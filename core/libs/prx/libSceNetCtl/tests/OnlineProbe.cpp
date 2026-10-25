// A stand-in for a game: it signs in and asks the web API through the real NpManager and
// NpWebApi2 exports, the way a title does, and prints what it got as name=value lines. The
// launcher's tests start it with the variables of a real launcher service (ANYPS5_ONLINE,
// ANYPS5_ONLINE_SECRET) to prove both ends of the bridge speak the same protocol; without them it
// shows the game's view offline.
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>

extern "C" {
int APS5_VABI sceNpGetState(int userId, std::uint32_t* state);
int APS5_VABI sceNpGetOnlineId(int userId, NpOnlineId* onlineId);
int APS5_VABI sceNpGetAccountIdA(int userId, std::uint64_t* accountId);
int APS5_VABI sceNpGetAccountCountryA(int userId, void* countryCode);
int APS5_VABI sceNpWebApi2Initialize(int libHttpCtxId, std::size_t poolSize);
int APS5_VABI sceNpWebApi2CreateUserContext(int libCtxId, int userId);
int APS5_VABI sceNpWebApi2CreateRequest(int userContextId, const char* apiGroup, const char* path, const char* method, const void* contentParameter, std::int64_t* requestId);
int APS5_VABI sceNpWebApi2AddHttpRequestHeader(std::int64_t requestId, const char* name, const char* value);
int APS5_VABI sceNpWebApi2SendRequest(std::int64_t requestId, const void* data, std::size_t size, NpWebApi2ResponseInformationOption* option);
int APS5_VABI sceNpWebApi2ReadData(std::int64_t requestId, void* data, std::size_t size);
int APS5_VABI sceNpWebApi2DeleteRequest(std::int64_t requestId);
}

namespace {

constexpr int InitialUser = 0x10000000;

std::string hexResult(int result) {
    char text[16];
    std::snprintf(text, sizeof(text), "0x%08x", static_cast<unsigned>(result));
    return text;
}

// One web request as a title makes it; prints <name>_status and <name>_body (or <name>_error).
void ask(int user, const char* name, const char* group, const char* path) {
    std::int64_t request = 0;
    if (const int created = sceNpWebApi2CreateRequest(user, group, path, "GET", nullptr, &request); created != 0) {
        std::cout << name << "_error=" << hexResult(created) << '\n';
        return;
    }
    sceNpWebApi2AddHttpRequestHeader(request, "X-Psn-NpCppWebApi-Context", "probe");
    NpWebApi2ResponseInformationOption info{};
    const int sent = sceNpWebApi2SendRequest(request, nullptr, 0, &info);
    if (sent != 0) {
        std::cout << name << "_error=" << hexResult(sent) << '\n';
    } else {
        std::string body;
        char chunk[256];
        for (int got; (got = sceNpWebApi2ReadData(request, chunk, sizeof(chunk))) > 0;) body.append(chunk, static_cast<std::size_t>(got));
        std::cout << name << "_status=" << info.http_status << '\n' << name << "_body=" << body << '\n';
    }
    sceNpWebApi2DeleteRequest(request);
}

}

int main() {
    try {
        std::uint32_t state = 0;
        const int stateResult = sceNpGetState(InitialUser, &state);
        std::cout << "state=" << (stateResult == 0 ? std::to_string(state) : hexResult(stateResult)) << '\n';
        NpOnlineId onlineId{};
        if (const int result = sceNpGetOnlineId(InitialUser, &onlineId); result == 0) {
            std::cout << "online_id=" << std::string(onlineId.data, strnlen(onlineId.data, sizeof(onlineId.data))) << '\n';
        } else {
            std::cout << "online_id_error=" << hexResult(result) << '\n';
        }
        std::uint64_t accountId = 0;
        if (const int result = sceNpGetAccountIdA(InitialUser, &accountId); result == 0) {
            std::cout << "account_id=" << accountId << '\n';
        } else {
            std::cout << "account_id_error=" << hexResult(result) << '\n';
        }
        char country[4] = {};
        if (sceNpGetAccountCountryA(InitialUser, country) == 0) std::cout << "country=" << std::string(country, strnlen(country, 2)) << '\n';

        const int library = sceNpWebApi2Initialize(1, 0x80000);
        const int user = library > 0 ? sceNpWebApi2CreateUserContext(library, InitialUser) : library;
        if (user <= 0) {
            std::cout << "web_error=" << hexResult(user) << '\n';
            return 0;
        }
        ask(user, "friends", "userProfile", "/v1/users/local_268435456/friends?");
        if (accountId != 0) ask(user, "profile", "userProfile", "/v1/users/me/profiles");
        ask(user, "sessions", "sessionManager", "/v1/playerSessions");
    } catch (const std::exception& error) {
        std::cerr << "online probe: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
