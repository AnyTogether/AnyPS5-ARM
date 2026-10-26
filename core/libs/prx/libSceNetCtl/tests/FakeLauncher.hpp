#ifndef CORE_LIBS_PRX_LIBSCENETCTL_TESTS_FAKELAUNCHER_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_TESTS_FAKELAUNCHER_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include "prx/libSceNetCtl/include/OnlineSocketHandle.hpp"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace Online::Testing {

// setenv, and _putenv_s on Windows, which has no setenv.
void SetEnvironment(const char* name, const std::string& value);

class FakeLauncher {
public:
    using WebHandler = std::function<std::optional<Wire::WebReply>(const Wire::WebRequest&)>;
    using DatagramHandler = std::function<std::optional<Wire::Datagram>(const Wire::Datagram&)>;

    explicit FakeLauncher(const Wire::Secret& secret);
    ~FakeLauncher();
    FakeLauncher(const FakeLauncher&) = delete;
    FakeLauncher& operator=(const FakeLauncher&) = delete;

    std::uint16_t Port() const { return port; }
    void SetAccount(const Wire::Account& account);
    void SetWebHandler(WebHandler handler);
    void SetDatagramHandler(DatagramHandler handler);
    bool WaitForDatagrams(std::size_t count, std::chrono::milliseconds timeout);
    std::vector<Wire::Datagram> Datagrams();
    // Streams: every stream frame the engine sends is kept. With loopback on, the fake is both
    // launchers and the other player's engine is this one: a stream the engine opens to a peer
    // comes back to the engine as one from that peer, and everything after it goes across.
    void SetStreamLoopback(bool on);
    bool WaitForStreams(std::size_t count, std::chrono::milliseconds timeout);
    std::vector<Wire::Stream> Streams();
    void SetRefusal(std::optional<Wire::Refuse> refuse);
    void SetProofSecret(const Wire::Secret& secret);
    void DropClient();
    void SendRaw(const std::vector<std::uint8_t>& bytes);
    void Send(Wire::Type type, std::uint16_t flags, std::uint32_t call, const std::vector<std::uint8_t>& payload);

    bool WaitForSessions(int count, std::chrono::milliseconds timeout);
    bool WaitForObservations(std::size_t count, std::chrono::milliseconds timeout);
    bool WaitForUnsupported(std::uint32_t call, std::chrono::milliseconds timeout);
    int Sessions();
    int ProvenSessions();
    std::optional<Wire::Hello> LastHello();
    std::vector<std::string> Observations();

private:
    void acceptLoop();
    void serve(Net::Handle client);
    void answer(Net::Handle client, Wire::WebRequest request, std::uint32_t call);
    bool write(Net::Handle client, const std::vector<std::uint8_t>& frame);

    Wire::Secret secret;
    Wire::Secret proofSecret;
    Net::Handle listener = Net::None;
    std::uint16_t port = 0;
    std::atomic<bool> stopping{false};

    std::mutex mutex;
    std::condition_variable changed;
    Wire::Account account;
    WebHandler webHandler;
    DatagramHandler datagramHandler;
    std::vector<Wire::Datagram> datagrams;
    bool streamLoopback = false;
    std::vector<Wire::Stream> streams;
    std::optional<Wire::Refuse> refusal;
    Net::Handle client = Net::None;
    int sessions = 0;
    int provenSessions = 0;
    std::optional<Wire::Hello> lastHello;
    std::vector<std::string> observations;
    std::vector<std::uint32_t> unsupported;
    std::vector<std::thread> answering;

    std::mutex writeMutex;
    std::thread acceptor;
};

}

#endif
