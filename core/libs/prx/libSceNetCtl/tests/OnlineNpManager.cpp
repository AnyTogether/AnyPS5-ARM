#include "FakeLauncher.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

extern "C" {
int APS5_VABI sceNpGetState(int userId, std::uint32_t* state);
int APS5_VABI sceNpGetOnlineId(int userId, NpOnlineId* onlineId);
int APS5_VABI sceNpGetNpId(int userId, NpId* npId);
int APS5_VABI sceNpGetAccountIdA(int userId, std::uint64_t* accountId);
int APS5_VABI sceNpGetAccountCountryA(int userId, void* countryCode);
int APS5_VABI sceNpHasSignedUp(int userId, bool* hasSignedUp);
int APS5_VABI sceNpGetUserIdByAccountId(std::uint64_t accountId, int* userId);
int APS5_VABI sceNpGetUserIdByOnlineId(const NpOnlineId* onlineId, int* userId);
int APS5_VABI sceNpGetAccountId(const NpOnlineId* onlineId, std::uint64_t* accountId);
int APS5_VABI sceNpCreateRequest(void);
int APS5_VABI sceNpDeleteRequest(int reqId);
int APS5_VABI sceNpCheckNpAvailabilityA(int reqId, int userId);
int APS5_VABI sceNpPollAsync(int reqId, int* result);
int APS5_VABI sceNpCheckPlus(int reqId, const void* param, void* result);
int APS5_VABI sceNpRegisterStateCallbackA(void* callback, void* userdata);
int APS5_VABI sceNpCheckCallback(void);
}

namespace {

using namespace std::chrono_literals;

constexpr int InitialUser = 0x10000000;
constexpr int SignedOut = static_cast<int>(0x80550006);
constexpr int UserNotFound = static_cast<int>(0x80550007);
constexpr std::uint64_t AccountId = 0x0123456789abcdefull;

std::atomic<int> lastState{0};
std::atomic<int> calls{0};

void APS5_VABI onState(int userId, std::uint32_t state, void*) {
    if (userId == InitialUser) lastState = static_cast<int>(state);
    ++calls;
}

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename TPredicate>
bool eventually(TPredicate predicate) {
    const auto until = std::chrono::steady_clock::now() + 5s;
    while (std::chrono::steady_clock::now() < until) {
        if (predicate()) return true;
        std::this_thread::sleep_for(10ms);
    }
    return predicate();
}

std::uint32_t state(int userId = InitialUser) {
    std::uint32_t value = 0;
    require(sceNpGetState(userId, &value) == 0, "sceNpGetState answers");
    return value;
}

NpOnlineId onlineId(const char* text) {
    NpOnlineId id{};
    std::strncpy(id.data, text, sizeof(id.data) - 1);
    return id;
}

}

int main() {
    try {
        Online::Wire::Secret secret{};
        for (std::size_t index = 0; index < secret.size(); ++index) secret[index] = static_cast<std::uint8_t>(0xA0 + index);
        Online::Testing::FakeLauncher launcher(secret);
        Online::Wire::Account account;
        account.signedIn = true;
        account.accountId = AccountId;
        account.onlineId = "anyps5-player";
        account.country = "tr";
        account.language = "tr";
        launcher.SetAccount(account);
        const std::string endpoint = "127.0.0.1:" + std::to_string(launcher.Port());
        std::string hex;
        static constexpr char digits[] = "0123456789abcdef";
        for (const auto byte : secret) {
            hex += digits[byte >> 4];
            hex += digits[byte & 15];
        }
        ::setenv("ANYPS5_ONLINE", endpoint.c_str(), 1);
        ::setenv("ANYPS5_ONLINE_SECRET", hex.c_str(), 1);

        require(sceNpRegisterStateCallbackA(reinterpret_cast<void*>(&onState), nullptr) > 0, "a state callback registers");
        require(sceNpCheckCallback() == 0 && lastState == 2, "the callback reports signed in");
        require(state() == 2, "the initial user is signed in");
        require(state(InitialUser + 1) == 1, "other local users stay signed out");

        NpOnlineId id{};
        require(sceNpGetOnlineId(InitialUser, &id) == 0 && std::string(id.data) == "anyps5-player", "the online ID is the launcher's handle");
        NpId npId{};
        require(sceNpGetNpId(InitialUser, &npId) == 0 && std::string(npId.online_id.data) == "anyps5-player", "the NP ID carries the handle");
        std::uint64_t accountId = 0;
        require(sceNpGetAccountIdA(InitialUser, &accountId) == 0 && accountId == AccountId, "the account ID is the launcher's");
        char country[4] = {'x', 'x', 'x', 'x'};
        require(sceNpGetAccountCountryA(InitialUser, country) == 0 && std::string(country) == "tr", "the country is the launcher's");
        bool signedUp = false;
        require(sceNpHasSignedUp(InitialUser, &signedUp) == 0 && signedUp, "the user has signed up");
        int userId = 0;
        require(sceNpGetUserIdByAccountId(AccountId, &userId) == 0 && userId == InitialUser, "the account maps back to the initial user");
        require(sceNpGetUserIdByAccountId(AccountId + 1, &userId) == UserNotFound, "another account is not a local user");
        const auto mine = onlineId("anyps5-player");
        const auto theirs = onlineId("someone-else");
        require(sceNpGetUserIdByOnlineId(&mine, &userId) == 0 && userId == InitialUser, "the handle maps back to the initial user");
        require(sceNpGetUserIdByOnlineId(&theirs, &userId) == UserNotFound, "another handle is not a local user");
        require(sceNpGetAccountId(&mine, &accountId) == 0 && accountId == AccountId, "the handle maps to the account");

        const int request = sceNpCreateRequest();
        int result = -1;
        require(sceNpCheckNpAvailabilityA(request, InitialUser) == 0, "the network is available to the signed-in user");
        require(sceNpPollAsync(request, &result) == 0 && result == 0, "polling the request reports success");
        require(sceNpCheckPlus(request, &result, &result) == SignedOut, "the Plus check keeps its offline answer");
        sceNpDeleteRequest(request);

        launcher.SetAccount(Online::Wire::Account{});
        require(eventually([] { return state() == 1; }), "the launcher signing out signs the game out");
        require(sceNpGetOnlineId(InitialUser, &id) == SignedOut, "identity questions fail again");
        require(sceNpCheckCallback() == 0 && lastState == 1, "the callback reports the sign-out");
        const int before = calls;
        require(sceNpCheckCallback() == 0 && calls == before, "an unchanged state is not reported again");

        launcher.SetAccount(account);
        require(eventually([] { return state() == 2; }), "signing in again is seen");
        launcher.DropClient();
        require(eventually([&] { return launcher.ProvenSessions() >= 2 && state() == 2; }), "a dropped bridge comes back signed in");
        require(sceNpCheckCallback() == 0 && lastState == 2, "the callback reports signed in after the reconnection");
    } catch (const std::exception& error) {
        std::cerr << "online np manager: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online np manager: ok\n";
    return 0;
}
