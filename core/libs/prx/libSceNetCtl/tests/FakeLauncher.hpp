#ifndef CORE_LIBS_PRX_LIBSCENETCTL_TESTS_FAKELAUNCHER_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_TESTS_FAKELAUNCHER_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
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

class FakeLauncher {
public:
    using WebHandler = std::function<std::optional<Wire::WebReply>(const Wire::WebRequest&)>;

    explicit FakeLauncher(const Wire::Secret& secret);
    ~FakeLauncher();
    FakeLauncher(const FakeLauncher&) = delete;
    FakeLauncher& operator=(const FakeLauncher&) = delete;

    std::uint16_t Port() const { return port; }
    void SetAccount(const Wire::Account& account);
    void SetWebHandler(WebHandler handler);
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
    void serve(int client);
    void answer(int client, Wire::WebRequest request, std::uint32_t call);
    bool write(int client, const std::vector<std::uint8_t>& frame);

    Wire::Secret secret;
    Wire::Secret proofSecret;
    int listener = -1;
    std::uint16_t port = 0;
    std::atomic<bool> stopping{false};

    std::mutex mutex;
    std::condition_variable changed;
    Wire::Account account;
    WebHandler webHandler;
    std::optional<Wire::Refuse> refusal;
    int client = -1;
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
