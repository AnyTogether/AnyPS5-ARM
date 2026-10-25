#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINEBRIDGE_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINEBRIDGE_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
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

private:
    struct Pending {
        bool done = false;
        std::optional<Wire::WebReply> reply;
    };

    void run();
    int connectToLauncher();
    bool handshake(int socket);
    void readLoop(int socket);
    void dispatch(const Wire::Header& header, std::span<const std::uint8_t> payload, int socket);
    void disconnect(int socket);
    bool send(int socket, Wire::Type type, std::uint16_t flags, std::uint32_t call, std::span<const std::uint8_t> payload);
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
    int liveSocket = -1;
    std::optional<Wire::Refuse> refusal;
    std::uint32_t lastCall = 0;
    std::map<std::uint32_t, Pending*> pending;

    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t outgoingBytes = 0;
    std::condition_variable outgoingChanged;
    std::function<void(const Wire::Datagram&)> datagramReceiver;
    std::function<void(const Wire::PushEvent&)> pushReceiver;

    std::mutex writeMutex;
    std::thread worker;
    std::thread writer;
};

}

#endif
