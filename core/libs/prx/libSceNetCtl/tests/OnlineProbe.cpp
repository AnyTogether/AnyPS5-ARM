// A stand-in for a game: it signs in and asks the web API through the real NpManager and
// NpWebApi2 exports, the way a title does, and prints what it got as name=value lines. The
// launcher's tests start it with the variables of a real launcher service (ANYPS5_ONLINE,
// ANYPS5_ONLINE_SECRET) to prove both ends of the bridge speak the same protocol; without them it
// shows the game's view offline.
//
// `online_probe p2p <peer address> ping|pong` instead plays peer-to-peer: a datagram P2P socket
// on port 3658, virtual port 1, through libSceNet; "ping" sends until the peer's "pong" comes
// back, "pong" answers every "ping". Two of them behind two launchers prove packets cross
// between players.
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <arpa/inet.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

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
int APS5_VABI sceNetInit_nid_postfix(void);
int APS5_VABI sceNetSocket(const char*, int, int, int);
int APS5_VABI sceNetBind_nid_postfix(int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetSendto(int, const void*, std::size_t, int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetRecvfrom(int, void*, std::size_t, int, void*, std::uint32_t*);
int APS5_VABI sceNetSocketClose(int);
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

// The platform's socket address: the virtual port sits where IPv4 has zeros.
struct NetAddress {
    std::uint8_t length = 16;
    std::uint8_t family = 2;
    std::uint16_t port = 0;
    std::uint32_t address = 0;
    std::uint16_t vport = 0;
    std::uint8_t zero[6] = {};
};
static_assert(sizeof(NetAddress) == 16);

std::string dotted(std::uint32_t networkOrder) {
    in_addr address{};
    address.s_addr = networkOrder;
    return inet_ntoa(address);
}

int p2p(const std::string& peerText, const std::string& role) {
    using namespace std::chrono_literals;
    in_addr peerAddress{};
    if (inet_pton(AF_INET, peerText.c_str(), &peerAddress) != 1) {
        std::cerr << "online probe: not an address: " << peerText << '\n';
        return 2;
    }
    sceNetInit_nid_postfix();
    const int socket = sceNetSocket("probe", 2, 6, 0);
    if (socket < 0) {
        std::cout << "socket_error=" << hexResult(socket) << '\n';
        return 1;
    }
    NetAddress bound;
    bound.port = htons(3658);
    bound.vport = htons(1);
    if (const int result = sceNetBind_nid_postfix(socket, &bound, sizeof(bound)); result != 0) {
        std::cout << "bind_error=" << hexResult(result) << '\n';
        return 1;
    }
    NetAddress peer = bound;
    peer.address = peerAddress.s_addr;
    const bool pinging = role == "ping";
    const auto until = std::chrono::steady_clock::now() + 20s;
    auto lastSend = std::chrono::steady_clock::time_point{};
    auto answeredAt = std::chrono::steady_clock::time_point{};
    bool done = false;
    while (std::chrono::steady_clock::now() < until && !done) {
        const auto now = std::chrono::steady_clock::now();
        if (pinging && now - lastSend > 100ms) {
            sceNetSendto(socket, "ping", 4, 0, &peer, sizeof(peer));
            lastSend = now;
        }
        char buffer[64];
        NetAddress from;
        std::uint32_t fromLength = sizeof(from);
        const auto got = sceNetRecvfrom(socket, buffer, sizeof(buffer), 0x80, &from, &fromLength);
        if (got < 0) {
            if (!pinging && answeredAt != std::chrono::steady_clock::time_point{} && now - answeredAt > 2s) done = true;
            std::this_thread::sleep_for(10ms);
            continue;
        }
        const std::string text(buffer, static_cast<std::size_t>(got));
        const std::string source = dotted(from.address) + ":" + std::to_string(ntohs(from.port)) + "/" + std::to_string(ntohs(from.vport));
        if (pinging && text == "pong") {
            std::cout << "got=pong\nfrom=" << source << '\n';
            done = true;
        } else if (!pinging && text == "ping") {
            if (answeredAt == std::chrono::steady_clock::time_point{}) std::cout << "got=ping\nfrom=" << source << '\n' << std::flush;
            sceNetSendto(socket, "pong", 4, 0, &from, fromLength);
            answeredAt = now;
        }
    }
    sceNetSocketClose(socket);
    if (!done) std::cout << "timed_out=1\n";
    return done ? 0 : 1;
}

}

int main(int argc, char** argv) {
    if (argc == 4 && std::string(argv[1]) == "p2p") return p2p(argv[2], argv[3]);
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
