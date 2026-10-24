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
}

namespace {

constexpr int InitialUser = 0x10000000;
constexpr int Unavailable = static_cast<int>(0x80553406);

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
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
        ::setenv("ANYPS5_ONLINE", endpoint.c_str(), 1);
        ::setenv("ANYPS5_ONLINE_SECRET", hex.c_str(), 1);

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
    } catch (const std::exception& error) {
        std::cerr << "online web api2: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online web api2: ok\n";
    return 0;
}
