#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINEBRIDGE_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINEBRIDGE_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include "prx/libSceNetCtl/include/OnlineSocketHandle.hpp"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <cstdint>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>

namespace Online {

struct BridgeOptions {
    std::chrono::milliseconds retry{2000};
    std::chrono::milliseconds firstAccount{2000};
    std::chrono::milliseconds handshake{5000};
    std::string build = "unknown";
};

struct AccountState {
    Wire::Account account;
    std::uint64_t generation = 0;
    bool connected = false;
};

class Bridge {
public:
    Bridge(std::uint16_t launcherPort, const Wire::Secret& secret, BridgeOptions options = {});
    ~Bridge();
    Bridge(const Bridge&) = delete;
    Bridge& operator=(const Bridge&) = delete;

    AccountState Account();
    std::optional<Wire::WebReply> Web(const Wire::WebRequest& request, std::chrono::milliseconds timeout);
    void Observe(std::string_view line);
    std::optional<Wire::Refuse> Refusal();
    bool SendDatagram(const Wire::Datagram& datagram);
    void SetDatagramReceiver(std::function<void(const Wire::Datagram&)> receiver);
    void SetPushReceiver(std::function<void(const Wire::PushEvent&)> receiver);
    // Stream frames keep their order with each other and with datagrams. StreamData waits while half
    // the queue to the launcher is full (the game's socket then fills up, as TCP would); the
    // other stream frames never wait. False while no launcher is connected.
    bool SendStream(const Wire::Stream& stream);
    // Gets the launcher's stream frames on the reader thread, and a StreamClose (Reset) for
    // stream 0 when the connection drops: every open stream ended with it.
    void SetStreamReceiver(std::function<void(const Wire::Stream&)> receiver);

private:
    struct Pending {
        bool done = false;
        std::optional<Wire::WebReply> reply;
    };

    void run();
    Net::Handle connectToLauncher();
    bool handshake(Net::Handle socket);
    void readLoop(Net::Handle socket);
    void dispatch(const Wire::Header& header, std::span<const std::uint8_t> payload, Net::Handle socket);
    void disconnect(Net::Handle socket);
    bool send(Net::Handle socket, Wire::Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload);
    void waitForFirstAccount(std::unique_lock<std::mutex>& lock);
    void writeLoop();

    const std::uint16_t launcherPort;
    const Wire::Secret secret;
    const BridgeOptions options;
    const std::chrono::steady_clock::time_point started;

    std::mutex mutex;
    std::condition_variable changed;
    AccountState state;
    bool accountSeen = false;
    bool stopping = false;
    bool gaveUp = false;
    bool warnedImpostor = false;
    Net::Handle liveSocket = Net::None;
    std::optional<Wire::Refuse> refusal;
    std::uint32_t lastCall = 0;
    std::map<std::uint32_t, Pending*> pending;

    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t outgoingBytes = 0;
    std::condition_variable outgoingChanged;
    std::function<void(const Wire::Datagram&)> datagramReceiver;
    std::function<void(const Wire::PushEvent&)> pushReceiver;
    std::function<void(const Wire::Stream&)> streamReceiver;

    std::mutex writeMutex;
    std::thread worker;
    std::thread writer;
};

}

#endif
