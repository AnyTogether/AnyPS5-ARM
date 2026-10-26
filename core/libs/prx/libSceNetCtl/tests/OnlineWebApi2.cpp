#include "FakeLauncher.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <chrono>
#include <thread>

extern "C" {
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
int APS5_VABI sceNpWebApi2PushEventRegisterCallback(int userContextId, int filterId, void* callback, void* userArg);
int APS5_VABI sceNpWebApi2PushEventRegisterPushContextCallback(int userContextId, int filterId, void* callback, void* userArg);
int APS5_VABI sceNpWebApi2PushEventCreatePushContext(int userContextId, char* pushContextId);
int APS5_VABI sceNpWebApi2PushEventStartPushContextCallback(int userContextId, const char* pushContextId);
int APS5_VABI sceNpWebApi2PushEventDeletePushContext(int userContextId, const char* pushContextId);
int APS5_VABI sceNpWebApi2PushEventUnregisterCallback(int userContextId, int callbackId);
int APS5_VABI sceNpCheckCallback(void);
}

namespace {

constexpr int InitialUser = 0x10000000;
constexpr int Unavailable = static_cast<int>(0x80553406);

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

// The platform's push event structures as a game sees them.
struct FilterParameter {
    char dataType[65];
    const void* keys;
    std::size_t keyCount;
};
static_assert(sizeof(FilterParameter) == 88);

struct PeerAddress {
    std::uint64_t accountId;
    std::int32_t platform;
    std::int32_t reserved;
};

struct OnlineId {
    char data[16];
    char term;
    char dummy[3];
};

struct ExtendedData {
    char key[33];
    const char* data;
    std::size_t length;
};

struct Delivered {
    int userContextId = 0;
    int callbackId = 0;
    std::string pushContextId;
    int type = -1;
    std::string service;
    std::uint64_t to = 0;
    std::string toOnlineId;
    std::uint64_t from = 0;
    std::string fromOnlineId;
    std::string dataType;
    std::string data;
    std::vector<std::pair<std::string, std::string>> extended;
    void* userArg = nullptr;
};

std::vector<Delivered> contextDeliveries;
std::vector<Delivered> plainDeliveries;

void fill(Delivered& out, const PeerAddress* to, const OnlineId* toOnlineId, const PeerAddress* from, const OnlineId* fromOnlineId, const char* dataType,
    const char* data, std::size_t length, const ExtendedData* extended, std::size_t extendedCount) {
    out.to = to ? to->accountId : 0;
    out.toOnlineId = toOnlineId ? toOnlineId->data : "";
    out.from = from ? from->accountId : 0;
    out.fromOnlineId = fromOnlineId ? fromOnlineId->data : "";
    out.dataType = dataType ? dataType : "";
    out.data.assign(data, length);
    for (std::size_t index = 0; index < extendedCount; ++index) out.extended.emplace_back(extended[index].key, std::string(extended[index].data, extended[index].length));
}

void APS5_VABI onPushContextEvent(int userContextId, int callbackId, const char* pushContextId, int type, const char* service, std::uint32_t, const PeerAddress* to,
    const OnlineId* toOnlineId, const PeerAddress* from, const OnlineId* fromOnlineId, const char* dataType, const char* data, std::size_t length,
    const ExtendedData* extended, std::size_t extendedCount, void* userArg) {
    Delivered got;
    got.userContextId = userContextId;
    got.callbackId = callbackId;
    got.pushContextId = pushContextId ? pushContextId : "";
    got.type = type;
    got.service = service ? service : "";
    got.userArg = userArg;
    fill(got, to, toOnlineId, from, fromOnlineId, dataType, data, length, extended, extendedCount);
    contextDeliveries.push_back(got);
}

void APS5_VABI onPushEvent(int userContextId, int callbackId, const char* service, std::uint32_t, const PeerAddress* to, const OnlineId* toOnlineId,
    const PeerAddress* from, const OnlineId* fromOnlineId, const char* dataType, const char* data, std::size_t length, const ExtendedData* extended,
    std::size_t extendedCount, void* userArg) {
    Delivered got;
    got.userContextId = userContextId;
    got.callbackId = callbackId;
    got.service = service ? service : "";
    got.userArg = userArg;
    fill(got, to, toOnlineId, from, fromOnlineId, dataType, data, length, extended, extendedCount);
    plainDeliveries.push_back(got);
}

FilterParameter parameter(const char* dataType) {
    FilterParameter value{};
    std::strncpy(value.dataType, dataType, sizeof(value.dataType) - 1);
    return value;
}

// Runs the game's callback check until `done` or `limit` passes.
template <typename TDone>
bool pump(TDone done, std::chrono::milliseconds limit = std::chrono::milliseconds(3000)) {
    const auto until = std::chrono::steady_clock::now() + limit;
    while (std::chrono::steady_clock::now() < until) {
        sceNpCheckCallback();
        if (done()) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    return false;
}

}

int main() {
    try {
        Online::Wire::Secret secret{};
        for (std::size_t index = 0; index < secret.size(); ++index) secret[index] = static_cast<std::uint8_t>(0x30 + index);
        Online::Testing::FakeLauncher launcher(secret);
        Online::Wire::Account account;
        account.signedIn = true;
        account.accountId = 42;
        account.onlineId = "player";
        launcher.SetAccount(account);
        std::mutex seenMutex;
        std::vector<Online::Wire::WebRequest> seen;
        const std::string replyBody = "{\"sessionId\":\"0123-abcd\",\"members\":[]}";
        launcher.SetWebHandler([&](const Online::Wire::WebRequest& request) -> std::optional<Online::Wire::WebReply> {
            {
                std::lock_guard lock(seenMutex);
                seen.push_back(request);
            }
            if (request.apiGroup != "sessionManager") return Online::Wire::WebReply{0, {}, {}};
            return Online::Wire::WebReply{201, {{"Content-Type", "application/json"}, {"X-Request-Id", "r-7"}},
                std::vector<std::uint8_t>(replyBody.begin(), replyBody.end())};
        });
        std::string hex;
        static constexpr char digits[] = "0123456789abcdef";
        for (const auto byte : secret) {
            hex += digits[byte >> 4];
            hex += digits[byte & 15];
        }
        const std::string endpoint = "127.0.0.1:" + std::to_string(launcher.Port());
        Online::Testing::SetEnvironment("ANYPS5_ONLINE", endpoint);
        Online::Testing::SetEnvironment("ANYPS5_ONLINE_SECRET", hex);

        const int library = sceNpWebApi2Initialize(1, 0x10000);
        require(library > 0, "the library initializes");
        const int user = sceNpWebApi2CreateUserContext(library, InitialUser);
        require(user > 0, "a user context is made");
        std::int64_t request = 0;
        require(sceNpWebApi2CreateRequest(user, "sessionManager", "/v1/playerSessions?fields=sessionId", "POST", nullptr, &request) == 0, "a request is made");
        require(sceNpWebApi2AddHttpRequestHeader(request, "Content-Type", "application/json") == 0, "a header is added");
        const std::string body = "{\"playerSessions\":[{\"maxPlayers\":4}]}";
        NpWebApi2ResponseInformationOption info{};
        require(sceNpWebApi2SendRequest(request, body.data(), body.size(), &info) == 0, "the launcher's answer makes the send succeed");
        require(info.http_status == 201 && info.response_data_size == replyBody.size(), "status and size reach the game");
        {
            std::lock_guard lock(seenMutex);
            require(seen.size() == 1, "one request reached the launcher");
            const auto& got = seen[0];
            require(got.userId == InitialUser && got.apiGroup == "sessionManager" && got.path == "/v1/playerSessions?fields=sessionId" && got.method == "POST",
                "the request keeps user, group, path and method");
            require(got.headers.size() == 1 && got.headers[0].first == "Content-Type" && got.headers[0].second == "application/json", "headers are passed");
            require(std::string(got.body.begin(), got.body.end()) == body, "the body is passed untouched");
        }
        std::size_t length = 0;
        require(sceNpWebApi2GetHttpResponseHeaderValueLength(request, "x-request-id", &length) == 0 && length == 3, "header lookup ignores case");
        char value[8] = {};
        require(sceNpWebApi2GetHttpResponseHeaderValue(request, "X-REQUEST-ID", value, sizeof(value)) == 0 && std::string(value) == "r-7", "header value is copied");
        char tiny[3] = {};
        require(sceNpWebApi2GetHttpResponseHeaderValue(request, "X-Request-Id", tiny, sizeof(tiny)) != 0, "a buffer without room for the terminator is refused");
        require(sceNpWebApi2GetHttpResponseHeaderValueLength(request, "Missing", &length) == Unavailable, "a missing header is not found");
        std::string read;
        char chunk[10];
        while (true) {
            const int got = sceNpWebApi2ReadData(request, chunk, sizeof(chunk));
            require(got >= 0, "reading succeeds");
            if (got == 0) break;
            read.append(chunk, static_cast<std::size_t>(got));
        }
        require(read == replyBody, "the body is read back in pieces");
        require(sceNpWebApi2DeleteRequest(request) == 0 && sceNpWebApi2ReadData(request, chunk, sizeof(chunk)) == Unavailable, "a deleted request has no body");

        std::int64_t other = 0;
        require(sceNpWebApi2CreateRequest(user, "matchmaking", "/v1/tickets", "GET", nullptr, &other) == 0, "another request is made");
        NpWebApi2ResponseInformationOption untouched{};
        untouched.http_status = -5;
        require(sceNpWebApi2SendRequest(other, nullptr, 0, &untouched) == Unavailable && untouched.http_status == -5,
            "a group the launcher does not offer fails as it does offline");
        require(sceNpWebApi2ReadData(other, chunk, sizeof(chunk)) == Unavailable, "a request that was not offered has no body");
        sceNpWebApi2DeleteRequest(other);

        // Push events: a push context made here, news from the launcher handed to the game's
        // callbacks on its own thread through sceNpCheckCallback.
        const int handle = sceNpWebApi2PushEventCreateHandle(library);
        require(handle > 0, "a push event handle is made");
        const FilterParameter memberTypes[] = {parameter("psn:sessionManager:ps:m:players:created"), parameter("psn:sessionManager:ps:m:players:deleted")};
        const int memberFilter = sceNpWebApi2PushEventCreateFilter(library, handle, "sessionManager", 0, memberTypes, 2);
        require(memberFilter > 0, "a session filter is made");
        const FilterParameter deletedType[] = {parameter("psn:sessionManager:playerSession:deleted")};
        const int plainFilter = sceNpWebApi2PushEventCreateFilter(library, handle, nullptr, 0xFFFFFFFFu, deletedType, 1);
        int userArg = 7;
        const int contextCallback = sceNpWebApi2PushEventRegisterPushContextCallback(user, memberFilter, reinterpret_cast<void*>(onPushContextEvent), &userArg);
        require(contextCallback > 0, "a push context callback is registered");
        const int plainCallback = sceNpWebApi2PushEventRegisterCallback(user, plainFilter, reinterpret_cast<void*>(onPushEvent), &userArg);
        require(plainCallback > 0, "a push event callback is registered");
        char context[37] = {};
        require(sceNpWebApi2PushEventCreatePushContext(user, context) == 0, "a push context is made while the launcher is there");
        require(std::strlen(context) == 36 && context[8] == '-' && context[13] == '-' && context[14] == '4' && context[18] == '-' && context[23] == '-',
            "the push context is a version 4 UUID");
        char second[37] = {};
        require(sceNpWebApi2PushEventCreatePushContext(user, second) == 0 && std::string(second) != context, "every push context is new");
        require(sceNpWebApi2PushEventDeletePushContext(user, second) == 0, "a push context can be deleted");
        require(sceNpWebApi2PushEventStartPushContextCallback(user, context) == 0, "the push context starts");

        auto send = [&](const std::string& pushContextId, const std::string& dataType, const std::string& data) {
            Online::Wire::PushEvent event;
            event.service = "sessionManager";
            event.pushContextId = pushContextId;
            event.dataType = dataType;
            event.data.assign(data.begin(), data.end());
            event.extended = {{"sessionId", "s-1"}};
            event.to = 42;
            event.from = 77;
            event.fromOnlineId = "bob";
            launcher.Send(Online::Wire::Type::PushEvent, 0, 0, Online::Wire::Encode(event));
        };
        send(context, "psn:sessionManager:ps:leader:updated", "{}");
        send(second, "psn:sessionManager:ps:m:players:created", "{\"gone\":1}");
        send(context, "psn:sessionManager:ps:m:players:created", "{\"member\":1}");
        require(pump([] { return !contextDeliveries.empty(); }), "the push context's callback gets the event");
        pump([] { return false; }, std::chrono::milliseconds(300));
        require(contextDeliveries.size() == 1, "events of another data type or a deleted push context are not delivered");
        const auto& got = contextDeliveries[0];
        require(got.userContextId == user && got.callbackId == contextCallback && got.pushContextId == context && got.type == 0, "context, callback and type");
        require(got.service == "sessionManager" && got.dataType == "psn:sessionManager:ps:m:players:created" && got.data == "{\"member\":1}", "service, type and data");
        require(got.to == 42 && got.toOnlineId == "player" && got.from == 77 && got.fromOnlineId == "bob", "to and from");
        require(got.extended.size() == 1 && got.extended[0].first == "sessionId" && got.extended[0].second == "s-1", "extended data");
        require(got.userArg == &userArg && plainDeliveries.empty(), "the game's argument comes back, and a plain callback does not get a push context's event");

        send("", "psn:sessionManager:playerSession:deleted", "{\"deleted\":1}");
        require(pump([] { return !plainDeliveries.empty(); }), "an event for no push context reaches the plain callback");
        require(plainDeliveries[0].callbackId == plainCallback && plainDeliveries[0].data == "{\"deleted\":1}" && contextDeliveries.size() == 1,
            "only the filter with that data type gets it");
        require(sceNpWebApi2PushEventUnregisterCallback(user, contextCallback) == 0, "the callback is unregistered");
        send(context, "psn:sessionManager:ps:m:players:deleted", "{}");
        pump([] { return false; }, std::chrono::milliseconds(300));
        require(contextDeliveries.size() == 1, "an unregistered callback gets nothing");
    } catch (const std::exception& error) {
        std::cerr << "online web api2: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online web api2: ok\n";
    return 0;
}
