#include "prx/libSceNetCtl/include/Online.hpp"
#include "prx/libSceNpManager/include/LegacyExports.hpp"
#include "prx/libc/include/general/ExportMacros.hpp"
#include "prx/libSceNpManager/include/Api.hpp"
#include "prx/libSceNpManager/include/InGameMessageIds.hpp"
#include <cerrno>
#include <cstdint>
#include <cstddef>
#include <string>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libSceUserService/UserService.hpp"
#include <algorithm>
#include <array>
#include <cstring>
#include <atomic>
#include <mutex>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

// PSN is not emulated: the user is reported as signed out and online queries fail.
static constexpr int SCE_NP_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80550003);
static constexpr int SCE_NP_ERROR_INVALID_PLATFORM_TYPE = static_cast<int>(0x80550004);
static constexpr int SCE_NP_ERROR_OUT_OF_MEMORY = static_cast<int>(0x80550005);
static constexpr int SCE_NP_ERROR_SIGNED_OUT = static_cast<int>(0x80550006);
static constexpr int SCE_NP_ERROR_USER_NOT_FOUND = static_cast<int>(0x80550007);
static constexpr int SCE_NP_ERROR_CALLBACK_ALREADY_REGISTERED = static_cast<int>(0x80550008);
static constexpr int SCE_NP_ERROR_CALLBACK_NOT_REGISTERED = static_cast<int>(0x80550009);
static constexpr int SCE_NP_ERROR_INVALID_SIZE = static_cast<int>(0x80550011);
static constexpr int SCE_NP_ERROR_REQUEST_NOT_FOUND = static_cast<int>(0x80550014);
static constexpr int SCE_NP_ERROR_INVALID_ID = static_cast<int>(0x80550015);
static constexpr int SCE_NP_ERROR_CALLBACK_MAX = static_cast<int>(0x8055001D);
static constexpr int NP_ID_MAPPER_REFUSED_ARGUMENT = static_cast<int>(0x80553083);
static constexpr int NP_ID_MAPPER_REFUSED_REQUEST_ID = static_cast<int>(0x80553085);
static constexpr int NP_MANAGER_INT_REQUEST_DUPLICATE = static_cast<int>(0x80559D03);
static constexpr int NP_MANAGER_INT_REQUEST_TABLE_FULL = static_cast<int>(0x80559D05);
static constexpr int NP_MANAGER_INT_REQUEST_NOT_IN_TABLE = static_cast<int>(0x80559D0A);
static constexpr uint32_t NP_STATE_SIGNED_OUT = 1;
static constexpr uint32_t NP_STATE_SIGNED_IN = 2;
static constexpr int NP_POLL_ASYNC_FINISHED = 0;
static constexpr uint32_t NP_REACHABILITY_STATE_UNAVAILABLE = 0;
static constexpr uint32_t NP_REACHABILITY_STATE_REACHABLE = 2;
static constexpr uint32_t NP_GAME_PRESENCE_STATUS_OFFLINE = 0;

static std::atomic<int> g_nextRequest{1};

static bool CopyGuestOut(void* dst, const void* src, std::size_t size) {
    const auto preserved = errno;
    const bool ok = GuestCopyOut_nid_no_patch(dst, src, size);
    errno = preserved;
    return ok;
}

static constexpr int NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80552B02);
static constexpr int SCE_NP_ASM_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x8055A201);
static constexpr int SCE_NP_ASM_ERROR_NOT_INITIALIZED = static_cast<int>(0x8055A202);
static constexpr int SCE_NP_ASM_ERROR_INVALID_ARGUMENT = static_cast<int>(0x8055A203);
static constexpr int SCE_NP_ASM_CLIENT_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x8055A281);
static constexpr int SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED = static_cast<int>(0x8055A282);
static constexpr int SCE_NP_ASM_CLIENT_ERROR_INVALID_ARGUMENT = static_cast<int>(0x8055A283);

namespace {
std::mutex g_asmMutex;
bool g_asmInitialized = false;
bool g_asmClientInitialized = false;
const void* g_asmClient = nullptr;
std::array<char, 16> g_asmTitleId = {};
std::set<const void*> g_asmConnections;
std::set<const void*> g_asmRequests;
}

static bool AsmInitialized() {
    std::lock_guard lock(g_asmMutex);
    return g_asmInitialized;
}

static bool AsmClientInitialized() {
    std::lock_guard lock(g_asmMutex);
    return g_asmClientInitialized;
}

static constexpr int NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND = static_cast<int>(0x80552B03);
static constexpr int NP_IN_GAME_MESSAGE_ERROR_HANDLE_NOT_FOUND = static_cast<int>(0x80552B05);
static constexpr int NP_IN_GAME_MESSAGE_ERROR_NOT_CONNECTED = static_cast<int>(0x80552B08);

namespace {
struct InGameMessageCallback {
    std::uint64_t address = 0;
    void* userdata = nullptr;
};

struct InGameMessageContext {
    std::set<std::int32_t> handles;
    std::map<std::int32_t, InGameMessageCallback> callbacks;
};

std::mutex inGameMessageMutex;
std::map<std::int32_t, InGameMessageContext> inGameMessageContexts;
std::int32_t nextInGameMessageContext = 1;
std::int32_t nextInGameMessageHandle = 1;

InGameMessageContext* FindInGameMessageContext(std::int32_t libCtxId) {
    const auto found = inGameMessageContexts.find(libCtxId);
    return found == inGameMessageContexts.end() ? nullptr : &found->second;
}
}

namespace {
std::mutex reachabilityMutex;
NpReachabilityStateCallback reachabilityCallback = nullptr;
void* reachabilityUserdata = nullptr;
bool reachabilityPending = false;
std::mutex requestMutex;
std::unordered_set<int> liveRequests;
std::unordered_map<int, int> requestResults;

std::optional<Online::Wire::Account> SignedInAccount() {
    const auto state = Online::CurrentAccount();
    if (!state || !state->account.signedIn) return std::nullopt;
    return state->account;
}

std::optional<Online::Wire::Account> SignedInUser(int userId) {
    if (userId != USER_SERVICE_INITIAL_USER_ID) return std::nullopt;
    return SignedInAccount();
}

struct PlusCheckParameter {
    std::uint64_t size;
    std::int32_t userId;
    std::uint8_t padding[4];
    std::uint64_t features;
    std::uint8_t reserved[32];
};
static_assert(sizeof(PlusCheckParameter) == 56);

bool PlusAllowed(const void* param) {
    PlusCheckParameter fields{};
    std::memcpy(&fields, param, sizeof(fields));
    return fields.size == sizeof(PlusCheckParameter) && SignedInUser(fields.userId).has_value();
}

void PlusFields(Online::Fields& in, const void* param) {
    if (!param) return;
    PlusCheckParameter fields{};
    std::memcpy(&fields, param, sizeof(fields));
    in.Uint("size", fields.size).Int("user_id", fields.userId).Hex("features", fields.features);
}

void FillOnlineId(NpOnlineId& out, const std::string& onlineId) {
    std::memset(&out, 0, sizeof(out));
    std::memcpy(out.data, onlineId.data(), std::min(onlineId.size(), sizeof(out.data) - 1));
}

bool SameOnlineId(const NpOnlineId& onlineId, const std::string& ours) {
    const std::string_view theirs(onlineId.data, strnlen(onlineId.data, sizeof(onlineId.data) - 1));
    return theirs == ours;
}

int AddRequest() {
    const int reqId = g_nextRequest.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard lock(requestMutex);
    liveRequests.insert(reqId);
    return reqId;
}

std::mutex idMapperMutex;
std::uint32_t nextIdMapperRequest = 1;
std::unordered_set<int> idMapperRequests;
constexpr std::size_t NP_MANAGER_INT_REQUEST_SLOTS = 64;
std::mutex managerIntMutex;
std::uint32_t nextManagerIntRequest = 1;
std::unordered_set<int> managerIntRequests;

int RequestResult(int reqId, int result) {
    if (reqId == 0) return SCE_NP_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(requestMutex);
    if (!liveRequests.count(reqId)) return SCE_NP_ERROR_REQUEST_NOT_FOUND;
    requestResults[reqId] = result;
    return result;
}

int SignedOutRequest(int reqId) {
    return RequestResult(reqId, SCE_NP_ERROR_SIGNED_OUT);
}

constexpr int NP_STATE_CALLBACK_MAX = 8;

struct StateCallbackA {
    NpStateCallbackA callback = nullptr;
    void* userdata = nullptr;
    bool pending = false;
};

struct StateCallback {
    NpStateCallback callback = nullptr;
    void* userdata = nullptr;
    bool pending = false;
};

struct ToolkitStateCallback {
    NpStateCallbackForToolkit callback = nullptr;
    void* userdata = nullptr;
    bool pending = false;
};

std::mutex stateMutex;
std::array<StateCallbackA, NP_STATE_CALLBACK_MAX> stateCallbacksA;
StateCallback stateCallback;
std::uint64_t seenAccountGeneration = 0;
ToolkitStateCallback toolkitStateCallback;

constexpr int NP_GAME_PRESENCE_CALLBACK_MAX = 8;

struct GamePresenceCallbackEntry {
    int handle = 0;
    void* callback = nullptr;
    void* userdata = nullptr;
    bool inUse = false;
};

std::mutex gamePresenceMutex;
std::array<GamePresenceCallbackEntry, NP_GAME_PRESENCE_CALLBACK_MAX> gamePresenceCallbacksA{};
int nextGamePresenceHandle = 0;
}

extern "C" {

int APS5_VABI sceNpAsmAbort(void) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    return 0;
}
int APS5_VABI sceNpAsmClientAbortRequest(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientClearNpTitleToken(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientClearNpTitleTokenA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientCreateRequest2(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientCreateResourceContext(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientCreateResourceContext2(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientDeleteRequest(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientDeleteResourceContext(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientDeleteResourceContext2(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetAppId(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetCacheControlMaxAge(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetGameNpTitleInfo(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetGameNpTitleToken(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetGameTitleBanInfo(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpComInfo2(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpComInfo2A(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpComInfo3(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpComInfo4(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpTitleId(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpTitleToken(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpTitleToken2(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetNpTitleTokenA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetRelatedGameNpTitleIds(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetRelatedGameNpTitleIdsA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetRelatedGameNpTitleIdsResult(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceBaseUrl(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceBaseUrlA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceBaseUrlWithNpTitleId(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceBaseUrlWithNpTitleIdA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceIdInfo(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientGetServiceIdInfoA(void) {
    if (!AsmClientInitialized()) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmClientInitialize(void* client, const void* param) {
    std::lock_guard lock(g_asmMutex);
    if (g_asmClientInitialized) return SCE_NP_ASM_CLIENT_ERROR_ALREADY_INITIALIZED;
    if (!param) return SCE_NP_ASM_CLIENT_ERROR_INVALID_ARGUMENT;
    g_asmClientInitialized = true;
    g_asmClient = client;
    return 0;
}
int APS5_VABI sceNpAsmClientSetNpTitleId(void* client, const char* npTitleId) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmClientInitialized) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    if (!client || !npTitleId) return SCE_NP_ASM_CLIENT_ERROR_INVALID_ARGUMENT;
    std::array<char, 16> title = {};
    for (std::size_t index = 0; index < title.size(); ++index) {
        if (!GuestCopyIn_nid_no_patch(&title[index], npTitleId + index, sizeof(char))) return SCE_NP_ASM_CLIENT_ERROR_INVALID_ARGUMENT;
        if (title[index] == 0) break;
    }
    g_asmTitleId = title;
    return 0;
}
int APS5_VABI sceNpAsmClientTerminate(void* client) {
    (void)client;
    std::lock_guard lock(g_asmMutex);
    if (!g_asmClientInitialized) return SCE_NP_ASM_CLIENT_ERROR_NOT_INITIALIZED;
    g_asmClientInitialized = false;
    g_asmClient = nullptr;
    g_asmTitleId.fill(0);
    return 0;
}
int APS5_VABI sceNpAsmCreateConnection(std::int32_t connectionId, void* connection) {
    (void)connectionId;
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    if (!connection) return SCE_NP_ASM_ERROR_INVALID_ARGUMENT;
    g_asmConnections.insert(connection);
    return 0;
}
int APS5_VABI sceNpAsmCreateRequest(void* connection, void* request, void* result) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    if (!connection || !request || !result) return SCE_NP_ASM_ERROR_INVALID_ARGUMENT;
    g_asmRequests.insert(request);
    return 0;
}
int APS5_VABI sceNpAsmDeleteConnection(void* connection) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    if (!connection) return SCE_NP_ASM_ERROR_INVALID_ARGUMENT;
    g_asmConnections.erase(connection);
    return 0;
}
int APS5_VABI sceNpAsmDeleteRequest(void* request) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    g_asmRequests.erase(request);
    return 0;
}
int APS5_VABI sceNpAsmGenerateNpTitleToken(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGenerateNpTitleToken2(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGetNpCommInfo(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGetNpCommInfo2(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGetRelatedGameNpTitleIds(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGetServiceBaseUrl(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmGetServiceIdInfo(void) {
    if (!AsmInitialized()) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpAsmInitialize(void) {
    std::lock_guard lock(g_asmMutex);
    if (g_asmInitialized) return SCE_NP_ASM_ERROR_ALREADY_INITIALIZED;
    g_asmInitialized = true;
    return 0;
}
int APS5_VABI sceNpAsmTerminate(void) {
    std::lock_guard lock(g_asmMutex);
    if (!g_asmInitialized) return SCE_NP_ASM_ERROR_NOT_INITIALIZED;
    g_asmInitialized = false;
    return 0;
}
int APS5_VABI sceNpCheckNpAvailabilityA(int reqId, int userId) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("reqId", static_cast<std::int64_t>(reqId)).Int("userId", static_cast<std::int64_t>(userId)); });
    if (userId == USER_SERVICE_USER_ID_INVALID) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    if (SignedInUser(userId)) return call.Return(RequestResult(reqId, 0));
    return call.Return(SignedOutRequest(reqId));
}
int APS5_VABI sceNpGetAccountDateOfBirthA(int userId, void* dateOfBirth) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userId", static_cast<std::int64_t>(userId)).Ptr("dateOfBirth", dateOfBirth); });
    if (!dateOfBirth || userId == USER_SERVICE_USER_ID_INVALID) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}
int APS5_VABI sceNpGetAccountLanguageA(int reqId, int userId, void* language) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("reqId", static_cast<std::int64_t>(reqId)).Int("userId", static_cast<std::int64_t>(userId)).Ptr("language", language); });
    if (!language || userId == USER_SERVICE_USER_ID_INVALID) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SignedOutRequest(reqId));
}
int APS5_VABI sceNpGetGamePresenceStatus(const NpOnlineId* onlineId, uint32_t* status) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("onlineId", onlineId).Ptr("status", status); });
    if (!onlineId || !status) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    NpOnlineId localOnlineId{};
    const int savedErrno = errno;
    if (!GuestCopyIn_nid_no_patch(&localOnlineId, onlineId, sizeof(localOnlineId))) {
        errno = savedErrno;
        return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    }
    const uint32_t presence = NP_GAME_PRESENCE_STATUS_OFFLINE;
    const bool copied = GuestCopyOut_nid_no_patch(status, &presence, sizeof(presence));
    errno = savedErrno;
    if (!copied) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}
int APS5_VABI sceNpGetGamePresenceStatusA(int userId, uint32_t* status) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userId", static_cast<std::int64_t>(userId)).Ptr("status", status); });
    if (!status || userId == USER_SERVICE_USER_ID_INVALID) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const uint32_t presence = NP_GAME_PRESENCE_STATUS_OFFLINE;
    const int savedErrno = errno;
    const bool copied = GuestCopyOut_nid_no_patch(status, &presence, sizeof(presence));
    errno = savedErrno;
    if (!copied) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}
int APS5_VABI sceNpGetParentalControlInfoA(int reqId, int userId, int8_t* age, void* info) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("reqId", static_cast<std::int64_t>(reqId)).Int("userId", static_cast<std::int64_t>(userId)).Ptr("age", age).Ptr("info", info); });
    if (!age || !info || userId == USER_SERVICE_USER_ID_INVALID) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SignedOutRequest(reqId));
}
int APS5_VABI sceNpIdMapperAbortRequest(int reqId) {
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    std::lock_guard lock(idMapperMutex);
    return idMapperRequests.count(reqId) ? 0 : SCE_NP_ERROR_REQUEST_NOT_FOUND;
}
int APS5_VABI sceNpIdMapperAccountIdToNpId(int reqId, int userId, const void* input, void* output, std::uint32_t value, std::uint8_t flag, std::uint64_t extra) {
    (void)flag;
    (void)extra;
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    if (userId == USER_SERVICE_USER_ID_INVALID || !input || !output || value < 1 || value > 1000) return NP_ID_MAPPER_REFUSED_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpIdMapperAccountIdToOnlineId(int reqId, int userId, const void* input, void* output, std::uint32_t value, std::uint8_t flag, std::uint64_t extra) {
    (void)flag;
    (void)extra;
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    if (userId == USER_SERVICE_USER_ID_INVALID || !input || !output || value < 1 || value > 1000) return NP_ID_MAPPER_REFUSED_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpIdMapperCreateRequest(void) {
    std::lock_guard lock(idMapperMutex);
    const int reqId = static_cast<int>(nextIdMapperRequest++);
    idMapperRequests.insert(reqId);
    return reqId;
}
int APS5_VABI sceNpIdMapperDeleteRequest(int reqId) {
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    std::lock_guard lock(idMapperMutex);
    return idMapperRequests.erase(reqId) ? 0 : SCE_NP_ERROR_REQUEST_NOT_FOUND;
}
int APS5_VABI sceNpIdMapperNpIdToAccountId(int reqId, int userId, const void* input, void* output, std::uint32_t value, std::uint8_t flag, std::uint64_t extra) {
    (void)flag;
    (void)extra;
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    if (userId == USER_SERVICE_USER_ID_INVALID || !input || !output || value < 1 || value > 1000) return NP_ID_MAPPER_REFUSED_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpIdMapperOnlineIdToAccountId(int reqId, int userId, const void* input, void* output, std::uint32_t value, std::uint8_t flag, std::uint64_t extra) {
    (void)flag;
    (void)extra;
    if (reqId <= 0) return NP_ID_MAPPER_REFUSED_REQUEST_ID;
    if (userId == USER_SERVICE_USER_ID_INVALID || !input || !output || value < 1 || value > 1000) return NP_ID_MAPPER_REFUSED_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpInGameMessageAbortHandle(std::int32_t libCtxId, std::int32_t handleId) {
    std::lock_guard lock(inGameMessageMutex);
    InGameMessageContext* context = FindInGameMessageContext(libCtxId);
    if (!context) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    return context->handles.count(handleId) == 1 ? 0 : NP_IN_GAME_MESSAGE_ERROR_HANDLE_NOT_FOUND;
}
int APS5_VABI sceNpInGameMessageCheckCallback(void) {
    return 0;
}
int APS5_VABI sceNpInGameMessageGetMemoryPoolStatistics(std::int32_t libCtxId, void* statistics) {
    if (statistics == nullptr) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(inGameMessageMutex);
    if (!FindInGameMessageContext(libCtxId)) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    std::uint8_t empty[0x20] {};
    if (!GuestCopyOut_nid_no_patch(statistics, empty, sizeof(empty))) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    return 0;
}
int APS5_VABI sceNpInGameMessagePrepareA(std::int32_t libCtxId, std::int32_t handleId, std::int32_t userId, std::uint64_t callbackAddress, void* userdata) {
    (void)userId;
    if (callbackAddress == 0) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(inGameMessageMutex);
    InGameMessageContext* context = FindInGameMessageContext(libCtxId);
    if (!context) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    if (context->handles.count(handleId) != 1) return NP_IN_GAME_MESSAGE_ERROR_HANDLE_NOT_FOUND;
    context->callbacks[handleId] = {callbackAddress, userdata};
    return 0;
}
int APS5_VABI sceNpInGameMessageSendDataA(std::int32_t libCtxId, const void* destination, const void* source, const void* message) {
    if (!destination || !source || !message) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::uint64_t size = 0;
    if (!GuestCopyIn_nid_no_patch(&size, static_cast<const std::uint8_t*>(message) + 0x200, sizeof(size))) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    if (size == 0 || size > 0x200) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(inGameMessageMutex);
    if (!FindInGameMessageContext(libCtxId)) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    return NP_IN_GAME_MESSAGE_ERROR_NOT_CONNECTED;
}
int APS5_VABI sceNpIntGetAppType(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIntGetGamePresenceStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIntGetNpTitleId(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIntGetNpTitleIdSecret(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIntRegisterCheckCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIntRegisterGamePresenceCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpIsPlusMember(int userId, bool* isMember) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", userId).Ptr("isMember", isMember); });
    if (!isMember) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const bool val = SignedInUser(userId).has_value();
    if (!CopyGuestOut(isMember, &val, sizeof(val))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Bool("is_member", val); });
}
int APS5_VABI sceNpManagerIntAbortRequest(int reqId) {
    std::lock_guard lock(managerIntMutex);
    return managerIntRequests.count(reqId) ? 0 : SCE_NP_ERROR_REQUEST_NOT_FOUND;
}
int APS5_VABI sceNpManagerIntAddActiveSigninStateCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntAddOnlineIdChangeCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntAddPlusMemberTypeCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntAddSigninStateCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntAuthGetAuthorizationCode(int reqId, int userId, const void* parameter, const void* optionalParameter, std::uint32_t firstValue, std::uint32_t secondValue, std::uint8_t flag, void* output) {
    (void)reqId;
    (void)optionalParameter;
    (void)flag;
    if (userId == USER_SERVICE_USER_ID_INVALID || !parameter || !output || firstValue > 3 || secondValue < 1 || secondValue > 3) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntAuthGetIdToken(int reqId, int userId, const void* firstParameter, const void* secondParameter, const void* thirdParameter, std::uint64_t value, void* output) {
    (void)reqId;
    (void)value;
    if (userId == USER_SERVICE_USER_ID_INVALID || !firstParameter || !secondParameter || !thirdParameter || !output) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntCheckNpAvailability(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCheckNpAvailabilityByPid(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCheckNpState(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCheckNpStateA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntClearGameAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntClearOnlineIdChangeFlag(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntClearTicket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntClearUsedFlag(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntClearVshAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCreateAuthenticationTicket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCreateLoginContext(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCreateLoginRequest(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntCreateRequest(void) {
    std::lock_guard lock(managerIntMutex);
    if (managerIntRequests.size() >= NP_MANAGER_INT_REQUEST_SLOTS) return NP_MANAGER_INT_REQUEST_TABLE_FULL;
    const int reqId = static_cast<int>(nextManagerIntRequest++);
    if (reqId <= 0) return reqId;
    if (!managerIntRequests.insert(reqId).second) return NP_MANAGER_INT_REQUEST_DUPLICATE;
    return reqId;
}
int APS5_VABI sceNpManagerIntDeleteLoginContext(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntDeleteRequest(int reqId) {
    std::lock_guard lock(managerIntMutex);
    return managerIntRequests.erase(reqId) ? 0 : NP_MANAGER_INT_REQUEST_NOT_IN_TABLE;
}
int APS5_VABI sceNpManagerIntGetAccessTokenViaImplicitFlow(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetAccountAge(int reqId, int userId, std::uint8_t* age) {
    (void)reqId;
    if (userId == USER_SERVICE_USER_ID_INVALID || !age) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountCountry(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetAccountCountryA(int userId, void* countryCode) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !countryCode) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountCountrySdk(int userId, void* countryCode) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !countryCode) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountDateOfBirthSdk(int userId, void* dateOfBirth) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !dateOfBirth) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountId(int userId, std::uint64_t* accountId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !accountId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountIdSdk(int userId, std::uint64_t* accountId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !accountId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountLanguage(int userId, const void* accountId, void* language) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !accountId || !language) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountLanguageA(int reqId, int userId, void* language) {
    (void)reqId;
    if (userId == USER_SERVICE_USER_ID_INVALID || !language) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountNpEnv(int userId, void* npEnv) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !npEnv) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAccountType(int userId, std::int32_t* accountType) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !accountType) return SCE_NP_ERROR_INVALID_ARGUMENT;
    constexpr std::int32_t val = 0;
    if (!CopyGuestOut(accountType, &val, sizeof(val))) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetActiveSigninState(int userId, void* state) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !state) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAuthServerErrorFlag(int userId, void* flag) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !flag) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAuthorizationCode(int reqId, int userId, const void* firstParameter, const void* secondParameter, const void* optionalParameter, std::uint32_t mode, std::uint8_t flag, void* optionalOutput, void* output) {
    (void)reqId;
    (void)optionalParameter;
    (void)flag;
    (void)optionalOutput;
    if (userId == USER_SERVICE_USER_ID_INVALID || !firstParameter || !secondParameter || !output) return SCE_NP_ERROR_INVALID_ARGUMENT;
    if (mode != 0 && mode != 3 && mode != 5) return SCE_NP_ERROR_INVALID_PLATFORM_TYPE;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetAuthorizationCodeWithPsnoUri(int reqId, int userId, const char* uri, std::uint32_t mode, void* output, std::size_t size) {
    (void)reqId;
    if (userId == USER_SERVICE_USER_ID_INVALID || !uri || !output) return SCE_NP_ERROR_INVALID_ARGUMENT;
    if (size < 1 || size > 0x801) return SCE_NP_ERROR_INVALID_SIZE;
    if (mode != 0 && mode != 3 && mode != 5) return SCE_NP_ERROR_INVALID_PLATFORM_TYPE;
    std::string copiedUri;
    const int savedErrno = errno;
    const int copyResult = CopyGuestString_nid_no_patch(uri, 0x2000, copiedUri);
    errno = savedErrno;
    if (copyResult == 63 || copyResult == 12) return SCE_NP_ERROR_OUT_OF_MEMORY;
    if (copyResult != 0) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetClientCredentialAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetCommunicationRestrictionStatus(int userId, int unknown, void* status) {
    (void)userId;
    if (unknown == -1 || !status) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetGameAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetIssuerId(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetNpEnv(void* npEnv) {
    if (!npEnv) return SCE_NP_ERROR_INVALID_ARGUMENT;
    constexpr std::array<std::uint8_t, 0x18> cleared{};
    if (!CopyGuestOut(npEnv, cleared.data(), cleared.size())) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetNpId(int userId, NpId* npId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !npId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetNpIdByOnlineId(const NpOnlineId* onlineId, NpId* npId) {
    if (!onlineId || !npId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetNpIdSdk(int userId, NpId* npId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !npId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetOfflineAccountId(int userId, void* accountId, void* flag) {
    (void)accountId;
    (void)flag;
    if (userId == USER_SERVICE_USER_ID_INVALID) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetOnlineId(int userId, NpOnlineId* onlineId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !onlineId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetOnlineIdChangeFlag(int userId, void* flag) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !flag) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetOnlineIdSdk(int userId, NpOnlineId* onlineId) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !onlineId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetParentalControlFlag(int userId, void* flag) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !flag) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetParentalControlInfo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetPlusMemberType(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetPlusMemberTypeNB(int userId, void* memberType) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !memberType) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetServerError(int userId, void* error) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !error) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetSigninState(int userId, void* state) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !state) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetSigninTelemetryInfo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetTicket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetTicketA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetTitleToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetTitleTokenWithCheck(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetUserIdByAccountId(std::uint64_t accountId, int* userId) {
    if (accountId == 0 || !userId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetOnlineIdByAccountId(std::uint64_t accountId, NpOnlineId* onlineId) {
    if (accountId == 0 || !onlineId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetUserIdByNpId(const NpId* npId, int* userId) {
    if (!npId || !userId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetUserIdByOnlineId(const NpOnlineId* onlineId, int* userId) {
    if (!onlineId || !userId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetUserIdByOnlineIdSdk(const NpOnlineId* onlineId, int* userId) {
    if (!onlineId || !userId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetUserList(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetUserNum(int userId, void* userNum) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !userNum) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntGetVshAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetVshAccessTokenWithCheck(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntGetVshClientId(void* clientId) {
    if (!clientId) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntIsSubAccount(int userId, void* isSubAccount) {
    if (userId == USER_SERVICE_USER_ID_INVALID || !isSubAccount) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
int APS5_VABI sceNpManagerIntIsTemporarySignout(int userId, void* isTemporarySignout) {
    (void)userId;
    if (!isTemporarySignout) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SCE_NP_ERROR_SIGNED_OUT;
}
bool APS5_VABI sceNpManagerIntIsUnregisteredClientError(int error) {
    return static_cast<std::uint32_t>(error) == 0x82e0104d;
}
int APS5_VABI sceNpManagerIntLoginAuthenticate(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntLoginBind(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntLoginCreateAuthenticationTicket(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNpManagerIntLoginGetAccessToken(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpAbortRequest(int req_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)); });
    std::lock_guard lock(requestMutex);
    return call.Return(liveRequests.count(req_id) ? 0 : SCE_NP_ERROR_REQUEST_NOT_FOUND);
}

int APS5_VABI sceNpCheckCallback(void) {
    Online::Call call("libSceNpManager", __func__);
    const auto account = Online::CurrentAccount();
    const bool signedIn = account && account->account.signedIn;
    NpId npId{};
    if (signedIn) FillOnlineId(npId.online_id, account->account.onlineId);
    const auto state = signedIn ? NP_STATE_SIGNED_IN : NP_STATE_SIGNED_OUT;
    std::array<StateCallbackA, NP_STATE_CALLBACK_MAX> callbacksA;
    StateCallback legacy;
    ToolkitStateCallback toolkit;
    bool accountChanged = false;
    {
        std::lock_guard lock(stateMutex);
        if (account && account->generation != seenAccountGeneration) {
            seenAccountGeneration = account->generation;
            accountChanged = true;
            for (auto& entry : stateCallbacksA) entry.pending = entry.callback != nullptr;
            stateCallback.pending = stateCallback.callback != nullptr;
            toolkitStateCallback.pending = toolkitStateCallback.callback != nullptr;
        }
        callbacksA = stateCallbacksA;
        legacy = stateCallback;
        toolkit = toolkitStateCallback;
        for (auto& entry : stateCallbacksA) entry.pending = false;
        stateCallback.pending = false;
        toolkitStateCallback.pending = false;
    }
    if (legacy.pending) legacy.callback(USER_SERVICE_INITIAL_USER_ID, state, signedIn ? &npId : nullptr, legacy.userdata);
    for (const auto& entry : callbacksA) {
        if (entry.pending) entry.callback(USER_SERVICE_INITIAL_USER_ID, state, entry.userdata);
    }
    if (toolkit.pending && toolkit.callback) toolkit.callback(USER_SERVICE_INITIAL_USER_ID, state, toolkit.userdata);
    NpReachabilityStateCallback reachability = nullptr;
    void* reachabilityArgument = nullptr;
    {
        std::lock_guard lock(reachabilityMutex);
        if (accountChanged && reachabilityCallback) reachabilityPending = true;
        if (reachabilityPending) {
            reachability = reachabilityCallback;
            reachabilityArgument = reachabilityUserdata;
            reachabilityPending = false;
        }
    }
    if (reachability) reachability(USER_SERVICE_INITIAL_USER_ID, signedIn ? NP_REACHABILITY_STATE_REACHABLE : NP_REACHABILITY_STATE_UNAVAILABLE, reachabilityArgument);
    // Web API push events (session news from the launcher) reach the game here, on its thread.
    if (Online::Enabled()) OnlineDispatchPush_nid_no_patch();
    return call.Return(0);
}

int APS5_VABI sceNpCheckNpAvailability(std::int32_t requestId, const NpOnlineId* onlineId, std::uint8_t* available) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("requestId", static_cast<std::int64_t>(requestId)).Ptr("onlineId", onlineId).Ptr("available", available); });
 if (requestId == 0 || onlineId == nullptr) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
 const std::uint8_t unavailable = 0;
 if (available != nullptr && !CopyGuestOut(available, &unavailable, sizeof(unavailable))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
 return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
}

int APS5_VABI sceNpCheckNpReachability(int req_id, int user_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Int("user_id", static_cast<std::int64_t>(user_id)); });
 (void)req_id;
 (void)user_id;
 return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpCheckPremium(int req_id, const NpCheckPremiumParameter* param, NpCheckPremiumResult* result) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) {
        in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("param", param).Ptr("result", result);
        PlusFields(in, param);
    });
    if (req_id != 0 && param && result && PlusAllowed(param)) {
        const int answer = RequestResult(req_id, 0);
        if (answer == 0) result->opaque[0] = 1;
        return call.Return(answer, [&](Online::Fields& out) { out.Bool("authorized", answer == 0); });
    }
    return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpCreateAsyncRequest(const NpCreateAsyncRequestParameter* param) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("param", param); });
    (void)param;
    return call.Return(AddRequest());
}

int APS5_VABI sceNpCreateRequest(void) {
    Online::Call call("libSceNpManager", __func__);
    return call.Return(AddRequest());
}

int APS5_VABI sceNpDeleteRequest(int req_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)); });
    std::lock_guard lock(requestMutex);
    if (!liveRequests.count(req_id)) return call.Return(SCE_NP_ERROR_REQUEST_NOT_FOUND);
    liveRequests.erase(req_id);
    requestResults.erase(req_id);
    return call.Return(0);
}

int APS5_VABI sceNpGetAccountAge(int req_id, int user_id, uint8_t* age) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("age", age); });
 (void)req_id;
 (void)user_id;
 if (!age) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
 return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpGetAccountCountry(const NpOnlineId* online_id, void* country_code) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("online_id", online_id).Ptr("country_code", country_code); });
    if (!online_id || !country_code) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
}

int APS5_VABI sceNpGetAccountDateOfBirth(const NpOnlineId* online_id, void* date_of_birth) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("online_id", online_id).Ptr("date_of_birth", date_of_birth); });
    if (!online_id || !date_of_birth) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
}

int APS5_VABI sceNpGetAccountLanguage(int req_id, const NpOnlineId* online_id, void* language) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("online_id", online_id).Ptr("language", language); });
    (void)req_id;
    if (!online_id || !language) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
}

int APS5_VABI sceNpGetParentalControlInfo(int req_id, const NpOnlineId* online_id, int8_t* age, void* info) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("online_id", online_id).Ptr("age", age).Ptr("info", info); });
    (void)req_id;
    if (!online_id || !age || !info) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
}

int APS5_VABI sceNpGetUserIdByOnlineId(const NpOnlineId* online_id, int* user_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("online_id", online_id).Ptr("user_id", user_id); });
    if (!online_id || !user_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInAccount();
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    if (!SameOnlineId(*online_id, account->onlineId)) return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
    *user_id = USER_SERVICE_INITIAL_USER_ID;
    return call.Return(0, [&](Online::Fields& out) { out.Int("user_id", *user_id); });
}

int APS5_VABI sceNpCheckPlus(int req_id, const void* param, void* result) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) {
        in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("param", param).Ptr("result", result);
        PlusFields(in, param);
    });
    if (req_id == 0 || !param || !result) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    if (PlusAllowed(param)) {
        const int answer = RequestResult(req_id, 0);
        if (answer == 0) *static_cast<std::uint8_t*>(result) = 1;
        return call.Return(answer, [&](Online::Fields& out) { out.Bool("authorized", answer == 0); });
    }
    return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpNotifyPlusFeature(const void* param) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("param", param); });
    if (!SignedInAccount()) NotImplemented_nid_no_patch(__func__);
    return call.Return(0);
}

int APS5_VABI sceNpGetAccountId(const NpOnlineId* online_id, uint64_t* account_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("online_id", online_id).Ptr("account_id", account_id); });
    if (!online_id || !account_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    NpOnlineId localId{};
    const auto preserved = errno;
    const bool copied = GuestCopyIn_nid_no_patch(&localId, online_id, sizeof(localId));
    errno = preserved;
    if (!copied) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInAccount();
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    if (!SameOnlineId(localId, account->onlineId)) return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
    const std::uint64_t value = account->accountId;
    if (!CopyGuestOut(account_id, &value, sizeof(value))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Uint("account_id", value); });
}

int APS5_VABI sceNpSetGamePresenceOnline(int req_id, const NpOnlineId* online_id, uint32_t presence) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("online_id", online_id).Uint("presence", static_cast<std::uint64_t>(presence)); });
    (void)presence;
    if (req_id == 0 || !online_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    {
        std::lock_guard lock(requestMutex);
        if (!liveRequests.count(req_id)) return call.Return(SCE_NP_ERROR_REQUEST_NOT_FOUND);
    }
    return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpSetGamePresenceOnlineA(int reqId, int userId, uint32_t presence) {
    (void)presence;
    if (userId == USER_SERVICE_USER_ID_INVALID) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return SignedOutRequest(reqId);
}

int APS5_VABI sceNpGetAccountCountryA(int user_id, void* country_code) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("country_code", country_code); });
    if (!country_code) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    UserServiceRegisteredUserIdList users{};
    if (user_id != USER_SERVICE_USER_ID_INVALID && sceUserServiceGetRegisteredUserIdList(&users) == USER_SERVICE_OK &&
        std::find(std::begin(users.user_id), std::end(users.user_id), user_id) == std::end(users.user_id))
        return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
    const auto account = SignedInUser(user_id);
    if (!account || account->country.size() != 2) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    char code[4]{};
    std::memcpy(code, account->country.data(), 2);
    if (!CopyGuestOut(country_code, code, sizeof(code))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Text("country_code", account->country); });
}

int APS5_VABI sceNpGetAccountIdA(int user_id, uint64_t* account_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("account_id", account_id); });
    if (user_id == USER_SERVICE_USER_ID_INVALID || !account_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInUser(user_id);
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    const std::uint64_t value = account->accountId;
    if (!CopyGuestOut(account_id, &value, sizeof(value))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Uint("account_id", value); });
}

int APS5_VABI sceNpGetNpId(int user_id, NpId* np_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("np_id", np_id); });
    if (user_id == USER_SERVICE_USER_ID_INVALID || !np_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInUser(user_id);
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    NpId value{};
    FillOnlineId(value.online_id, account->onlineId);
    if (!CopyGuestOut(np_id, &value, sizeof(value))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Text("online_id", account->onlineId); });
}

int APS5_VABI sceNpGetNpReachabilityState(int user_id, uint32_t* state) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("state", state); });
    if (!state) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const uint32_t val = SignedInUser(user_id) ? NP_REACHABILITY_STATE_REACHABLE : NP_REACHABILITY_STATE_UNAVAILABLE;
    if (!CopyGuestOut(state, &val, sizeof(val))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Uint("state", val); });
}

int APS5_VABI sceNpGetOnlineId(int user_id, NpOnlineId* online_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("online_id", online_id); });
    if (user_id == USER_SERVICE_USER_ID_INVALID || !online_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInUser(user_id);
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    NpOnlineId value{};
    FillOnlineId(value, account->onlineId);
    if (!CopyGuestOut(online_id, &value, sizeof(value))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Text("online_id", account->onlineId); });
}

int APS5_VABI sceNpGetState(int user_id, uint32_t* state) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("state", state); });
    if (!state) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const uint32_t localState = SignedInUser(user_id) ? NP_STATE_SIGNED_IN : NP_STATE_SIGNED_OUT;
    if (!CopyGuestOut(state, &localState, sizeof(localState))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Uint("state", localState); });
}

int APS5_VABI sceNpHasSignedUp(int user_id, bool* has_signed_up) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("has_signed_up", has_signed_up); });
    if (!has_signed_up) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const bool localSignedUp = SignedInUser(user_id).has_value();
    if (!CopyGuestOut(has_signed_up, &localSignedUp, sizeof(localSignedUp))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0, [&](Online::Fields& out) { out.Bool("has_signed_up", localSignedUp); });
}

int APS5_VABI sceNpPollAsync(int req_id, int* result) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Ptr("result", result); });
    if (!result) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    int value = SCE_NP_ERROR_SIGNED_OUT;
    {
        std::lock_guard lock(requestMutex);
        if (!liveRequests.count(req_id)) return call.Return(SCE_NP_ERROR_REQUEST_NOT_FOUND);
        const auto found = requestResults.find(req_id);
        if (found != requestResults.end()) value = found->second;
    }
    if (!CopyGuestOut(result, &value, sizeof(value))) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(NP_POLL_ASYNC_FINISHED, [&](Online::Fields& out) { out.Int("result", value); });
}

int APS5_VABI sceNpWaitAsync(int req_id, int* result) {
    if (!result) return SCE_NP_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(requestMutex);
    if (!liveRequests.count(req_id)) return SCE_NP_ERROR_REQUEST_NOT_FOUND;
    constexpr int val = SCE_NP_ERROR_SIGNED_OUT;
    if (!CopyGuestOut(result, &val, sizeof(val))) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return 0;
}

void APS5_VABI sceNpRegisterGamePresenceCallback(void* callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("callback", callback).Ptr("userdata", userdata); });
    (void)callback;
    (void)userdata;
}

int APS5_VABI sceNpRegisterGamePresenceCallbackA(void* callback, void* userdata) {
    if (!callback) return SCE_NP_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(gamePresenceMutex);
    for (auto& entry : gamePresenceCallbacksA) {
        if (entry.inUse) continue;
        entry.handle = ++nextGamePresenceHandle;
        entry.callback = callback;
        entry.userdata = userdata;
        entry.inUse = true;
        return entry.handle;
    }
    return SCE_NP_ERROR_CALLBACK_MAX;
}

int APS5_VABI sceNpUnregisterGamePresenceCallbackA(int callbackId) {
    std::lock_guard lock(gamePresenceMutex);
    for (auto& entry : gamePresenceCallbacksA) {
        if (entry.inUse && entry.handle == callbackId) {
            entry = {};
            return 0;
        }
    }
    return SCE_NP_ERROR_CALLBACK_NOT_REGISTERED;
}

int APS5_VABI sceNpRegisterNpReachabilityStateCallback(void* callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("callback", callback).Ptr("userdata", userdata); });
    if (!callback) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    std::lock_guard lock(reachabilityMutex);
    if (reachabilityCallback) return call.Return(SCE_NP_ERROR_CALLBACK_ALREADY_REGISTERED);
    reachabilityCallback = reinterpret_cast<NpReachabilityStateCallback>(callback);
    reachabilityUserdata = userdata;
    reachabilityPending = true;
    return call.Return(0);
}

int APS5_VABI sceNpUnregisterNpReachabilityStateCallback(void) {
    Online::Call call("libSceNpManager", __func__);
    std::lock_guard lock(reachabilityMutex);
    if (!reachabilityCallback) return call.Return(SCE_NP_ERROR_CALLBACK_NOT_REGISTERED);
    reachabilityCallback = nullptr;
    reachabilityUserdata = nullptr;
    reachabilityPending = false;
    return call.Return(0);
}

int APS5_VABI sceNpRegisterPlusEventCallback(void* callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("callback", callback).Ptr("userdata", userdata); });
    (void)userdata;
    if (!callback) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}

int APS5_VABI sceNpRegisterPremiumEventCallback(void* callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("callback", callback).Ptr("userdata", userdata); });
    (void)userdata;
    if (!callback) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}

int APS5_VABI sceNpRegisterStateCallback(NpStateCallback callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("userdata", userdata); });
    if (!callback) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    std::lock_guard lock(stateMutex);
    if (stateCallback.callback) return call.Return(SCE_NP_ERROR_CALLBACK_ALREADY_REGISTERED);
    stateCallback = {callback, userdata, true};
    return call.Return(0);
}

int APS5_VABI sceNpSetContentRestriction(const NpContentRestriction* restriction) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("restriction", restriction); });
    struct Fields {
        std::uint64_t size;
        std::int8_t defaultAgeRestriction;
        std::uint8_t padding[3];
        std::int32_t ageRestrictionCount;
        const void* ageRestrictions;
    };
    if (!restriction) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto* fields = reinterpret_cast<const Fields*>(restriction);
    if (fields->size != sizeof(Fields)) return call.Return(SCE_NP_ERROR_INVALID_SIZE);
    if (fields->defaultAgeRestriction < 0 || fields->ageRestrictionCount < 0 || fields->ageRestrictionCount > 0x100) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    if (fields->ageRestrictionCount > 0 && !fields->ageRestrictions) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}

int APS5_VABI sceNpSetNpTitleId(const NpTitleId* title_id, const NpTitleSecret* title_secret) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Str("title_id", title_id ? title_id->data : nullptr, sizeof(title_id->data)).Ptr("title_secret", title_secret); });
    (void)title_id;
    (void)title_secret;
    return call.Return(0);
}

int APS5_VABI sceNpSetTimeout(int reqId, int32_t resolveRetry, uint32_t resolveTimeout, uint32_t connTimeout,
    uint32_t sendTimeout, uint32_t recvTimeout) {
    constexpr uint32_t minResolveTimeout = 1000000;
    constexpr uint32_t minTransferTimeout = 10000000;
    auto belowMinimum = [](uint32_t timeout, uint32_t minimum) { return timeout != 0 && timeout < minimum; };
    if (reqId <= 0 || resolveRetry < 0) return SCE_NP_ERROR_INVALID_ARGUMENT;
    if (resolveRetry == 0 && resolveTimeout == 0 && connTimeout == 0 && sendTimeout == 0 && recvTimeout == 0) {
        return SCE_NP_ERROR_INVALID_ARGUMENT;
    }
    if (belowMinimum(resolveTimeout, minResolveTimeout) || belowMinimum(connTimeout, minTransferTimeout) ||
        belowMinimum(sendTimeout, minTransferTimeout) || belowMinimum(recvTimeout, minTransferTimeout)) {
        return SCE_NP_ERROR_INVALID_ARGUMENT;
    }
    std::lock_guard lock(requestMutex);
    return liveRequests.count(reqId) ? 0 : SCE_NP_ERROR_REQUEST_NOT_FOUND;
}

int APS5_VABI sceNpUnregisterStateCallback(void) {
    Online::Call call("libSceNpManager", __func__);
    std::lock_guard lock(stateMutex);
    if (!stateCallback.callback) return call.Return(SCE_NP_ERROR_CALLBACK_NOT_REGISTERED);
    stateCallback = {};
    return call.Return(0);
}

int APS5_VABI sceNpRegisterStateCallbackForToolkit(NpStateCallbackForToolkit callback, void* userdata) {
    std::lock_guard lock(stateMutex);
    toolkitStateCallback = {callback, userdata, true};
    return 0;
}

int APS5_VABI sceNpUnregisterStateCallbackForToolkit(void) {
    std::lock_guard lock(stateMutex);
    if (!toolkitStateCallback.callback) return SCE_NP_ERROR_CALLBACK_NOT_REGISTERED;
    toolkitStateCallback = {};
    return 0;
}

int APS5_VABI sceNpGetAccountLanguage2(int req_id, int user_id, void* language) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("req_id", static_cast<std::int64_t>(req_id)).Int("user_id", static_cast<std::int64_t>(user_id)).Ptr("language", language); });
    (void)req_id;
    (void)user_id;
    (void)language;
    return call.Return(SCE_NP_ERROR_SIGNED_OUT);
}

int APS5_VABI sceNpNotifyPremiumFeature(const void* param) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("param", param); });
    (void)param;
    return call.Return(0);
}

int APS5_VABI sceNpRegisterStateCallbackA(NpStateCallbackA callback, void* userdata) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("userdata", userdata); });
    if (!callback) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    std::lock_guard lock(stateMutex);
    for (const auto& entry : stateCallbacksA) {
        if (entry.callback == callback) return call.Return(SCE_NP_ERROR_CALLBACK_ALREADY_REGISTERED);
    }
    for (int index = 0; index < NP_STATE_CALLBACK_MAX; ++index) {
        if (stateCallbacksA[index].callback) continue;
        stateCallbacksA[index] = {callback, userdata, true};
        return call.Return(index + 1);
    }
    return call.Return(SCE_NP_ERROR_CALLBACK_MAX);
}

int APS5_VABI sceNpUnregisterStateCallbackA(int callbackId) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Int("callbackId", static_cast<std::int64_t>(callbackId)); });
    if (static_cast<uint32_t>(callbackId) - 1u >= static_cast<uint32_t>(NP_STATE_CALLBACK_MAX)) return call.Return(SCE_NP_ERROR_INVALID_ID);
    std::lock_guard lock(stateMutex);
    auto& entry = stateCallbacksA[callbackId - 1];
    if (!entry.callback) return call.Return(SCE_NP_ERROR_CALLBACK_NOT_REGISTERED);
    entry = {};
    return call.Return(0);
}

int APS5_VABI sceNpUnregisterPremiumEventCallback(void) {
    Online::Call call("libSceNpManager", __func__);
    return call.Return(0);
}

int APS5_VABI sceNpUnregisterPlusEventCallback(void) {
    Online::Call call("libSceNpManager", __func__);
    return call.Return(0);
}

int APS5_VABI sceNpGetUserIdByAccountId(uint64_t account_id, int* user_id) {
    Online::Call call("libSceNpManager", __func__);
    call.Args([&](Online::Fields& in) { in.Uint("account_id", static_cast<std::uint64_t>(account_id)).Ptr("user_id", user_id); });
    if (account_id == 0 || !user_id) return call.Return(SCE_NP_ERROR_INVALID_ARGUMENT);
    const auto account = SignedInAccount();
    if (!account) return call.Return(SCE_NP_ERROR_SIGNED_OUT);
    if (account->accountId != account_id) return call.Return(SCE_NP_ERROR_USER_NOT_FOUND);
    *user_id = USER_SERVICE_INITIAL_USER_ID;
    return call.Return(0, [&](Online::Fields& out) { out.Int("user_id", *user_id); });
}

int APS5_VABI sceNpGetSandboxInfo(void* sandbox_info) {
    if (!sandbox_info) return SCE_NP_ERROR_INVALID_ARGUMENT;
    static constexpr char Platform[] = "RETAIL";
    static constexpr char Environment[] = "LIVE";
    std::array<char, 0x50> localInfo{};
    std::memcpy(localInfo.data(), Platform, sizeof(Platform));
    std::memcpy(localInfo.data() + 0x28, Environment, sizeof(Environment));
    const int savedErrno = errno;
    const bool copied = GuestCopyOut_nid_no_patch(sandbox_info, localInfo.data(), localInfo.size());
    errno = savedErrno;
    if (!copied) return SCE_NP_ERROR_INVALID_ARGUMENT;
    return 0;
}

APS5_EXPORT("8weiQyIdI3A", sceNpUnknown_8weiQyIdI3A);
int APS5_VABI sceNpUnknown_8weiQyIdI3A(int userId, const NpOnlineId* buffer) {
    (void)userId;
    (void)buffer;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

APS5_EXPORT("WxLcN76q19o", sceNpUnknown_WxLcN76q19o);
int APS5_VABI sceNpUnknown_WxLcN76q19o(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpCheckCallbackForLib() {
    Online::Call call("libSceNpManager", __func__);
    return call.Return(sceNpCheckCallback());
}

}

extern "C" {

int APS5_VABI sceNpInGameMessageCreateHandle(std::int32_t libCtxId) {
    std::lock_guard lock(inGameMessageMutex);
    InGameMessageContext* context = FindInGameMessageContext(libCtxId);
    if (!context) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    const std::int32_t handleId = TakeInGameMessageId(nextInGameMessageHandle, __func__);
    context->handles.insert(handleId);
    return handleId;
}

int APS5_VABI sceNpInGameMessageDeleteHandle(std::int32_t libCtxId, std::int32_t handleId) {
    std::lock_guard lock(inGameMessageMutex);
    InGameMessageContext* context = FindInGameMessageContext(libCtxId);
    if (!context) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    context->callbacks.erase(handleId);
    return context->handles.erase(handleId) == 1 ? 0 : NP_IN_GAME_MESSAGE_ERROR_HANDLE_NOT_FOUND;
}

int APS5_VABI sceNpInGameMessageInitialize(std::size_t poolSize, void* option) {
    (void)poolSize;
    (void)option;
    std::lock_guard lock(inGameMessageMutex);
    const std::int32_t libCtxId = TakeInGameMessageId(nextInGameMessageContext, __func__);
    inGameMessageContexts.emplace(libCtxId, InGameMessageContext{});
    return libCtxId;
}

int APS5_VABI sceNpInGameMessagePrepare(std::int32_t libCtxId, std::int32_t handleId, std::int32_t userId, std::uint64_t callbackAddress, void* userdata) {
    (void)userId;
    if (callbackAddress == 0) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(inGameMessageMutex);
    InGameMessageContext* context = FindInGameMessageContext(libCtxId);
    if (!context) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    if (context->handles.count(handleId) != 1) return NP_IN_GAME_MESSAGE_ERROR_HANDLE_NOT_FOUND;
    context->callbacks[handleId] = {callbackAddress, userdata};
    return 0;
}

int APS5_VABI sceNpInGameMessageSendData(std::int32_t libCtxId, const void* destination, const void* source, const void* message) {
    if (!destination || !source || !message) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::uint64_t size = 0;
    if (!GuestCopyIn_nid_no_patch(&size, static_cast<const std::uint8_t*>(message) + 0x80, sizeof(size))) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    if (size == 0 || size > 0x200) return NP_IN_GAME_MESSAGE_ERROR_INVALID_ARGUMENT;
    std::lock_guard lock(inGameMessageMutex);
    if (!FindInGameMessageContext(libCtxId)) return NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
    return NP_IN_GAME_MESSAGE_ERROR_NOT_CONNECTED;
}

int APS5_VABI sceNpInGameMessageTerminate(std::int32_t libCtxId) {
    std::lock_guard lock(inGameMessageMutex);
    return inGameMessageContexts.erase(libCtxId) == 1 ? 0 : NP_IN_GAME_MESSAGE_ERROR_LIB_CONTEXT_NOT_FOUND;
}

int APS5_VABI sceNpSnsFacebookCreateRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpSnsFacebookDeleteRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpSnsFacebookGetAccessToken() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}

extern "C" {

int APS5_VABI npManagerLegacyUnknown_70N4VzVCpQg_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("70N4VzVCpQg", npManagerLegacyUnknown_70N4VzVCpQg_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_SSuF3qPYjgA_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("SSuF3qPYjgA", npManagerLegacyUnknown_SSuF3qPYjgA_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_ZKqJVpTOtW0_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("ZKqJVpTOtW0", npManagerLegacyUnknown_ZKqJVpTOtW0_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_jBLJpaqaV1A_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("jBLJpaqaV1A", npManagerLegacyUnknown_jBLJpaqaV1A_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_mtowPSR0JN8_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("mtowPSR0JN8", npManagerLegacyUnknown_mtowPSR0JN8_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_qp_minus_DvqvPOYM_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("qp-DvqvPOYM", npManagerLegacyUnknown_qp_minus_DvqvPOYM_nid_no_patch);

int APS5_VABI npManagerLegacyUnknown_tmnDjDmI3AI_nid_no_patch() {
    NotImplemented_nid_no_patch(__func__);
}
APS5_EXPORT("tmnDjDmI3AI", npManagerLegacyUnknown_tmnDjDmI3AI_nid_no_patch);

}
