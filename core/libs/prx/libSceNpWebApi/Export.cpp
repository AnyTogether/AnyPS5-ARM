#include "prx/libSceNetCtl/include/Online.hpp"
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

static constexpr int SCE_NP_WEBAPI_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80552902);
static constexpr int SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND = static_cast<int>(0x80552904);
static constexpr int SCE_NP_WEBAPI_ERROR_PUSH_EVENT_FILTER_NOT_FOUND = static_cast<int>(0x8055290B);
static constexpr int SCE_NP_WEBAPI_ERROR_HANDLE_NOT_FOUND = static_cast<int>(0x8055290D);
static constexpr int SCE_NP_WEBAPI_ERROR_SERVICE_PUSH_EVENT_FILTER_NOT_FOUND = static_cast<int>(0x8055290E);
static constexpr int SCE_NP_WEBAPI_ERROR_SIGNED_IN_USER_NOT_FOUND = static_cast<int>(0x80552910);
static constexpr int SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_MAX = static_cast<int>(0x8055291A);

namespace {

struct LibraryContext {
    int libHttpCtxId;
    std::size_t poolSize;
    std::unordered_set<int> handles;
    std::unordered_set<int> pushEventFilters;
};

std::mutex contextsMutex;
std::unordered_map<int, LibraryContext> contexts;
int lastContext = 0;
int lastObject = 0;

int nextObject() {
    lastObject = lastObject % 0xefffffff + 1;
    return lastObject;
}

}

extern "C" {

int APS5_VABI sceNpWebApiAbortRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiCreateContext() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiCreateHandle(int libCtxId) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)); });
    std::lock_guard lock(contextsMutex);
    const auto context = contexts.find(libCtxId);
    if (context == contexts.end()) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    const auto handle = nextObject();
    context->second.handles.insert(handle);
    return call.Return(handle);
}

int APS5_VABI sceNpWebApiCreatePushEventFilter(int libCtxId, const void* filterParam, std::size_t filterParamNum) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)).Ptr("filterParam", filterParam).Uint("filterParamNum", static_cast<std::uint64_t>(filterParamNum)); });
    if (!filterParam || filterParamNum == 0) return call.Return(SCE_NP_WEBAPI_ERROR_INVALID_ARGUMENT);
    std::lock_guard lock(contextsMutex);
    const auto context = contexts.find(libCtxId);
    if (context == contexts.end()) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    const auto filter = nextObject();
    context->second.pushEventFilters.insert(filter);
    return call.Return(filter);
}

int APS5_VABI sceNpWebApiCreateRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiCreateServicePushEventFilter(int libCtxId, int handleId, const char* npServiceName, std::uint32_t npServiceLabel, const void* filterParam, std::size_t filterParamNum) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)).Int("handleId", static_cast<std::int64_t>(handleId)).Str("npServiceName", npServiceName).Uint("npServiceLabel", static_cast<std::uint64_t>(npServiceLabel)).Ptr("filterParam", filterParam).Uint("filterParamNum", static_cast<std::uint64_t>(filterParamNum)); });
    (void)npServiceLabel;
    if (!npServiceName || !filterParam || filterParamNum == 0) return call.Return(SCE_NP_WEBAPI_ERROR_INVALID_ARGUMENT);
    std::lock_guard lock(contextsMutex);
    const auto context = contexts.find(libCtxId);
    if (context == contexts.end()) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    if (!context->second.handles.contains(handleId)) return call.Return(SCE_NP_WEBAPI_ERROR_HANDLE_NOT_FOUND);
    return call.Return(SCE_NP_WEBAPI_ERROR_SIGNED_IN_USER_NOT_FOUND);
}

int APS5_VABI sceNpWebApiDeleteContext() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiDeleteHandle(int libCtxId, int handleId) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)).Int("handleId", static_cast<std::int64_t>(handleId)); });
    std::lock_guard lock(contextsMutex);
    const auto context = contexts.find(libCtxId);
    if (context == contexts.end()) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    return call.Return(context->second.handles.erase(handleId) != 0 ? 0 : SCE_NP_WEBAPI_ERROR_HANDLE_NOT_FOUND);
}

int APS5_VABI sceNpWebApiDeletePushEventFilter(int libCtxId, int filterId) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)).Int("filterId", static_cast<std::int64_t>(filterId)); });
    std::lock_guard lock(contextsMutex);
    const auto context = contexts.find(libCtxId);
    if (context == contexts.end()) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    return call.Return(context->second.pushEventFilters.erase(filterId) != 0 ? 0 : SCE_NP_WEBAPI_ERROR_PUSH_EVENT_FILTER_NOT_FOUND);
}

int APS5_VABI sceNpWebApiDeleteRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiDeleteServicePushEventFilter(int libCtxId, int filterId) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)).Int("filterId", static_cast<std::int64_t>(filterId)); });
    (void)filterId;
    std::lock_guard lock(contextsMutex);
    if (!contexts.contains(libCtxId)) return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
    return call.Return(SCE_NP_WEBAPI_ERROR_SERVICE_PUSH_EVENT_FILTER_NOT_FOUND);
}

int APS5_VABI sceNpWebApiGetHttpResponseHeaderValue() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiGetHttpResponseHeaderValueLength() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiGetHttpStatusCode() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiInitialize(int libHttpCtxId, std::size_t poolSize) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libHttpCtxId", static_cast<std::int64_t>(libHttpCtxId)).Uint("poolSize", static_cast<std::uint64_t>(poolSize)); });
    std::lock_guard lock(contextsMutex);
    for (int attempt = 0; attempt < 0x7fff; ++attempt) {
        lastContext = lastContext % 0x7fff + 1;
        if (contexts.contains(lastContext)) continue;
        contexts[lastContext] = {libHttpCtxId, poolSize, {}, {}};
        return call.Return(lastContext);
    }
    return call.Return(SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_MAX);
}

int APS5_VABI sceNpWebApiReadData() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiRegisterPushEventCallback() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiRegisterServicePushEventCallback() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiSendRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiTerminate(int libCtxId) {
    Online::Call call("libSceNpWebApi", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libCtxId", static_cast<std::int64_t>(libCtxId)); });
    std::lock_guard lock(contextsMutex);
    return call.Return(contexts.erase(libCtxId) != 0 ? 0 : SCE_NP_WEBAPI_ERROR_LIB_CONTEXT_NOT_FOUND);
}

int APS5_VABI sceNpWebApiUnregisterPushEventCallback() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiUnregisterServicePushEventCallback() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApiUtilityParseNpId() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
