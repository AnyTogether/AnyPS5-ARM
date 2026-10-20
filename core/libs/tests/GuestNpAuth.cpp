#include "SceTypes.hpp"

#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceNpAuthAbortRequest(int req_id);
int APS5_VABI sceNpAuthCreateAsyncRequest(const void* param);
int APS5_VABI sceNpAuthCreateRequest(void);
int APS5_VABI sceNpAuthDeleteRequest(int req_id);
int APS5_VABI sceNpAuthGetAuthorizationCode(int req_id, const void* param, void* auth_code);
int APS5_VABI sceNpAuthGetAuthorizationCodeV3(int req_id, const void* param, void* auth_code, int* issuer_id);
int APS5_VABI sceNpAuthGetAuthorizedAppCode();
int APS5_VABI sceNpAuthGetIdToken(int req_id, const void* param, void* id_token);
int APS5_VABI sceNpAuthGetIdTokenV3(int req_id, const void* param, void* id_token);
int APS5_VABI sceNpAuthPollAsync(int req_id, int* result);
int APS5_VABI sceNpAuthSetTimeout(int req_id, int resolve_retry, uint32_t resolve_timeout, uint32_t connect_timeout, uint32_t send_timeout, uint32_t receive_timeout);
int APS5_VABI sceNpAuthWaitAsync(int req_id, int* result);
}

static void Require(bool condition) {
    if (!condition) {
        std::abort();
    }
}

int main() {
    constexpr int invalidArgument = static_cast<int>(0x80550301);
    constexpr int signedOut = static_cast<int>(0x80550006);
    constexpr int aborted = static_cast<int>(0x80550304);
    constexpr int requestNotFound = static_cast<int>(0x80550306);
    constexpr int invalidId = static_cast<int>(0x80550307);
    constexpr int pollRunning = 1;

    const int syncReq = sceNpAuthCreateRequest();
    const int syncReq2 = sceNpAuthCreateRequest();
    Require(syncReq > 0);
    Require(syncReq2 > syncReq);

    const int asyncReq = sceNpAuthCreateAsyncRequest(nullptr);
    const int asyncReq2 = sceNpAuthCreateAsyncRequest(nullptr);
    Require(asyncReq > syncReq2);
    Require(asyncReq2 > asyncReq);

    alignas(8) char param[16] = {};
    alignas(8) char token[16] = {};
    alignas(8) char authCode[16] = {};
    int issuerId = 0;

    Require(sceNpAuthSetTimeout(syncReq, 2, 5000000, 10000000, 10000000, 10000000) == 0);
    Require(sceNpAuthSetTimeout(asyncReq, 0, 0, 0, 0, 0) == 0);

    int pollUnprocessed = 0;
    Require(sceNpAuthPollAsync(asyncReq, &pollUnprocessed) == invalidId);
    int waitUnprocessed = 0;
    Require(sceNpAuthWaitAsync(asyncReq, &waitUnprocessed) == invalidId);

    Require(sceNpAuthGetAuthorizedAppCode() == signedOut);

    Require(sceNpAuthGetIdToken(syncReq, nullptr, token) == invalidArgument);
    Require(sceNpAuthGetIdToken(syncReq, param, nullptr) == invalidArgument);
    Require(sceNpAuthGetIdToken(syncReq, nullptr, nullptr) == invalidArgument);
    Require(sceNpAuthGetIdTokenV3(syncReq, nullptr, token) == invalidArgument);
    Require(sceNpAuthGetIdTokenV3(syncReq, param, nullptr) == invalidArgument);
    Require(sceNpAuthGetIdTokenV3(syncReq, nullptr, nullptr) == invalidArgument);
    Require(sceNpAuthGetIdToken(syncReq, param, token) == signedOut);
    Require(sceNpAuthGetIdToken(syncReq, param, token) == invalidArgument);
    Require(sceNpAuthGetIdTokenV3(syncReq, param, token) == invalidArgument);

    Require(sceNpAuthGetAuthorizationCode(syncReq2, nullptr, authCode) == invalidArgument);
    Require(sceNpAuthGetAuthorizationCode(syncReq2, param, nullptr) == invalidArgument);
    Require(sceNpAuthGetAuthorizationCodeV3(syncReq, nullptr, authCode, &issuerId) == invalidArgument);
    Require(sceNpAuthGetAuthorizationCodeV3(syncReq, param, nullptr, &issuerId) == invalidArgument);
    Require(sceNpAuthGetAuthorizationCode(syncReq2, param, authCode) == signedOut);
    Require(sceNpAuthGetAuthorizationCode(syncReq2, param, authCode) == invalidArgument);
    Require(sceNpAuthGetAuthorizationCodeV3(syncReq2, param, authCode, &issuerId) == invalidArgument);

    Require(sceNpAuthGetIdTokenV3(asyncReq, param, token) == 0);
    Require(sceNpAuthGetIdTokenV3(asyncReq, param, token) == invalidArgument);
    int asyncPoll = 0;
    Require(sceNpAuthPollAsync(asyncReq, &asyncPoll) == pollRunning);
    Require(asyncPoll == 0);
    Require(sceNpAuthPollAsync(asyncReq, &asyncPoll) == 0);
    Require(asyncPoll == signedOut);
    Require(sceNpAuthPollAsync(asyncReq, &asyncPoll) == 0);
    Require(asyncPoll == signedOut);
    int asyncWait = 0;
    Require(sceNpAuthWaitAsync(asyncReq, &asyncWait) == 0);
    Require(asyncWait == signedOut);

    Require(sceNpAuthGetAuthorizationCodeV3(asyncReq2, param, authCode, &issuerId) == 0);
    Require(sceNpAuthGetAuthorizationCodeV3(asyncReq2, param, authCode, &issuerId) == invalidArgument);
    int asyncWait2 = 0;
    Require(sceNpAuthWaitAsync(asyncReq2, &asyncWait2) == 0);
    Require(asyncWait2 == signedOut);

    constexpr int unknownReq = 999999;
    Require(sceNpAuthGetIdToken(unknownReq, param, token) == requestNotFound);
    Require(sceNpAuthGetIdTokenV3(unknownReq, param, token) == requestNotFound);
    Require(sceNpAuthGetAuthorizationCode(unknownReq, param, authCode) == requestNotFound);
    Require(sceNpAuthGetAuthorizationCodeV3(unknownReq, param, authCode, &issuerId) == requestNotFound);
    int pollResult = 0;
    Require(sceNpAuthPollAsync(unknownReq, &pollResult) == requestNotFound);
    int waitResult = 0;
    Require(sceNpAuthWaitAsync(unknownReq, &waitResult) == requestNotFound);
    Require(sceNpAuthSetTimeout(unknownReq, 2, 5000000, 10000000, 10000000, 10000000) == requestNotFound);

    Require(sceNpAuthWaitAsync(syncReq, nullptr) == invalidArgument);
    Require(sceNpAuthWaitAsync(syncReq, &waitResult) == invalidId);
    Require(sceNpAuthPollAsync(syncReq, &pollResult) == invalidId);

    Require(sceNpAuthAbortRequest(asyncReq) == 0);
    Require(sceNpAuthGetIdTokenV3(asyncReq, param, token) == invalidArgument);
    Require(sceNpAuthAbortRequest(unknownReq) == requestNotFound);

    const int abortedReq = sceNpAuthCreateAsyncRequest(nullptr);
    Require(sceNpAuthAbortRequest(abortedReq) == 0);
    Require(sceNpAuthGetIdTokenV3(abortedReq, param, token) == aborted);
    Require(sceNpAuthGetAuthorizationCodeV3(abortedReq, param, authCode, &issuerId) == aborted);
    int abortedWait = 0;
    Require(sceNpAuthWaitAsync(abortedReq, &abortedWait) == 0);
    Require(abortedWait == aborted);

    Require(sceNpAuthDeleteRequest(syncReq) == 0);
    Require(sceNpAuthGetIdTokenV3(syncReq, param, token) == requestNotFound);
    Require(sceNpAuthWaitAsync(syncReq, &waitResult) == requestNotFound);
    Require(sceNpAuthSetTimeout(syncReq, 2, 5000000, 10000000, 10000000, 10000000) == requestNotFound);

    return 0;
}
