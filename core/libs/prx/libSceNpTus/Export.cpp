#include <cstdint>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

static constexpr int SCE_NP_ERROR_SIGNED_OUT = static_cast<int>(0x80550006);
static constexpr int SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80550704);
static constexpr int SCE_NP_COMMUNITY_ERROR_TOO_MANY_OBJECTS = static_cast<int>(0x80550706);
static constexpr int SCE_NP_COMMUNITY_ERROR_ABORTED = static_cast<int>(0x80550707);
static constexpr int SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT = static_cast<int>(0x8055070C);
static constexpr int SCE_NP_COMMUNITY_ERROR_INVALID_ID = static_cast<int>(0x8055070E);
static constexpr int SCE_NP_COMMUNITY_ERROR_TOO_MANY_SLOTID = static_cast<int>(0x80550718);
static constexpr int POLL_FINISHED = 0;
static constexpr int POLL_RUNNING = 1;
static constexpr std::size_t MAX_TITLE_CONTEXTS = 32;
static constexpr std::size_t MAX_REQUESTS = 256;
static constexpr int MAX_SLOTS = 64;

namespace {
struct Request {
    int titleCtxId = 0;
    bool started = false;
    bool aborted = false;
    int result = 0;
};

std::mutex tusMutex;
std::unordered_set<int> titleContexts;
std::unordered_map<int, Request> requests;
int nextTitleContext = 1;
int nextRequest = 1;

int ValidateSlots(const std::int32_t* slotIds, int arrayLen, const void* option) {
    if (!slotIds) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (arrayLen < 1 || option) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    if (arrayLen > MAX_SLOTS) return SCE_NP_COMMUNITY_ERROR_TOO_MANY_SLOTID;
    for (int index = 0; index < arrayLen; ++index) {
        if (slotIds[index] < 0) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    }
    return 0;
}

int ValidateNonEmptySlots(const std::int32_t* slotIds, int arrayLen, const void* option) {
    if (!slotIds || arrayLen < 1) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    return ValidateSlots(slotIds, arrayLen, option);
}

bool IsEmpty(const NpOnlineId* user) {
    return !user->data[0];
}

int StartOffline(int reqId) {
    std::lock_guard lock(tusMutex);
    const auto request = requests.find(reqId);
    if (request == requests.end()) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    request->second.started = true;
    request->second.result = request->second.aborted ? SCE_NP_COMMUNITY_ERROR_ABORTED : SCE_NP_ERROR_SIGNED_OUT;
    return 0;
}

int WaitOffline(int reqId, int* result) {
    std::lock_guard lock(tusMutex);
    const auto request = requests.find(reqId);
    if (request == requests.end()) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    if (!request->second.started) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    if (result) *result = request->second.result;
    return 0;
}

int Complete(int reqId, int asyncResult) {
    if (asyncResult < 0) return asyncResult;
    int result = 0;
    if (const int error = WaitOffline(reqId, &result)) return error;
    return result;
}
}

extern "C" {

int APS5_VABI sceNpTusCreateNpTitleCtxA(std::uint32_t serviceLabel, int userId) {
    (void)serviceLabel;
    (void)userId;
    std::lock_guard lock(tusMutex);
    if (titleContexts.size() >= MAX_TITLE_CONTEXTS) return SCE_NP_COMMUNITY_ERROR_TOO_MANY_OBJECTS;
    const int contextId = nextTitleContext++;
    titleContexts.insert(contextId);
    return contextId;
}

int APS5_VABI sceNpTusCreateRequest(int titleCtxId) {
    std::lock_guard lock(tusMutex);
    if (!titleContexts.contains(titleCtxId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    if (requests.size() >= MAX_REQUESTS) return SCE_NP_COMMUNITY_ERROR_TOO_MANY_OBJECTS;
    const int reqId = nextRequest++;
    requests.emplace(reqId, Request{titleCtxId});
    return reqId;
}

int APS5_VABI sceNpTusDeleteNpTitleCtx(int titleCtxId) {
    std::lock_guard lock(tusMutex);
    if (!titleContexts.erase(titleCtxId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    std::erase_if(requests, [titleCtxId](const auto& entry) { return entry.second.titleCtxId == titleCtxId; });
    return 0;
}

int APS5_VABI sceNpTusDeleteRequest(int reqId) {
    std::lock_guard lock(tusMutex);
    return requests.erase(reqId) ? 0 : SCE_NP_COMMUNITY_ERROR_INVALID_ID;
}

int APS5_VABI sceNpTusAbortRequest(int reqId) {
    std::lock_guard lock(tusMutex);
    const auto request = requests.find(reqId);
    if (request == requests.end()) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    request->second.aborted = true;
    return 0;
}

int APS5_VABI sceNpTusPollAsync(int reqId, int* result) {
    std::lock_guard lock(tusMutex);
    const auto request = requests.find(reqId);
    if (request == requests.end()) return SCE_NP_COMMUNITY_ERROR_INVALID_ID;
    if (!request->second.started) return POLL_RUNNING;
    if (result) *result = request->second.result;
    return POLL_FINISHED;
}

int APS5_VABI sceNpTusGetMultiSlotVariableAAsync(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)targetAccountId;
    (void)variableArraySize;
    if (!variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusSetMultiSlotVariableAAsync(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, const std::int64_t* variableArray, int arrayLen, void* option) {
    (void)targetAccountId;
    if (!variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusDeleteMultiSlotVariableAAsync(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, int arrayLen, void* option) {
    (void)targetAccountId;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusAddAndGetVariableAAsync(int reqId, std::uint64_t targetAccountId, std::int32_t slotId, std::int64_t inVariable, const std::uint64_t* isLastChangedAuthor, const void* isLastChangedDate, void* outVariable, std::uint64_t outVariableSize, void* option) {
    (void)targetAccountId;
    (void)inVariable;
    (void)isLastChangedAuthor;
    (void)isLastChangedDate;
    (void)outVariableSize;
    if (!outVariable) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (slotId < 0 || option) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusSetThreadParam(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssCreateNpTitleCtx(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssCreateNpTitleCtxA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusCreateTitleCtx(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetTimeout(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusChangeModeForOtherSaveDataOwners(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusWaitAsync(int reqId, int* result) {
    return WaitOffline(reqId, result);
}

int APS5_VABI sceNpTusGetMultiSlotVariableA(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusGetMultiSlotVariableAAsync(reqId, targetAccountId, slotIds, variableArray, variableArraySize, arrayLen, option));
}

int APS5_VABI sceNpTusGetMultiSlotVariableAsync(int reqId, const void* targetNpId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)targetNpId;
    (void)variableArraySize;
    if (!variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusGetMultiSlotVariableVUserAsync(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)variableArraySize;
    if (!targetVirtualUserId || !variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateNonEmptySlots(slotIds, arrayLen, option)) return error;
    if (IsEmpty(targetVirtualUserId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusGetMultiSlotVariableAVUserAsync(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)variableArraySize;
    if (!targetVirtualUserId || !variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    if (IsEmpty(targetVirtualUserId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusGetMultiSlotVariableAVUser(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusGetMultiSlotVariableAVUserAsync(reqId, targetVirtualUserId, slotIds, variableArray, variableArraySize, arrayLen, option));
}

int APS5_VABI sceNpTusGetMultiSlotVariableForCrossSaveAsync(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)targetAccountId;
    (void)variableArraySize;
    if (!variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusGetMultiSlotVariableForCrossSave(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusGetMultiSlotVariableForCrossSaveAsync(reqId, targetAccountId, slotIds, variableArray, variableArraySize, arrayLen, option));
}

int APS5_VABI sceNpTusGetMultiSlotVariableForCrossSaveVUserAsync(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    (void)variableArraySize;
    if (!targetVirtualUserId || !variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    if (IsEmpty(targetVirtualUserId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusGetMultiSlotVariableForCrossSaveVUser(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, void* variableArray, std::uint64_t variableArraySize, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusGetMultiSlotVariableForCrossSaveVUserAsync(reqId, targetVirtualUserId, slotIds, variableArray, variableArraySize, arrayLen, option));
}

int APS5_VABI sceNpTusSetMultiSlotVariableA(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, const std::int64_t* variableArray, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusSetMultiSlotVariableAAsync(reqId, targetAccountId, slotIds, variableArray, arrayLen, option));
}

int APS5_VABI sceNpTusSetMultiSlotVariableAsync(int reqId, const void* targetNpId, const std::int32_t* slotIds, const std::int64_t* variableArray, int arrayLen, void* option) {
    (void)targetNpId;
    if (!variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusSetMultiSlotVariableVUserAsync(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, const std::int64_t* variableArray, int arrayLen, void* option) {
    if (!targetVirtualUserId || !variableArray) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateSlots(slotIds, arrayLen, option)) return error;
    if (IsEmpty(targetVirtualUserId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusDeleteMultiSlotVariableA(int reqId, std::uint64_t targetAccountId, const std::int32_t* slotIds, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusDeleteMultiSlotVariableAAsync(reqId, targetAccountId, slotIds, arrayLen, option));
}

int APS5_VABI sceNpTusDeleteMultiSlotVariableAsync(int reqId, const void* targetNpId, const std::int32_t* slotIds, int arrayLen, void* option) {
    if (!targetNpId) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateNonEmptySlots(slotIds, arrayLen, option)) return error;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusDeleteMultiSlotVariable(int reqId, const void* targetNpId, const std::int32_t* slotIds, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusDeleteMultiSlotVariableAsync(reqId, targetNpId, slotIds, arrayLen, option));
}

int APS5_VABI sceNpTusDeleteMultiSlotVariableVUserAsync(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, int arrayLen, void* option) {
    if (!targetVirtualUserId) return SCE_NP_COMMUNITY_ERROR_INSUFFICIENT_ARGUMENT;
    if (const int error = ValidateNonEmptySlots(slotIds, arrayLen, option)) return error;
    if (IsEmpty(targetVirtualUserId)) return SCE_NP_COMMUNITY_ERROR_INVALID_ARGUMENT;
    return StartOffline(reqId);
}

int APS5_VABI sceNpTusDeleteMultiSlotVariableVUser(int reqId, const NpOnlineId* targetVirtualUserId, const std::int32_t* slotIds, int arrayLen, void* option) {
    return Complete(reqId, sceNpTusDeleteMultiSlotVariableVUserAsync(reqId, targetVirtualUserId, slotIds, arrayLen, option));
}

int APS5_VABI sceNpTusGetMultiUserVariable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariableAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotDataVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotDataAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotDataVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatusAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssGetSmallStorage(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssGetSmallStorageAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssGetStorage(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssGetStorageAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTssGetDataAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusAddAndGetVariableForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiSlotDataStatusForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetDataForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserVariableForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetMultiUserDataStatusForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariableA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariableAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariableForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsVariableForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatusA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatusAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatusForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusGetFriendsDataStatusForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusSetDataAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotDataA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusDeleteMultiSlotDataAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableA(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableAAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableAVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableAVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableForCrossSave(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableForCrossSaveAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableForCrossSaveVUser(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpTusTryAndSetVariableForCrossSaveVUserAsync(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
