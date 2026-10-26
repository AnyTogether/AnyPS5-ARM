#include "FakeLauncher.hpp"
#include "prx/libSceNetCtl/include/OnlineSocket.hpp"
#include <cstdlib>
#include <stdexcept>

namespace Online::Testing {

void SetEnvironment(const char* name, const std::string& value) {
#ifdef _WIN32
    ::_putenv_s(name, value.c_str());
#else
    ::setenv(name, value.c_str(), 1);
#endif
}

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

FakeLauncher::FakeLauncher(const Wire::Secret& secret) : secret(secret), proofSecret(secret) {
    listener = Net::OpenTcp();
    if (listener == Net::None) throw std::runtime_error("fake launcher: no socket");
    const auto listening = Net::ListenLoopback(listener, 4);
    if (!listening) {
        Net::Close(listener);
        throw std::runtime_error("fake launcher: cannot listen on 127.0.0.1");
    }
    port = *listening;
    acceptor = std::thread([this] { acceptLoop(); });
}

FakeLauncher::~FakeLauncher() {
    stopping = true;
    DropClient();
    if (acceptor.joinable()) acceptor.join();
    std::vector<std::thread> threads;
    {
        std::lock_guard lock(mutex);
        threads.swap(answering);
    }
    for (auto& thread : threads) thread.join();
    Net::Close(listener);
}

void FakeLauncher::SetAccount(const Wire::Account& value) {
    Net::Handle live = Net::None;
    {
        std::lock_guard lock(mutex);
        account = value;
        if (provenSessions > 0) live = client;
    }
    if (live != Net::None) write(live, Wire::Frame(Wire::Type::Account, 0, 0, Wire::Encode(value)));
}

void FakeLauncher::SetWebHandler(WebHandler handler) {
    std::lock_guard lock(mutex);
    webHandler = std::move(handler);
}

void FakeLauncher::SetDatagramHandler(DatagramHandler handler) {
    std::lock_guard lock(mutex);
    datagramHandler = std::move(handler);
}

bool FakeLauncher::WaitForDatagrams(std::size_t count, std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, timeout, [&] { return datagrams.size() >= count; });
}

std::vector<Wire::Datagram> FakeLauncher::Datagrams() {
    std::lock_guard lock(mutex);
    return datagrams;
}

void FakeLauncher::SetRefusal(std::optional<Wire::Refuse> refuse) {
    std::lock_guard lock(mutex);
    refusal = std::move(refuse);
}

void FakeLauncher::SetProofSecret(const Wire::Secret& value) {
    std::lock_guard lock(mutex);
    proofSecret = value;
}

void FakeLauncher::DropClient() {
    std::lock_guard lock(mutex);
    if (client != Net::None) Net::ShutdownBoth(client);
}

void FakeLauncher::SendRaw(const std::vector<std::uint8_t>& bytes) {
    Net::Handle live = Net::None;
    {
        std::lock_guard lock(mutex);
        live = client;
    }
    if (live != Net::None) write(live, bytes);
}

void FakeLauncher::Send(Wire::Type type, std::uint16_t flags, std::uint32_t call, const std::vector<std::uint8_t>& payload) {
    SendRaw(Wire::Frame(type, flags, call, payload));
}

bool FakeLauncher::write(Net::Handle socket, const std::vector<std::uint8_t>& frame) {
    std::lock_guard lock(writeMutex);
    std::size_t done = 0;
    while (done < frame.size()) {
        const auto sent = Net::Send(socket, frame.data() + done, frame.size() - done);
        if (sent <= 0) return false;
        done += static_cast<std::size_t>(sent);
    }
    return true;
}

bool FakeLauncher::WaitForSessions(int count, std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, timeout, [&] { return provenSessions >= count; });
}

bool FakeLauncher::WaitForObservations(std::size_t count, std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, timeout, [&] { return observations.size() >= count; });
}

bool FakeLauncher::WaitForUnsupported(std::uint32_t call, std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, timeout, [&] {
        for (const auto value : unsupported) {
            if (value == call) return true;
        }
        return false;
    });
}

int FakeLauncher::Sessions() {
    std::lock_guard lock(mutex);
    return sessions;
}

int FakeLauncher::ProvenSessions() {
    std::lock_guard lock(mutex);
    return provenSessions;
}

std::optional<Wire::Hello> FakeLauncher::LastHello() {
    std::lock_guard lock(mutex);
    return lastHello;
}

std::vector<std::string> FakeLauncher::Observations() {
    std::lock_guard lock(mutex);
    return observations;
}

void FakeLauncher::acceptLoop() {
    while (!stopping) {
        if (!Net::WaitReadable(listener, 20)) continue;
        const auto accepted = Net::Accept(listener);
        if (accepted == Net::None) continue;
        {
            std::lock_guard lock(mutex);
            client = accepted;
        }
        serve(accepted);
        {
            std::lock_guard lock(mutex);
            client = Net::None;
        }
        Net::Close(accepted);
    }
}

void FakeLauncher::serve(Net::Handle socket) {
    const auto first = readFrame(socket);
    if (!first || first->header.type != static_cast<std::uint16_t>(Wire::Type::Hello)) return;
    const auto hello = Wire::DecodeHello(first->payload);
    if (!hello) return;
    std::optional<Wire::Refuse> refuse;
    Wire::Secret signing{};
    {
        std::lock_guard lock(mutex);
        lastHello = hello;
        ++sessions;
        refuse = refusal;
        signing = proofSecret;
        changed.notify_all();
    }
    if (refuse) {
        write(socket, Wire::Frame(Wire::Type::Refuse, 0, 0, Wire::Encode(*refuse)));
        return;
    }
    Wire::Welcome welcome;
    welcome.nonce = Wire::RandomNonce();
    welcome.proof = Wire::MakeProof(signing, Wire::Side::Launcher, hello->nonce, welcome.nonce);
    if (!write(socket, Wire::Frame(Wire::Type::Welcome, 0, 0, Wire::Encode(welcome)))) return;
    const auto proofFrame = readFrame(socket);
    if (!proofFrame || proofFrame->header.type != static_cast<std::uint16_t>(Wire::Type::Proof)) return;
    const auto proof = Wire::DecodeProof(proofFrame->payload);
    if (!proof || !Wire::SameProof(*proof, Wire::MakeProof(secret, Wire::Side::Engine, hello->nonce, welcome.nonce))) {
        write(socket, Wire::Frame(Wire::Type::Refuse, 0, 0, Wire::Encode(Wire::Refuse{Wire::RefuseReason::BadProof, "bad proof"})));
        return;
    }
    Wire::Account current;
    {
        std::lock_guard lock(mutex);
        ++provenSessions;
        current = account;
    }
    write(socket, Wire::Frame(Wire::Type::Account, 0, 0, Wire::Encode(current)));
    {
        std::lock_guard lock(mutex);
        changed.notify_all();
    }
    while (true) {
        auto frame = readFrame(socket);
        if (!frame) return;
        const auto type = frame->header.type;
        if ((frame->header.flags & Wire::FlagReply) != 0) {
            if ((frame->header.flags & Wire::FlagUnsupported) != 0) {
                std::lock_guard lock(mutex);
                unsupported.push_back(frame->header.call);
                changed.notify_all();
            }
            continue;
        }
        if (type == static_cast<std::uint16_t>(Wire::Type::Observation)) {
            Wire::Reader reader(frame->payload);
            auto line = reader.Str();
            std::lock_guard lock(mutex);
            observations.push_back(std::move(line));
            changed.notify_all();
            continue;
        }
        if (type == static_cast<std::uint16_t>(Wire::Type::Datagram)) {
            Wire::Reader reader(frame->payload);
            Wire::Datagram datagram;
            datagram.peer = reader.U32();
            datagram.peerPort = reader.U16();
            datagram.peerVport = reader.U16();
            datagram.localPort = reader.U16();
            datagram.localVport = reader.U16();
            datagram.kind = static_cast<Wire::DatagramKind>(reader.U8());
            datagram.data = reader.Bytes();
            if (!reader.Ok()) continue;
            DatagramHandler handler;
            {
                std::lock_guard lock(mutex);
                datagrams.push_back(datagram);
                handler = datagramHandler;
                changed.notify_all();
            }
            if (handler) {
                if (const auto reply = handler(datagram)) write(socket, Wire::Frame(Wire::Type::Datagram, 0, 0, Wire::Encode(*reply)));
            }
            continue;
        }
        if (type == static_cast<std::uint16_t>(Wire::Type::WebRequest)) {
            auto request = Wire::DecodeWebRequest(frame->payload);
            if (!request) continue;
            const auto call = frame->header.call;
            std::lock_guard lock(mutex);
            answering.emplace_back([this, socket, call, request = std::move(*request)]() mutable { answer(socket, std::move(request), call); });
        }
    }
}

void FakeLauncher::answer(Net::Handle socket, Wire::WebRequest request, std::uint32_t call) {
    WebHandler handler;
    {
        std::lock_guard lock(mutex);
        handler = webHandler;
    }
    const auto reply = handler ? handler(request) : std::nullopt;
    if (reply) {
        write(socket, Wire::Frame(Wire::Type::WebRequest, Wire::FlagReply, call, Wire::Encode(*reply)));
    } else {
        write(socket, Wire::Frame(Wire::Type::WebRequest, Wire::FlagReply | Wire::FlagUnsupported, call, {}));
    }
}

}
