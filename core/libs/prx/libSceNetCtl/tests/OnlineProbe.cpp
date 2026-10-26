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
//
// `online_probe udp <address> ping|pong [bytes]` does the same over plain UDP sockets with
// SO_BROADCAST, "pong" on port 3659 and "ping" on 3660, so <address> may be 255.255.255.255 or the virtual network's broadcast:
// "ping" sends <bytes>-byte pings (default 4) and first tries one datagram too big for UDP;
// "pong" answers each ping to its sender with "pong" and the size it got.
//
// `online_probe stream <peer address> ping|pong [bytes]` plays over a stream P2P socket: "pong"
// listens on port 3658, virtual port 1, accepts one stream, reads <bytes> bytes (default 100000)
// and writes them back; "ping" connects to the peer (trying again while it is refused, as the
// listener may not be up yet), writes <bytes> patterned bytes and checks that the same come back.
//
// `online_probe host` plays Host the way Human Fall Flat (PPSA02429) does: it asks the block list
// and the restriction status first thing, makes a sessionManager push context, creates a Player
// Session with it, waits up to 10 s for the launcher's news of another player joining (pushed to
// the context, delivered through sceNpCheckCallback), then leaves the session and a stale one.
// Creating the session and inviting to it go the way the game's own libSceNpCppWebApi.prx sends
// them (cppWebApi below), so a reply it would not take shows here as <name>_response=none.
//
// `online_probe join <session ID>` plays Join the same way: a push context, then joining the
// Player Session of a room found elsewhere (Photon's list), which the launcher has never seen.
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <algorithm>
#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#endif
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
int APS5_VABI sceNpWebApi2GetHttpResponseHeaderValueLength(std::int64_t requestId, const char* name, std::size_t* length);
int APS5_VABI sceNpWebApi2GetHttpResponseHeaderValue(std::int64_t requestId, const char* name, char* value, std::size_t size);
int APS5_VABI sceNpWebApi2DeleteRequest(std::int64_t requestId);
int APS5_VABI sceNpWebApi2PushEventCreateHandle(int libCtxId);
int APS5_VABI sceNpWebApi2PushEventCreateFilter(int libCtxId, int handleId, const char* service, std::uint32_t label, const void* params, std::size_t count);
int APS5_VABI sceNpWebApi2PushEventRegisterPushContextCallback(int userContextId, int filterId, void* callback, void* userArg);
int APS5_VABI sceNpWebApi2PushEventCreatePushContext(int userContextId, char* pushContextId);
int APS5_VABI sceNpWebApi2PushEventStartPushContextCallback(int userContextId, const char* pushContextId);
int APS5_VABI sceNpWebApi2PushEventDeletePushContext(int userContextId, const char* pushContextId);
int APS5_VABI sceNpCheckCallback(void);
int APS5_VABI sceNetInit_nid_postfix(void);
int APS5_VABI sceNetSocket(const char*, int, int, int);
int APS5_VABI sceNetBind_nid_postfix(int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetSendto(int, const void*, std::size_t, int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetRecvfrom(int, void*, std::size_t, int, void*, std::uint32_t*);
int APS5_VABI sceNetSocketClose(int);
int APS5_VABI sceNetSetsockopt(int, int, int, const void*, std::uint32_t);
int APS5_VABI sceNetListen(int, int);
int APS5_VABI sceNetAccept(int, void*, std::uint32_t*);
int APS5_VABI sceNetConnect(int, const void*, std::uint32_t);
int APS5_VABI sceNetGetpeername(int, void*, std::uint32_t*);
std::int64_t APS5_VABI sceNetSend(int, const void*, std::size_t, int);
std::int64_t APS5_VABI sceNetRecv(int, void*, std::size_t, int);
}

namespace {

constexpr int InitialUser = 0x10000000;

std::string hexResult(int result) {
    char text[16];
    std::snprintf(text, sizeof(text), "0x%08x", static_cast<unsigned>(result));
    return text;
}

// One web request as a title makes it; prints <name>_status and <name>_body (or <name>_error)
// and returns the body.
std::string request(int user, const char* name, const char* group, const std::string& path, const char* method = "GET", const std::string& sent = {}) {
    std::int64_t request = 0;
    if (const int created = sceNpWebApi2CreateRequest(user, group, path.c_str(), method, nullptr, &request); created != 0) {
        std::cout << name << "_error=" << hexResult(created) << '\n';
        return {};
    }
    sceNpWebApi2AddHttpRequestHeader(request, "X-Psn-NpCppWebApi-Context", "probe");
    if (!sent.empty()) sceNpWebApi2AddHttpRequestHeader(request, "Content-Type", "application/json; charset=utf-8");
    NpWebApi2ResponseInformationOption info{};
    const int result = sceNpWebApi2SendRequest(request, sent.empty() ? nullptr : sent.data(), sent.size(), &info);
    std::string body;
    if (result != 0) {
        std::cout << name << "_error=" << hexResult(result) << '\n';
    } else {
        char chunk[256];
        for (int got; (got = sceNpWebApi2ReadData(request, chunk, sizeof(chunk))) > 0;) body.append(chunk, static_cast<std::size_t>(got));
        std::cout << name << "_status=" << info.http_status << '\n' << name << "_body=" << body << '\n';
    }
    sceNpWebApi2DeleteRequest(request);
    return body;
}

// One request the way the game's bundled libSceNpCppWebApi.prx makes it for an API whose reply
// has a body (PlayerSessionsApi::createPlayerSessions and the like): the response information
// option set, then the body read in 255-byte pieces and parsed ONLY when the status is the one
// the API answers with (201 for every POST that makes something). Any other 2xx status leaves the
// transaction finished with no response body, and the game then reads a member of a null body
// (SIGSEGV at address 0x10 in PostPlayerSessionsResponseBody::getPlayerSessions). Prints
// <name>_status, the Content-Type and Content-Length headers, and <name>_response=parsed or none.
std::string cppWebApi(int user, const char* name, const char* group, const std::string& path, const char* method, const std::string& sent, int expected,
    const char* headerName = nullptr, const std::string& headerValue = {}) {
    std::int64_t request = 0;
    if (const int created = sceNpWebApi2CreateRequest(user, group, path.c_str(), method, nullptr, &request); created != 0) {
        std::cout << name << "_error=" << hexResult(created) << '\n';
        return {};
    }
    sceNpWebApi2AddHttpRequestHeader(request, "X-Psn-NpCppWebApi-Context", "PS5/2.00");
    if (headerName) sceNpWebApi2AddHttpRequestHeader(request, headerName, headerValue.c_str());
    NpWebApi2ResponseInformationOption info{};
    const int result = sceNpWebApi2SendRequest(request, sent.data(), sent.size(), &info);
    std::string body;
    if (result != 0) {
        std::cout << name << "_error=" << hexResult(result) << '\n';
    } else {
        std::cout << name << "_status=" << info.http_status << '\n' << name << "_size=" << info.response_data_size << '\n';
        static const char* const headers[][2] = {{"Content-Type", "_content_type="}, {"Content-Length", "_content_length="}};
        for (const auto& [header, key] : headers) {
            std::size_t length = 0;
            std::string value;
            if (sceNpWebApi2GetHttpResponseHeaderValueLength(request, header, &length) == 0) {
                value.assign(length + 1, '\0');
                if (sceNpWebApi2GetHttpResponseHeaderValue(request, header, value.data(), value.size()) != 0) value = "?";
                value.resize(std::strlen(value.c_str()));
            }
            std::cout << name << key << value << '\n';
        }
        if (info.http_status == expected) {
            char chunk[255];
            for (int got; (got = sceNpWebApi2ReadData(request, chunk, sizeof(chunk))) > 0;) body.append(chunk, static_cast<std::size_t>(got));
        }
        std::cout << name << "_response=" << (body.empty() || body.front() != '{' ? "none" : "parsed") << '\n' << name << "_body=" << body << '\n';
    }
    sceNpWebApi2DeleteRequest(request);
    return body;
}

void ask(int user, const char* name, const char* group, const char* path) {
    request(user, name, group, path);
}

struct PushFilterParameter {
    char dataType[65];
    const void* keys;
    std::size_t keyCount;
};

std::string pushedType;
std::string pushedData;
std::string pushedContext;

void APS5_VABI onPush(int, int, const char* pushContextId, int, const char*, std::uint32_t, const void*, const void*, const void*, const void*,
    const char* dataType, const char* data, std::size_t length, const void*, std::size_t, void*) {
    if (!pushedType.empty()) return;
    pushedContext = pushContextId ? pushContextId : "";
    pushedType = dataType ? dataType : "";
    pushedData.assign(data, length);
}

int host() {
    using namespace std::chrono_literals;
    std::uint64_t accountId = 0;
    if (const int result = sceNpGetAccountIdA(InitialUser, &accountId); result != 0) {
        std::cout << "account_id_error=" << hexResult(result) << '\n';
        return 1;
    }
    const auto account = std::to_string(accountId);
    const int library = sceNpWebApi2Initialize(1, 0x80000);
    const int user = library > 0 ? sceNpWebApi2CreateUserContext(library, InitialUser) : library;
    // The first thing the game asks, as soon as it starts.
    request(user, "restriction", "communicationRestrictionStatus", "/v3/users/" + account + "/communication/restriction/status");
    request(user, "blocks", "userProfile", "/v1/users/me/blocks?offset=0&limit=0");

    const int handle = sceNpWebApi2PushEventCreateHandle(library);
    static const char* const types[] = {"psn:sessionManager:playerSession:created", "psn:sessionManager:playerSession:deleted",
        "psn:sessionManager:ps:m:players:created", "psn:sessionManager:ps:m:players:deleted", "psn:sessionManager:ps:leader:updated"};
    PushFilterParameter parameters[5] = {};
    for (std::size_t index = 0; index < 5; ++index) std::strncpy(parameters[index].dataType, types[index], sizeof(parameters[index].dataType) - 1);
    const int filter = sceNpWebApi2PushEventCreateFilter(library, handle, "sessionManager", 0, parameters, 5);
    sceNpWebApi2PushEventRegisterPushContextCallback(user, filter, reinterpret_cast<void*>(onPush), nullptr);
    char context[37] = {};
    const int made = sceNpWebApi2PushEventCreatePushContext(user, context);
    std::cout << "push_context_result=" << hexResult(made) << "\npush_context=" << context << '\n';
    if (made != 0) return 1;
    sceNpWebApi2PushEventStartPushContextCallback(user, context);

    const std::string created = cppWebApi(user, "create", "sessionManager", "/v1/playerSessions", "POST",
        std::string(R"({"playerSessions":[{"maxPlayers":8,"maxSpectators":0,"joinDisabled":false,"supportedPlatforms":["PS5"],)") +
            R"("localizedSessionName":{"defaultLanguage":"en-US","localizedText":{"en-US":"Human Fall Flat"}},"joinableUserType":"ANYONE",)" +
            R"("invitableUserType":"MEMBER","leaderPrivileges":["KICK","UPDATE_JOINABLE_USER_TYPE"],"swapSupported":false,"customData1":"cm9vbQ==",)" +
            R"("member":{"players":[{"accountId":"me","platform":"me","pushContexts":[{"pushContextId":")" + context + R"("}]}]}}]})", 201);
    const auto at = created.find("\"sessionId\":\"");
    if (at == std::string::npos) return 1;
    const auto start = at + 13;
    const std::string sessionId = created.substr(start, created.find('"', start) - start);
    std::cout << "session_id=" << sessionId << '\n';
    request(user, "get", "sessionManager", "/v1/playerSessions/" + sessionId);
    request(user, "patch", "sessionManager", "/v1/playerSessions/" + sessionId, "PATCH", R"({"joinableUserType":"FRIENDS"})");
    cppWebApi(user, "invite", "sessionManager", "/v1/playerSessions/" + sessionId + "/invitations", "POST", R"({"invitations":[{"to":{"accountId":"123"}}]})", 201);
    std::cout << "waiting=1" << std::endl;
    for (auto until = std::chrono::steady_clock::now() + 10s; pushedType.empty() && std::chrono::steady_clock::now() < until;) {
        sceNpCheckCallback();
        std::this_thread::sleep_for(10ms);
    }
    std::cout << "pushed_type=" << pushedType << "\npushed_context=" << pushedContext << "\npushed_data=" << pushedData << '\n';
    request(user, "leave", "sessionManager", "/v1/playerSessions/" + sessionId + "/members/" + account, "DELETE");
    request(user, "stale_leave", "sessionManager", "/v1/playerSessions/cb8a5af3-067c-4fbc-87c3-f96b20fb4f33/members/" + account, "DELETE");
    request(user, "after", "sessionManager", "/v1/playerSessions/" + sessionId);
    sceNpWebApi2PushEventDeletePushContext(user, context);
    return 0;
}

int join(const std::string& sessionId) {
    std::uint64_t accountId = 0;
    if (const int result = sceNpGetAccountIdA(InitialUser, &accountId); result != 0) {
        std::cout << "account_id_error=" << hexResult(result) << '\n';
        return 1;
    }
    const int library = sceNpWebApi2Initialize(1, 0x80000);
    const int user = library > 0 ? sceNpWebApi2CreateUserContext(library, InitialUser) : library;
    const int handle = sceNpWebApi2PushEventCreateHandle(library);
    PushFilterParameter parameters[1] = {};
    std::strncpy(parameters[0].dataType, "psn:sessionManager:ps:m:players:created", sizeof(parameters[0].dataType) - 1);
    const int filter = sceNpWebApi2PushEventCreateFilter(library, handle, "sessionManager", 0, parameters, 1);
    sceNpWebApi2PushEventRegisterPushContextCallback(user, filter, reinterpret_cast<void*>(onPush), nullptr);
    char context[37] = {};
    if (sceNpWebApi2PushEventCreatePushContext(user, context) != 0) return 1;
    sceNpWebApi2PushEventStartPushContextCallback(user, context);
    cppWebApi(user, "join", "sessionManager", "/v1/playerSessions/" + sessionId + "/member/players", "POST",
        R"({"players":[{"accountId":")" + std::to_string(accountId) + R"(","platform":"PS5","pushContexts":[{"pushContextId":")" + context + R"("}]}]})", 201);
    // Then, as Human Fall Flat does, getPlayerSessions with the session named in a header.
    cppWebApi(user, "joined", "sessionManager", "/v1/playerSessions?fields=sessionId,member,leader,customData1", "GET", {}, 200,
        "X-PSN-SESSION-MANAGER-SESSION-IDS", sessionId);
    request(user, "leave", "sessionManager", "/v1/playerSessions/" + sessionId + "/members/" + std::to_string(accountId), "DELETE");
    sceNpWebApi2PushEventDeletePushContext(user, context);
    return 0;
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

std::string pattern(std::size_t bytes) {
    std::string out(bytes, '\0');
    for (std::size_t index = 0; index < bytes; ++index) out[index] = static_cast<char>(index * 31 + index / 977);
    return out;
}

bool readAll(int socket, std::string& out, std::size_t bytes) {
    char buffer[8192];
    while (out.size() < bytes) {
        const auto got = sceNetRecv(socket, buffer, std::min(sizeof(buffer), bytes - out.size()), 0);
        if (got <= 0) return false;
        out.append(buffer, static_cast<std::size_t>(got));
    }
    return true;
}

bool writeAll(int socket, const std::string& data) {
    std::size_t done = 0;
    while (done < data.size()) {
        const auto sent = sceNetSend(socket, data.data() + done, data.size() - done, 0);
        if (sent <= 0) return false;
        done += static_cast<std::size_t>(sent);
    }
    return true;
}

int stream(const std::string& peerText, const std::string& role, std::size_t bytes) {
    using namespace std::chrono_literals;
    in_addr peerAddress{};
    if (inet_pton(AF_INET, peerText.c_str(), &peerAddress) != 1) {
        std::cerr << "online probe: not an address: " << peerText << '\n';
        return 2;
    }
    sceNetInit_nid_postfix();
    if (role == "pong") {
        const int listener = sceNetSocket("probe-listen", 2, 10, 0);
        if (listener < 0) {
            std::cout << "socket_error=" << hexResult(listener) << '\n';
            return 1;
        }
        NetAddress bound;
        bound.port = htons(3658);
        bound.vport = htons(1);
        if (const int result = sceNetBind_nid_postfix(listener, &bound, sizeof(bound)); result != 0) {
            std::cout << "bind_error=" << hexResult(result) << '\n';
            return 1;
        }
        if (const int result = sceNetListen(listener, 4); result != 0) {
            std::cout << "listen_error=" << hexResult(result) << '\n';
            return 1;
        }
        std::cout << "listening=1\n" << std::flush;
        NetAddress from;
        std::uint32_t fromLength = sizeof(from);
        const int accepted = sceNetAccept(listener, &from, &fromLength);
        if (accepted < 0) {
            std::cout << "accept_error=" << hexResult(accepted) << '\n';
            return 1;
        }
        std::cout << "from=" << dotted(from.address) << ":" << ntohs(from.port) << "/" << ntohs(from.vport) << '\n';
        std::string got;
        const bool read = readAll(accepted, got, bytes);
        std::cout << "got=" << got.size() << "\nsame=" << (read && got == pattern(bytes) ? 1 : 0) << '\n';
        writeAll(accepted, got);
        // The pinger closes once it has everything back.
        char end[16];
        std::cout << "end=" << sceNetRecv(accepted, end, sizeof(end), 0) << '\n';
        sceNetSocketClose(accepted);
        sceNetSocketClose(listener);
        return read ? 0 : 1;
    }
    NetAddress peer;
    peer.address = peerAddress.s_addr;
    peer.port = htons(3658);
    peer.vport = htons(1);
    const auto until = std::chrono::steady_clock::now() + 20s;
    int socket = -1;
    int result = -1;
    while (std::chrono::steady_clock::now() < until) {
        socket = sceNetSocket("probe-stream", 2, 10, 0);
        result = sceNetConnect(socket, &peer, sizeof(peer));
        if (result == 0) break;
        sceNetSocketClose(socket);
        socket = -1;
        std::this_thread::sleep_for(100ms);
    }
    if (socket < 0) {
        std::cout << "connect_error=" << hexResult(result) << '\n';
        return 1;
    }
    NetAddress name;
    std::uint32_t nameLength = sizeof(name);
    sceNetGetpeername(socket, &name, &nameLength);
    std::cout << "peer=" << dotted(name.address) << ":" << ntohs(name.port) << "/" << ntohs(name.vport) << '\n';
    const auto sent = pattern(bytes);
    if (!writeAll(socket, sent)) std::cout << "write_failed=1\n";
    std::string back;
    const bool read = readAll(socket, back, bytes);
    std::cout << "echoed=" << back.size() << "\nsame=" << (read && back == sent ? 1 : 0) << '\n';
    sceNetSocketClose(socket);
    // A game keeps running after it closes a stream; the close reaches the peer before this
    // stand-in exits (an exit with the bridge's queue unsent would break the stream instead).
    std::this_thread::sleep_for(300ms);
    return read && back == sent ? 0 : 1;
}

int udp(const std::string& destinationText, const std::string& role, std::size_t bytes) {
    using namespace std::chrono_literals;
    in_addr destinationAddress{};
    if (inet_pton(AF_INET, destinationText.c_str(), &destinationAddress) != 1) {
        std::cerr << "online probe: not an address: " << destinationText << '\n';
        return 2;
    }
    sceNetInit_nid_postfix();
    const int socket = sceNetSocket("probe-udp", 2, 2, 0);
    if (socket < 0) {
        std::cout << "socket_error=" << hexResult(socket) << '\n';
        return 1;
    }
    const int enabled = 1;
    sceNetSetsockopt(socket, 0xffff, 0x20, &enabled, sizeof(enabled));
    const bool pinging = role == "ping";
    // The pinger has its own port, so both probes can run on one Mac.
    NetAddress bound;
    bound.port = htons(pinging ? 3660 : 3659);
    if (const int result = sceNetBind_nid_postfix(socket, &bound, sizeof(bound)); result != 0) {
        std::cout << "bind_error=" << hexResult(result) << '\n';
        return 1;
    }
    NetAddress destination;
    destination.port = htons(3659);
    destination.address = destinationAddress.s_addr;
    std::string ping(std::max<std::size_t>(bytes, 4), 'x');
    ping.replace(0, 4, "ping");
    if (pinging) {
        const std::string tooBig(70000, 'x');
        const auto refused = sceNetSendto(socket, tooBig.data(), tooBig.size(), 0, &destination, sizeof(destination));
        std::cout << "oversize=" << (refused < 0 ? hexResult(static_cast<int>(refused)) : std::to_string(refused)) << '\n';
    }
    std::string buffer(70000, '\0');
    const auto until = std::chrono::steady_clock::now() + 20s;
    auto lastSend = std::chrono::steady_clock::time_point{};
    auto answeredAt = std::chrono::steady_clock::time_point{};
    bool done = false;
    while (std::chrono::steady_clock::now() < until && !done) {
        const auto now = std::chrono::steady_clock::now();
        if (pinging && now - lastSend > 100ms) {
            sceNetSendto(socket, ping.data(), ping.size(), 0, &destination, sizeof(destination));
            lastSend = now;
        }
        NetAddress from;
        std::uint32_t fromLength = sizeof(from);
        const auto got = sceNetRecvfrom(socket, buffer.data(), buffer.size(), 0x80, &from, &fromLength);
        if (got < 0) {
            if (!pinging && answeredAt != std::chrono::steady_clock::time_point{} && now - answeredAt > 2s) done = true;
            std::this_thread::sleep_for(10ms);
            continue;
        }
        const std::string text(buffer.data(), static_cast<std::size_t>(got));
        const std::string source = dotted(from.address) + ":" + std::to_string(ntohs(from.port));
        if (pinging && text.rfind("pong ", 0) == 0) {
            std::cout << "got=pong\nfrom=" << source << "\nsize=" << text.substr(5) << '\n';
            done = true;
        } else if (!pinging && text.rfind("ping", 0) == 0) {
            if (answeredAt == std::chrono::steady_clock::time_point{}) std::cout << "got=ping\nfrom=" << source << "\nsize=" << got << '\n' << std::flush;
            const std::string pong = "pong " + std::to_string(got);
            sceNetSendto(socket, pong.data(), pong.size(), 0, &from, fromLength);
            answeredAt = now;
        }
    }
    sceNetSocketClose(socket);
    if (!done) std::cout << "timed_out=1\n";
    return done ? 0 : 1;
}

}

int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "host") return host();
    if (argc == 3 && std::string(argv[1]) == "join") return join(argv[2]);
    if (argc == 4 && std::string(argv[1]) == "p2p") return p2p(argv[2], argv[3]);
    if ((argc == 4 || argc == 5) && std::string(argv[1]) == "stream") return stream(argv[2], argv[3], argc == 5 ? std::stoul(argv[4]) : 100000);
    if ((argc == 4 || argc == 5) && std::string(argv[1]) == "udp") return udp(argv[2], argv[3], argc == 5 ? std::stoul(argv[4]) : 4);
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
        ask(user, "tickets", "matchmaking", "/v1/tickets");
    } catch (const std::exception& error) {
        std::cerr << "online probe: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
