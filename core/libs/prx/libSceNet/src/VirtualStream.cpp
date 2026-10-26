#include "prx/libSceNet/include/VirtualStream.hpp"
#include "prx/libSceNetCtl/include/Online.hpp"
#include "prx/libSceNetCtl/include/OnlineSocket.hpp"
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

namespace VirtualStream {

namespace {

namespace Wire = Online::Wire;
namespace Net = Online::Net;

// Bytes from the launcher wait for the game here; a game that stops reading for this long breaks
// its stream rather than the engine's memory.
constexpr std::size_t MaxQueued = 16u * 1024u * 1024u;
constexpr std::size_t ReadChunk = 16u * 1024u;

struct Stream {
    std::uint32_t id = 0;
    std::mutex mutex;
    std::condition_variable changed;
    Net::Handle socket = Net::None;
    std::deque<std::vector<std::uint8_t>> queue;
    std::size_t queued = 0;
    // Opening: the peer's answer.
    bool answered = false;
    bool accepted = false;
    // The launcher ended the stream (after the bytes queued before it).
    bool remoteEnded = false;
    Wire::StreamCloseReason remoteReason = Wire::StreamCloseReason::Closed;
    // Broken: both directions end now, the game's socket gets a reset.
    bool broken = false;
    // The game ended its side; the launcher was told.
    bool localEnded = false;
    int running = 0;
    // The port accept sees for a connection into a listener, kept until the stream ends.

    ~Stream() {
        if (socket != Net::None) Net::Close(socket);
    }
};

struct Listener {
    std::uint16_t nativePort = 0;
    int descriptor = -1;
};

std::mutex mutex;
std::map<std::pair<std::uint16_t, std::uint16_t>, Listener> listeners;
std::map<std::uint32_t, std::shared_ptr<Stream>> streams;
// Streams opened by the game whose socket has not connected to the relay listener yet, by the
// loopback port the socket is bound to.
std::map<std::uint16_t, std::uint32_t> connecting;
std::map<std::uint16_t, VirtualNet::Source> acceptedFrom;
std::uint32_t lastId = 0;
Net::Handle relay = Net::None;
std::uint16_t relayPort = 0;
bool receiving = false;

void send(const Wire::Stream& frame) {
    OnlineSendStream_nid_no_patch(frame);
}

void sendClose(std::uint32_t id, Wire::StreamCloseReason reason) {
    Wire::Stream frame;
    frame.type = Wire::Type::StreamClose;
    frame.stream = id;
    frame.reason = reason;
    send(frame);
}

void finished(const std::shared_ptr<Stream>& stream) {
    std::lock_guard lock(mutex);
    const auto found = streams.find(stream->id);
    if (found != streams.end() && found->second == stream) streams.erase(found);
    std::erase_if(connecting, [&](const auto& entry) { return entry.second == stream->id; });
}

// Marks a thread of the stream done; the last one forgets the stream (its socket closes with it).
void leave(const std::shared_ptr<Stream>& stream) {
    bool last = false;
    {
        std::lock_guard lock(stream->mutex);
        last = --stream->running == 0;
    }
    if (last) finished(stream);
}

void breakStream(Stream& stream) {
    std::lock_guard lock(stream.mutex);
    if (stream.broken) return;
    stream.broken = true;
    if (stream.socket != Net::None) {
        Net::ResetOnClose(stream.socket);
        Net::ShutdownBoth(stream.socket);
    }
    stream.changed.notify_all();
}

// Game -> launcher.
void readLoop(std::shared_ptr<Stream> stream) {
    std::vector<std::uint8_t> buffer(ReadChunk);
    while (true) {
        const auto got = Net::Receive(stream->socket, buffer.data(), buffer.size());
        {
            std::lock_guard lock(stream->mutex);
            if (stream->broken) break;
        }
        if (got <= 0) {
            {
                std::lock_guard lock(stream->mutex);
                stream->localEnded = true;
                stream->changed.notify_all();
            }
            sendClose(stream->id, got == 0 ? Wire::StreamCloseReason::Closed : Wire::StreamCloseReason::Reset);
            if (got < 0) breakStream(*stream);
            break;
        }
        Wire::Stream frame;
        frame.type = Wire::Type::StreamData;
        frame.stream = stream->id;
        frame.data.assign(buffer.begin(), buffer.begin() + got);
        if (!OnlineSendStream_nid_no_patch(frame)) {
            breakStream(*stream);
            break;
        }
    }
    leave(stream);
}

// Launcher -> game. Ends the game's writes side once the launcher ended the stream and every
// byte before that was written; the stream is done once both sides ended.
void writeLoop(std::shared_ptr<Stream> stream) {
    while (true) {
        std::vector<std::uint8_t> chunk;
        {
            std::unique_lock lock(stream->mutex);
            stream->changed.wait(lock, [&] { return stream->broken || !stream->queue.empty() || stream->remoteEnded; });
            if (stream->broken) break;
            if (stream->queue.empty()) {
                if (stream->remoteReason != Wire::StreamCloseReason::Closed) {
                    lock.unlock();
                    breakStream(*stream);
                    break;
                }
                Net::ShutdownWrite(stream->socket);
                // A half-closed stream lasts until the game ends its side too.
                stream->changed.wait(lock, [&] { return stream->broken || stream->localEnded; });
                break;
            }
            chunk = std::move(stream->queue.front());
            stream->queue.pop_front();
            stream->queued -= chunk.size();
        }
        std::size_t done = 0;
        while (done < chunk.size()) {
            const auto sent = Net::Send(stream->socket, chunk.data() + done, chunk.size() - done);
            if (sent <= 0) break;
            done += static_cast<std::size_t>(sent);
        }
        if (done < chunk.size()) {
            // The game closed its socket: what the peer still sends has nowhere to go.
            bool ended = false;
            {
                std::lock_guard lock(stream->mutex);
                ended = stream->localEnded;
            }
            if (!ended) sendClose(stream->id, Wire::StreamCloseReason::Reset);
            breakStream(*stream);
            break;
        }
    }
    leave(stream);
}

void start(const std::shared_ptr<Stream>& stream, Net::Handle socket) {
    {
        std::lock_guard lock(stream->mutex);
        stream->socket = socket;
        stream->running = 2;
        if (stream->broken) {
            Net::ResetOnClose(socket);
            Net::ShutdownBoth(socket);
        }
    }
    Net::SetNoDelay(socket);
    std::thread(readLoop, stream).detach();
    std::thread(writeLoop, stream).detach();
}

// The relay listener: pairs each game socket that connects with the stream it opened.
void relayLoop(Net::Handle listener) {
    while (true) {
        const auto accepted = Net::Accept(listener);
        if (accepted == Net::None) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }
        const auto port = Net::PeerPort(accepted);
        std::shared_ptr<Stream> stream;
        {
            std::lock_guard lock(mutex);
            const auto found = connecting.find(port);
            if (found != connecting.end()) {
                const auto opened = streams.find(found->second);
                if (opened != streams.end()) stream = opened->second;
                connecting.erase(found);
            }
        }
        if (!stream) {
            Net::Close(accepted);
            continue;
        }
        start(stream, accepted);
    }
}

void opened(const Wire::Stream& frame) {
    Listener listener;
    {
        std::lock_guard lock(mutex);
        const auto found = listeners.find({frame.localPort, frame.localVport});
        if (found == listeners.end() || streams.contains(frame.stream)) {
            listener.descriptor = -1;
        } else {
            listener = found->second;
        }
    }
    if (listener.descriptor < 0) return sendClose(frame.stream, Wire::StreamCloseReason::Refused);
    // The engine's end is bound before it connects, so the game's accept always finds who it is.
    const auto socket = Net::OpenTcp();
    if (socket == Net::None) return sendClose(frame.stream, Wire::StreamCloseReason::Refused);
    const auto port = Net::BindLoopback(socket);
    if (!port) {
        Net::Close(socket);
        return sendClose(frame.stream, Wire::StreamCloseReason::Refused);
    }
    {
        std::lock_guard lock(mutex);
        acceptedFrom[*port] = VirtualNet::Source{frame.peer, frame.peerPort, frame.peerVport};
    }
    if (!Net::ConnectLoopbackWithin(socket, listener.nativePort, 1000)) {
        Net::Close(socket);
        std::lock_guard lock(mutex);
        acceptedFrom.erase(*port);
        return sendClose(frame.stream, Wire::StreamCloseReason::Refused);
    }
    auto stream = std::make_shared<Stream>();
    stream->id = frame.stream;
    stream->answered = true;
    stream->accepted = true;
    {
        std::lock_guard lock(mutex);
        streams[frame.stream] = stream;
    }
    Wire::Stream accept;
    accept.type = Wire::Type::StreamAccept;
    accept.stream = frame.stream;
    send(accept);
    start(stream, socket);
}

void received(const Wire::Stream& frame) {
    if (frame.type == Wire::Type::StreamOpen) return opened(frame);
    std::vector<std::shared_ptr<Stream>> targets;
    {
        std::lock_guard lock(mutex);
        if (frame.stream == 0) {
            for (const auto& entry : streams) targets.push_back(entry.second);
        } else if (const auto found = streams.find(frame.stream); found != streams.end()) {
            targets.push_back(found->second);
        }
    }
    for (const auto& stream : targets) {
        bool overflow = false;
        {
            std::lock_guard lock(stream->mutex);
            switch (frame.type) {
            case Wire::Type::StreamAccept:
                stream->answered = true;
                stream->accepted = true;
                break;
            case Wire::Type::StreamData:
                if (stream->remoteEnded) break;
                if (stream->queued + frame.data.size() > MaxQueued) {
                    overflow = true;
                    break;
                }
                stream->queued += frame.data.size();
                stream->queue.push_back(frame.data);
                break;
            case Wire::Type::StreamClose:
                stream->answered = true;
                stream->remoteEnded = true;
                stream->remoteReason = frame.reason;
                break;
            default:
                break;
            }
            stream->changed.notify_all();
        }
        if (overflow) {
            std::fprintf(stderr, "[online] stream %u: the game left more than 16 MiB unread; the stream breaks\n", stream->id);
            sendClose(stream->id, Wire::StreamCloseReason::Reset);
            breakStream(*stream);
        } else if (frame.type == Wire::Type::StreamClose && frame.reason != Wire::StreamCloseReason::Closed) {
            // Refused or broken: nothing queued is delivered, the game's socket is reset.
            breakStream(*stream);
        }
    }
}

void dispatch(const Wire::Stream& frame) {
    received(frame);
}

// Under `mutex`.
bool prepare() {
    if (!receiving) {
        OnlineSetStreamReceiver_nid_no_patch(dispatch);
        receiving = true;
    }
    if (relay != Net::None) return true;
    const auto listener = Net::OpenTcp();
    if (listener == Net::None) return false;
    const auto port = Net::ListenLoopback(listener, 64);
    if (!port) {
        Net::Close(listener);
        return false;
    }
    relay = listener;
    relayPort = *port;
    std::thread(relayLoop, listener).detach();
    return true;
}

}

bool Listen(std::uint16_t port, std::uint16_t vport, std::uint16_t nativePort, int descriptor) {
    std::lock_guard lock(mutex);
    if (!prepare()) return false;
    const auto found = listeners.find({port, vport});
    if (found != listeners.end() && found->second.descriptor != descriptor) return false;
    listeners[{port, vport}] = Listener{nativePort, descriptor};
    return true;
}

void Forget(int descriptor) {
    std::lock_guard lock(mutex);
    std::erase_if(listeners, [descriptor](const auto& entry) { return entry.second.descriptor == descriptor; });
}

std::optional<Opening> Open(std::uint32_t peer, std::uint16_t peerPort, std::uint16_t peerVport, std::uint16_t localPort, std::uint16_t localVport,
                            std::uint16_t guestPort) {
    auto stream = std::make_shared<Stream>();
    Opening opening;
    {
        std::lock_guard lock(mutex);
        if (!prepare()) return std::nullopt;
        do {
            lastId = (lastId + 1) & ~Wire::LauncherStream;
        } while (lastId == 0 || streams.contains(lastId));
        stream->id = lastId;
        streams[lastId] = stream;
        connecting[guestPort] = lastId;
        opening = Opening{lastId, relayPort};
    }
    Wire::Stream frame;
    frame.type = Wire::Type::StreamOpen;
    frame.stream = opening.id;
    frame.peer = peer;
    frame.peerPort = peerPort;
    frame.peerVport = peerVport;
    frame.localPort = localPort;
    frame.localVport = localVport;
    if (!OnlineSendStream_nid_no_patch(frame)) {
        Abandon(opening.id);
        return std::nullopt;
    }
    return opening;
}

Answer Wait(std::uint32_t id, std::chrono::milliseconds timeout) {
    std::shared_ptr<Stream> stream;
    {
        std::lock_guard lock(mutex);
        const auto found = streams.find(id);
        if (found == streams.end()) return Answer::Broken;
        stream = found->second;
    }
    std::unique_lock lock(stream->mutex);
    if (!stream->changed.wait_for(lock, timeout, [&] { return stream->answered || stream->broken; })) return Answer::TimedOut;
    if (stream->accepted && !stream->broken) return Answer::Accepted;
    if (stream->remoteEnded && stream->remoteReason == Wire::StreamCloseReason::Refused) return Answer::Refused;
    return Answer::Broken;
}

void Abandon(std::uint32_t id) {
    std::shared_ptr<Stream> stream;
    {
        std::lock_guard lock(mutex);
        const auto found = streams.find(id);
        if (found == streams.end()) return;
        stream = found->second;
        streams.erase(found);
        std::erase_if(connecting, [id](const auto& entry) { return entry.second == id; });
    }
    bool told = false;
    {
        std::lock_guard lock(stream->mutex);
        told = stream->remoteEnded;
        stream->broken = true;
        stream->changed.notify_all();
    }
    if (!told) sendClose(id, Wire::StreamCloseReason::Reset);
}

std::optional<VirtualNet::Source> Accepted(std::uint16_t enginePort) {
    std::lock_guard lock(mutex);
    const auto found = acceptedFrom.find(enginePort);
    if (found == acceptedFrom.end()) return std::nullopt;
    const auto source = found->second;
    acceptedFrom.erase(found);
    return source;
}

}
