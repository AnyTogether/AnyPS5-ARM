#include "prx/libSceNetCtl/include/OnlineBridge.hpp"
#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <vector>

namespace Online {

namespace {

#ifdef MSG_NOSIGNAL
constexpr int SendFlags = MSG_NOSIGNAL;
#else
constexpr int SendFlags = 0;
#endif

bool readExact(int socket, std::uint8_t* out, std::size_t size) {
    std::size_t done = 0;
    while (done < size) {
        const auto got = ::recv(socket, out + done, size - done, 0);
        if (got > 0) {
            done += static_cast<std::size_t>(got);
            continue;
        }
        if (got < 0 && errno == EINTR) continue;
        return false;
    }
    return true;
}

bool writeAll(int socket, const std::uint8_t* bytes, std::size_t size) {
    std::size_t done = 0;
    while (done < size) {
        const auto sent = ::send(socket, bytes + done, size - done, SendFlags);
        if (sent > 0) {
            done += static_cast<std::size_t>(sent);
            continue;
        }
        if (sent < 0 && errno == EINTR) continue;
        return false;
    }
    return true;
}

void setReceiveTimeout(int socket, std::chrono::milliseconds timeout) {
    timeval value{};
    value.tv_sec = static_cast<decltype(value.tv_sec)>(timeout.count() / 1000);
    value.tv_usec = static_cast<decltype(value.tv_usec)>((timeout.count() % 1000) * 1000);
    ::setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &value, sizeof(value));
}

struct Frame {
    Wire::Header header;
    std::vector<std::uint8_t> payload;
};

std::optional<Frame> readFrame(int socket) {
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
        if (liveSocket >= 0) ::shutdown(liveSocket, SHUT_RDWR);
    }
    changed.notify_all();
    outgoingChanged.notify_all();
    if (worker.joinable()) worker.join();
    if (writer.joinable()) writer.join();
}

bool Bridge::SendDatagram(const Wire::Datagram& datagram) {
    constexpr std::size_t MaxQueuedFrames = 1024;
    constexpr std::size_t MaxQueuedBytes = 8u * 1024u * 1024u;
    if (datagram.data.size() > Wire::MaxDatagram) return false;
    auto frame = Wire::Frame(Wire::Type::Datagram, 0, 0, Wire::Encode(datagram));
    {
        std::lock_guard lock(mutex);
        if (!state.connected || liveSocket < 0) return false;
        if (outgoing.size() >= MaxQueuedFrames || outgoingBytes + frame.size() > MaxQueuedBytes) return false;
        outgoingBytes += frame.size();
        outgoing.push_back(std::move(frame));
    }
    outgoingChanged.notify_one();
    return true;
}

void Bridge::SetDatagramReceiver(std::function<void(const Wire::Datagram&)> receiver) {
    std::lock_guard lock(mutex);
    datagramReceiver = std::move(receiver);
}

void Bridge::writeLoop() {
    while (true) {
        std::vector<std::uint8_t> frame;
        int socket = -1;
        {
            std::unique_lock lock(mutex);
            outgoingChanged.wait(lock, [this] { return stopping || !outgoing.empty(); });
            if (stopping) return;
            frame = std::move(outgoing.front());
            outgoing.pop_front();
            outgoingBytes -= frame.size();
            socket = liveSocket;
        }
        if (socket < 0) continue;
        std::lock_guard writing(writeMutex);
        {
            std::lock_guard lock(mutex);
            if (liveSocket != socket) continue;
        }
        if (!writeAll(socket, frame.data(), frame.size())) ::shutdown(socket, SHUT_RDWR);
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
    int socket = -1;
    {
        std::unique_lock lock(mutex);
        waitForFirstAccount(lock);
        if (!state.connected || liveSocket < 0) return std::nullopt;
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
    int socket = -1;
    {
        std::lock_guard lock(mutex);
        if (!state.connected || liveSocket < 0) return;
        socket = liveSocket;
    }
    Wire::Writer writer;
    if (line.size() > 0xffff) line = line.substr(0, 0xffff);
    writer.Str(line);
    send(socket, Wire::Type::Observation, 0, 0, writer.Data());
}

bool Bridge::send(int socket, Wire::Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload) {
    const auto frame = Wire::Frame(type, flags, call, payload);
    std::lock_guard writing(writeMutex);
    {
        std::lock_guard lock(mutex);
        if (liveSocket != socket) return false;
    }
    if (writeAll(socket, frame.data(), frame.size())) return true;
    ::shutdown(socket, SHUT_RDWR);
    return false;
}

int Bridge::connectToLauncher() {
    const int socket = ::socket(AF_INET, SOCK_STREAM, 0);
    if (socket < 0) return -1;
    const int one = 1;
    ::setsockopt(socket, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    ::setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(launcherPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::connect(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        ::close(socket);
        return -1;
    }
    return socket;
}

bool Bridge::handshake(int socket) {
    setReceiveTimeout(socket, options.handshake);
    Wire::Hello hello;
    hello.nonce = Wire::RandomNonce();
    hello.build = options.build;
    hello.pid = static_cast<std::uint32_t>(::getpid());
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
    setReceiveTimeout(socket, std::chrono::milliseconds(0));
    return true;
}

void Bridge::dispatch(const Wire::Header& header, std::span<const std::uint8_t> payload, int socket) {
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

void Bridge::readLoop(int socket) {
    while (true) {
        auto frame = readFrame(socket);
        if (!frame) return;
        dispatch(frame->header, frame->payload, socket);
    }
}

void Bridge::disconnect(int socket) {
    {
        std::lock_guard lock(mutex);
        if (liveSocket == socket) liveSocket = -1;
        if (state.account.signedIn || state.connected) {
            state.account = {};
            state.connected = false;
            ++state.generation;
        }
        for (auto& [call, entry] : pending) entry->done = true;
        outgoing.clear();
        outgoingBytes = 0;
        changed.notify_all();
    }
    std::lock_guard writing(writeMutex);
    ::close(socket);
}

void Bridge::run() {
    while (true) {
        {
            std::lock_guard lock(mutex);
            if (stopping || gaveUp) return;
        }
        const int socket = connectToLauncher();
        if (socket >= 0) {
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
