#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <array>

extern "C" {
int APS5_VABI sceNpSessionSignalingInitialize(void* param);
int APS5_VABI sceNpSessionSignalingCreateContext(const void* param, std::uint32_t* contextId);
int APS5_VABI sceNpSessionSignalingCreateContext2(const void* param, std::uint32_t* contextId);
int APS5_VABI sceNpSessionSignalingDestroyContext(std::uint32_t contextId);
int APS5_VABI sceNpSessionSignalingDeactivate(std::uint32_t contextId, std::uint32_t connectionId);
std::int32_t APS5_VABI sceNpSessionSignalingGetLocalNetInfo(std::int32_t contextId, void* info);
int APS5_VABI sceNpSessionSignalingRequestPrepare(std::uint32_t contextId, std::uint32_t* requestId);
std::int32_t APS5_VABI sceNpSessionSignalingGetConnectionStatus(std::int32_t contextId, std::int32_t connectionId, std::int32_t* status, void* peerAddress, std::uint16_t* peerPort);
int APS5_VABI sceNpSessionSignalingTerminate(void);
int APS5_VABI sceNpSessionSignalingGetConnectionStatistics(void* statistics);
int APS5_VABI sceNpSessionSignalingGetConnectionFromPeerAddress(std::uint32_t contextId, const void* peerAddress, std::uint32_t* connectionId);
}

namespace {

constexpr int InvalidArgument = static_cast<int>(0x80553303u);
constexpr int Unavailable = static_cast<int>(0x80552D06u);
constexpr int ConnectionNotFound = static_cast<int>(0x8055330Cu);
constexpr int NotInitialized = static_cast<int>(0x80553301u);
constexpr int AlreadyInitialized = static_cast<int>(0x80553302u);
constexpr int ContextLimit = static_cast<int>(0x80553307u);
constexpr int ContextNotFound = static_cast<int>(0x80553308u);
constexpr int GroupNotFound = static_cast<int>(0x8055330Au);

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "NpSessionSignaling: %s\n", message);
        std::abort();
    }
}

}

int main() {
    alignas(8) unsigned char initializeParam[40] = {};
    Require(sceNpSessionSignalingTerminate() == NotInitialized, "terminate before initialize");
    Require(sceNpSessionSignalingCreateContext2(nullptr, nullptr) == NotInitialized, "initialization check precedes context arguments");
    Require(sceNpSessionSignalingGetConnectionStatus(0, 0, nullptr, nullptr, nullptr) == NotInitialized, "status before initialize");
    Require(sceNpSessionSignalingInitialize(nullptr) == InvalidArgument, "null initialize parameter");
    Require(sceNpSessionSignalingInitialize(initializeParam) == InvalidArgument, "zero pool size");
    const std::uint64_t poolSize = 4 * 1024 * 1024;
    std::memcpy(initializeParam + 8, &poolSize, sizeof(poolSize));
    Require(sceNpSessionSignalingInitialize(initializeParam) == 0, "initialize failed");
    Require(sceNpSessionSignalingInitialize(nullptr) == AlreadyInitialized, "initialization check precedes initialize arguments");
    alignas(8) unsigned char contextParam[56] = {};
    std::uint32_t contextId = 0;
    Require(sceNpSessionSignalingCreateContext(nullptr, &contextId) == InvalidArgument, "null context parameter");
    Require(contextId == 0, "invalid context parameter wrote an id");
    Require(sceNpSessionSignalingCreateContext2(nullptr, &contextId) == InvalidArgument, "null context2 parameter");
    Require(contextId == 0, "invalid context2 parameter wrote an id");
    Require(sceNpSessionSignalingCreateContext(contextParam, nullptr) == InvalidArgument, "null context id");
    Require(sceNpSessionSignalingCreateContext2(contextParam, nullptr) == InvalidArgument, "null context2 id");
    Require(sceNpSessionSignalingCreateContext2(contextParam, &contextId) == 0, "context creation failed");
    const auto firstId = contextId;
    Require(sceNpSessionSignalingCreateContext2(contextParam, &contextId) == ContextLimit, "duplicate user context");
    Require(contextId == firstId, "duplicate context modified output");
    std::array<std::uint32_t, 9> otherContexts{};
    for (std::int32_t userId = 1; userId <= 9; ++userId) {
        std::memcpy(contextParam, &userId, sizeof(userId));
        Require(sceNpSessionSignalingCreateContext2(contextParam, &otherContexts[userId - 1]) == 0, "create remaining contexts");
    }
    const std::int32_t overflowUser = 10;
    std::memcpy(contextParam, &overflowUser, sizeof(overflowUser));
    Require(sceNpSessionSignalingCreateContext2(contextParam, &contextId) == ContextLimit, "context limit");
    Require(contextId == firstId, "context limit modified output");
    Require(sceNpSessionSignalingDestroyContext(firstId) == 0, "destroy first context");
    Require(sceNpSessionSignalingDestroyContext(firstId) == ContextNotFound, "destroy stale context");
    Require(sceNpSessionSignalingCreateContext2(contextParam, &contextId) == 0, "reuse context slot");
    Require(contextId != firstId, "reused context kept stale id");

    std::uint32_t requestId = 0xa5a5a5a5u;
    Require(sceNpSessionSignalingRequestPrepare(firstId, &requestId) == ContextNotFound, "prepare stale context");
    Require(sceNpSessionSignalingRequestPrepare(firstId, nullptr) == InvalidArgument, "prepare argument precedence");
    Require(sceNpSessionSignalingRequestPrepare(contextId, nullptr) == InvalidArgument, "null request id");
    Require(sceNpSessionSignalingRequestPrepare(contextId, &requestId) == Unavailable, "prepare without network");
    Require(requestId == 0xa5a5a5a5u, "failed prepare wrote a request id");

    const auto netContextId = static_cast<std::int32_t>(contextId);
    unsigned char info[16];
    std::memset(info, 0xa5, sizeof(info));
    unsigned char untouched[sizeof(info)];
    std::memcpy(untouched, info, sizeof(info));
    Require(sceNpSessionSignalingGetLocalNetInfo(netContextId, nullptr) == InvalidArgument, "null info");
    Require(sceNpSessionSignalingGetLocalNetInfo(netContextId, info) == Unavailable, "local net info without network");
    Require(std::memcmp(info, untouched, sizeof(info)) == 0, "failed query modified the info");

    std::int32_t status = 0x5a5a5a5a;
    std::uint32_t peerAddress = 0xa5a5a5a5u;
    std::uint16_t peerPort = 0xa5a5;
    Require(sceNpSessionSignalingGetConnectionStatus(firstId, 1, &status, &peerAddress, &peerPort) == ContextNotFound, "status stale context");
    Require(sceNpSessionSignalingGetConnectionStatus(netContextId, 1, nullptr, &peerAddress, &peerPort) == InvalidArgument, "null connection status");
    Require(sceNpSessionSignalingGetConnectionStatus(netContextId, 1, &status, &peerAddress, &peerPort) == ConnectionNotFound, "connection without network");
    Require(sceNpSessionSignalingGetConnectionStatus(netContextId, 1, &status, nullptr, nullptr) == ConnectionNotFound, "connection without peer outputs");
    Require(status == 0x5a5a5a5a && peerAddress == 0xa5a5a5a5u && peerPort == 0xa5a5, "failed status query wrote an output");
    unsigned char statistics[16];
    std::memset(statistics, 0xa5, sizeof(statistics));
    unsigned char untouchedStatistics[sizeof(statistics)];
    std::memcpy(untouchedStatistics, statistics, sizeof(statistics));
    Require(sceNpSessionSignalingGetConnectionStatistics(nullptr) == InvalidArgument, "null connection statistics");
    Require(sceNpSessionSignalingGetConnectionStatistics(statistics) == Unavailable, "connection statistics without network");
    Require(std::memcmp(statistics, untouchedStatistics, sizeof(statistics)) == 0, "failed statistics query wrote an output");
    alignas(8) unsigned char peer[16] = {};
    std::uint32_t connectionId = 0xa5a5a5a5u;
    Require(sceNpSessionSignalingGetConnectionFromPeerAddress(contextId, nullptr, &connectionId) == InvalidArgument, "null peer address");
    Require(sceNpSessionSignalingGetConnectionFromPeerAddress(contextId, peer, nullptr) == InvalidArgument, "null peer connection id");
    Require(sceNpSessionSignalingGetConnectionFromPeerAddress(firstId, peer, &connectionId) == ContextNotFound, "peer lookup stale context");
    Require(sceNpSessionSignalingGetConnectionFromPeerAddress(contextId, peer, &connectionId) == Unavailable, "peer lookup without network");
    Require(connectionId == 0xa5a5a5a5u, "failed peer lookup wrote a connection id");
    Require(sceNpSessionSignalingDeactivate(firstId, 1) == ContextNotFound, "deactivate stale context");
    Require(sceNpSessionSignalingDeactivate(contextId, 1) == GroupNotFound, "deactivate nonexistent group");

    Require(sceNpSessionSignalingTerminate() == 0, "terminate failed");
    Require(sceNpSessionSignalingDestroyContext(contextId) == NotInitialized, "destroy after terminate");
    Require(sceNpSessionSignalingTerminate() == NotInitialized, "repeated terminate");
    Require(sceNpSessionSignalingInitialize(initializeParam) == 0, "reinitialize");
    Require(sceNpSessionSignalingRequestPrepare(contextId, &requestId) == ContextNotFound, "reinitialize retained a context");
    Require(sceNpSessionSignalingTerminate() == 0, "final terminate");
}
