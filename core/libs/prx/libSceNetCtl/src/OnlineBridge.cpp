#include "prx/libSceNetCtl/include/OnlineBridge.hpp"
#include "prx/libSceNetCtl/include/OnlineSocket.hpp"
#include <cstdio>
#include <cstring>
#include <vector>

namespace Online {

namespace {

bool readExact(Net::Handle socket, std::uint8_t* out, std::size_t size) {
    std::size_t done = 0;
    while (done < size) {
        const auto got = Net::Receive(socket, out + done, size - done);
        if (got <= 0) return false;
        done += static_cast<std::size_t>(got);
    }
    return true;
}

bool writeAll(Net::Handle socket, const std::uint8_t* bytes, std::size_t size) {
    std::size_t done = 0;
    while (done < size) {
        const auto sent = Net::Send(socket, bytes + done, size - done);
        if (sent <= 0) return false;
        done += static_cast<std::size_t>(sent);
    }
    return true;
}

struct Frame {
    Wire::Header header;
    std::vector<std::uint8_t> payload;
};

std::optional<Frame> readFrame(Net::Handle socket) {
    std::array<std::uint8_t, Wire::HeaderSize> head{};
    if (!readExact(socket, head.data(), head.size())) return std::nullopt;
    const auto header = Wire::DecodeHeader(head);
    if (!header) return std::nullopt;
    Frame frame{*header, std::vector<std::uint8_t>(header->length)};
    if (header->length != 0 && !readExact(socket, frame.payload.data(), frame.payload.size())) return std::nullopt;
    return frame;
}

}

Bridge::Bridge(std::uint16_t launcherPort, const Wire::Secret& secret, BridgeOptions options)
    : launcherPort(launcherPort), secret(secret), options(std::move(options)), started(std::chrono::steady_clock::now()) {
    worker = std::thread([this] { run(); });
    writer = std::thread([this] { writeLoop(); });
}

Bridge::~Bridge() {
    {
        std::lock_guard lock(mutex);
        stopping = true;
        if (liveSocket != Net::None) Net::ShutdownBoth(liveSocket);
    }
    changed.notify_all();
    outgoingChanged.notify_all();
    if (worker.joinable()) worker.join();
    if (writer.joinable()) writer.join();
}

namespace {
constexpr std::size_t MaxQueuedFrames = 1024;
constexpr std::size_t MaxQueuedBytes = 8u * 1024u * 1024u;
}

bool Bridge::SendDatagram(const Wire::Datagram& datagram) {
    if (datagram.data.size() > Wire::MaxDatagram) return false;
    auto frame = Wire::Frame(Wire::Type::Datagram, 0, 0, Wire::Encode(datagram));
    {
        std::lock_guard lock(mutex);
        if (!state.connected || liveSocket == Net::None) return false;
        if (outgoing.size() >= MaxQueuedFrames || outgoingBytes + frame.size() > MaxQueuedBytes) return false;
        outgoingBytes += frame.size();
        outgoing.push_back(std::move(frame));
    }
    outgoingChanged.notify_all();
    return true;
}

void Bridge::SetDatagramReceiver(std::function<void(const Wire::Datagram&)> receiver) {
    std::lock_guard lock(mutex);
    datagramReceiver = std::move(receiver);
}

bool Bridge::SendStream(const Wire::Stream& stream) {
    if (!Wire::IsStream(static_cast<std::uint16_t>(stream.type)) || stream.stream == 0 || stream.data.size() > Wire::MaxStreamData) return false;
    auto frame = Wire::Frame(stream.type, 0, 0, Wire::Encode(stream));
    {
        std::unique_lock lock(mutex);
        const auto socket = liveSocket;
        if (stream.type == Wire::Type::StreamData) {
            outgoingChanged.wait(lock, [&] { return stopping || !state.connected || liveSocket != socket || outgoingBytes + frame.size() <= MaxQueuedBytes; });
        }
        if (stopping || !state.connected || liveSocket == Net::None || liveSocket != socket) return false;
        outgoingBytes += frame.size();
        outgoing.push_back(std::move(frame));
    }
    outgoingChanged.notify_all();
    return true;
}

void Bridge::SetStreamReceiver(std::function<void(const Wire::Stream&)> receiver) {
    std::lock_guard lock(mutex);
    streamReceiver = std::move(receiver);
}

void Bridge::SetPushReceiver(std::function<void(const Wire::PushEvent&)> receiver) {
    std::lock_guard lock(mutex);
    pushReceiver = std::move(receiver);
}

void Bridge::writeLoop() {
    while (true) {
        std::vector<std::uint8_t> frame;
        Net::Handle socket = Net::None;
        {
            std::unique_lock lock(mutex);
            outgoingChanged.wait(lock, [this] { return stopping || !outgoing.empty(); });
            if (stopping) return;
            frame = std::move(outgoing.front());
            outgoing.pop_front();
            outgoingBytes -= frame.size();
            socket = liveSocket;
        }
        outgoingChanged.notify_all();
        if (socket == Net::None) continue;
        std::lock_guard writing(writeMutex);
        {
            std::lock_guard lock(mutex);
            if (liveSocket != socket) continue;
        }
        if (!writeAll(socket, frame.data(), frame.size())) Net::ShutdownBoth(socket);
    }
}

void Bridge::waitForFirstAccount(std::unique_lock<std::mutex>& lock) {
    changed.wait_until(lock, started + options.firstAccount, [this] { return accountSeen || gaveUp || stopping; });
}

AccountState Bridge::Account() {
    std::unique_lock lock(mutex);
    waitForFirstAccount(lock);
    return state;
}

std::optional<Wire::Refuse> Bridge::Refusal() {
    std::lock_guard lock(mutex);
    return refusal;
}

std::optional<Wire::WebReply> Bridge::Web(const Wire::WebRequest& request, std::chrono::milliseconds timeout) {
    const auto payload = Wire::Encode(request);
    Pending entry;
    std::uint32_t call = 0;
    Net::Handle socket = Net::None;
    {
        std::unique_lock lock(mutex);
        waitForFirstAccount(lock);
        if (!state.connected || liveSocket == Net::None) return std::nullopt;
        socket = liveSocket;
        do {
            call = ++lastCall;
        } while (call == 0 || pending.contains(call));
        pending.emplace(call, &entry);
    }
    std::optional<Wire::WebReply> reply;
    if (send(socket, Wire::Type::WebRequest, 0, call, payload)) {
        std::unique_lock lock(mutex);
        changed.wait_for(lock, timeout, [&entry] { return entry.done; });
        reply = std::move(entry.reply);
    }
    std::lock_guard lock(mutex);
    pending.erase(call);
    return reply;
}

void Bridge::Observe(std::string_view line) {
    Net::Handle socket = Net::None;
    {
        std::lock_guard lock(mutex);
        if (!state.connected || liveSocket == Net::None) return;
        socket = liveSocket;
    }
    Wire::Writer writer;
    if (line.size() > 0xffff) line = line.substr(0, 0xffff);
    writer.Str(line);
    send(socket, Wire::Type::Observation, 0, 0, writer.Data());
}

bool Bridge::send(Net::Handle socket, Wire::Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload) {
    const auto frame = Wire::Frame(type, flags, call, payload);
    std::lock_guard writing(writeMutex);
    {
        std::lock_guard lock(mutex);
        if (liveSocket != socket) return false;
    }
    if (writeAll(socket, frame.data(), frame.size())) return true;
    Net::ShutdownBoth(socket);
    return false;
}

Net::Handle Bridge::connectToLauncher() {
    const auto socket = Net::OpenTcp();
    if (socket == Net::None) return Net::None;
    Net::SetNoDelay(socket);
    if (!Net::ConnectLoopback(socket, launcherPort)) {
        Net::Close(socket);
        return Net::None;
    }
    return socket;
}

bool Bridge::handshake(Net::Handle socket) {
    Net::SetReceiveTimeout(socket, options.handshake);
    Wire::Hello hello;
    hello.nonce = Wire::RandomNonce();
    hello.build = options.build;
    hello.pid = Net::ProcessId();
    if (!send(socket, Wire::Type::Hello, 0, 0, Wire::Encode(hello))) return false;
    const auto answer = readFrame(socket);
    if (!answer) return false;
    if (answer->header.type == static_cast<std::uint16_t>(Wire::Type::Refuse)) {
        const auto refuse = Wire::DecodeRefuse(answer->payload);
        std::lock_guard lock(mutex);
        refusal = refuse.value_or(Wire::Refuse{Wire::RefuseReason::BadProof, "malformed refusal"});
        if (refusal->reason == Wire::RefuseReason::BadProof || refusal->reason == Wire::RefuseReason::Protocol) gaveUp = true;
        changed.notify_all();
        std::fprintf(stderr, "online bridge: the launcher refused this game (%u): %s\n", static_cast<unsigned>(refusal->reason), refusal->text.c_str());
        return false;
    }
    if (answer->header.type != static_cast<std::uint16_t>(Wire::Type::Welcome)) return false;
    const auto welcome = Wire::DecodeWelcome(answer->payload);
    if (!welcome) return false;
    if (welcome->protocol != Wire::Protocol) {
        std::fprintf(stderr, "online bridge: the launcher speaks protocol %u, this engine %u\n", welcome->protocol, Wire::Protocol);
        std::lock_guard lock(mutex);
        gaveUp = true;
        changed.notify_all();
        return false;
    }
    if (!Wire::SameProof(welcome->proof, Wire::MakeProof(secret, Wire::Side::Launcher, hello.nonce, welcome->nonce))) {
        if (!warnedImpostor) std::fprintf(stderr, "online bridge: the program on the launcher's port does not know this game's secret\n");
        warnedImpostor = true;
        return false;
    }
    if (!send(socket, Wire::Type::Proof, 0, 0, Wire::Encode(Wire::MakeProof(secret, Wire::Side::Engine, hello.nonce, welcome->nonce)))) return false;
    Net::SetReceiveTimeout(socket, std::chrono::milliseconds(0));
    return true;
}

void Bridge::dispatch(const Wire::Header& header, std::span<const std::uint8_t> payload, Net::Handle socket) {
    const bool reply = (header.flags & Wire::FlagReply) != 0;
    if (reply) {
        if (header.type != static_cast<std::uint16_t>(Wire::Type::WebRequest)) return;
        std::optional<Wire::WebReply> decoded;
        if ((header.flags & Wire::FlagUnsupported) == 0) decoded = Wire::DecodeWebReply(payload);
        std::lock_guard lock(mutex);
        const auto found = pending.find(header.call);
        if (found == pending.end()) return;
        found->second->reply = std::move(decoded);
        found->second->done = true;
        changed.notify_all();
        return;
    }
    if (header.type == static_cast<std::uint16_t>(Wire::Type::Datagram)) {
        const auto datagram = Wire::DecodeDatagram(payload);
        if (!datagram) return;
        std::function<void(const Wire::Datagram&)> receiver;
        {
            std::lock_guard lock(mutex);
            receiver = datagramReceiver;
        }
        if (receiver) receiver(*datagram);
        return;
    }
    if (Wire::IsStream(header.type)) {
        const auto stream = Wire::DecodeStream(static_cast<Wire::Type>(header.type), payload);
        if (!stream) return;
        std::function<void(const Wire::Stream&)> receiver;
        {
            std::lock_guard lock(mutex);
            receiver = streamReceiver;
        }
        if (receiver) receiver(*stream);
        return;
    }
    if (header.type == static_cast<std::uint16_t>(Wire::Type::PushEvent)) {
        const auto event = Wire::DecodePushEvent(payload);
        if (!event) return;
        std::function<void(const Wire::PushEvent&)> receiver;
        {
            std::lock_guard lock(mutex);
            receiver = pushReceiver;
        }
        if (receiver) receiver(*event);
        return;
    }
    if (header.type == static_cast<std::uint16_t>(Wire::Type::Account)) {
        const auto account = Wire::DecodeAccount(payload);
        if (!account) return;
        std::lock_guard lock(mutex);
        const bool same = accountSeen && state.account.signedIn == account->signedIn && state.account.accountId == account->accountId &&
            state.account.onlineId == account->onlineId && state.account.country == account->country &&
            state.account.language == account->language && state.account.age == account->age &&
            state.account.address == account->address && state.account.nat == account->nat;
        state.account = *account;
        state.connected = true;
        if (!same) ++state.generation;
        accountSeen = true;
        changed.notify_all();
        return;
    }
    if (header.call != 0) send(socket, static_cast<Wire::Type>(header.type), Wire::FlagReply | Wire::FlagUnsupported, header.call, {});
}

void Bridge::readLoop(Net::Handle socket) {
    while (true) {
        auto frame = readFrame(socket);
        if (!frame) return;
        dispatch(frame->header, frame->payload, socket);
    }
}

void Bridge::disconnect(Net::Handle socket) {
    std::function<void(const Wire::Stream&)> receiver;
    {
        std::lock_guard lock(mutex);
        if (liveSocket == socket) liveSocket = Net::None;
        if (state.account.signedIn || state.connected) {
            state.account = {};
            state.connected = false;
            ++state.generation;
        }
        for (auto& [call, entry] : pending) entry->done = true;
        outgoing.clear();
        outgoingBytes = 0;
        changed.notify_all();
        receiver = streamReceiver;
    }
    outgoingChanged.notify_all();
    if (receiver) {
        Wire::Stream ended;
        ended.type = Wire::Type::StreamClose;
        ended.reason = Wire::StreamCloseReason::Reset;
        receiver(ended);
    }
    std::lock_guard writing(writeMutex);
    Net::Close(socket);
}

void Bridge::run() {
    while (true) {
        {
            std::lock_guard lock(mutex);
            if (stopping || gaveUp) return;
        }
        const auto socket = connectToLauncher();
        if (socket != Net::None) {
            bool proceed = false;
            {
                std::lock_guard lock(mutex);
                if (!stopping) {
                    liveSocket = socket;
                    proceed = true;
                }
            }
            if (proceed && handshake(socket)) readLoop(socket);
            disconnect(socket);
        }
        std::unique_lock lock(mutex);
        changed.wait_for(lock, options.retry, [this] { return stopping || gaveUp; });
    }
}

}
