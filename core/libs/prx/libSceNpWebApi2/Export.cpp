#include "prx/libSceNetCtl/include/Online.hpp"
#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <atomic>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <unordered_map>

// The PSN web API has no service behind it: handles can be created, but requests fail.
static constexpr int SCE_NP_WEBAPI2_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80553402);
static constexpr int SCE_NP_WEBAPI2_ERROR_UNAVAILABLE = static_cast<int>(0x80553406);
static constexpr int SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT = static_cast<int>(0x80553404);
static constexpr int SCE_NP_WEBAPI2_ERROR_INVALID_HANDLE = static_cast<int>(0x8055340D);
static std::atomic<int> g_nextHandle{1};

struct NpWebApi2PushContextId {
    char value[37];
};

static_assert(sizeof(NpWebApi2PushContextId) == 37);

struct NpWebApi2MemoryPoolStats {
    size_t pool_size;
    size_t max_inuse_size;
    size_t current_inuse_size;
    int32_t reserved;
};

static_assert(sizeof(NpWebApi2MemoryPoolStats) == 32);

static std::mutex g_poolsMutex;
static std::unordered_map<int, size_t> g_pools;

static int CreateLibraryContext(size_t poolSize) {
    const int libCtxId = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    std::lock_guard lock(g_poolsMutex);
    g_pools[libCtxId] = poolSize;
    return libCtxId;
}

struct PushHandle {
    std::int32_t libraryContextId;
    std::uint32_t timeout = 0;
    bool aborted = false;
};

static std::unordered_map<int, PushHandle> pushHandles;

extern "C" {

int APS5_VABI sceNpWebApi2AbortRequest(int64_t request_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)); });
    (void)request_id;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2AddHttpRequestHeader(int64_t request_id, const char* field_name, const char* value) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Str("field_name", field_name).Str("value", value); });
    (void)request_id;
    (void)field_name;
    (void)value;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2AddWebTraceTag(std::int64_t requestId, const char* value) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("requestId", static_cast<std::int64_t>(requestId)).Str("value", value); });
    (void)requestId;
    if (!value) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_ARGUMENT);
    return call.Return(0);
}

void APS5_VABI sceNpWebApi2CheckTimeout(void) {
    Online::Call call("libSceNpWebApi2", __func__);
}

int APS5_VABI sceNpWebApi2CreateRequest(int user_context_id, const char* api_group, const char* path, const char* method, const void* content_parameter, int64_t* request_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_context_id", static_cast<std::int64_t>(user_context_id)).Str("api_group", api_group).Str("path", path).Str("method", method).Ptr("content_parameter", content_parameter).Ptr("request_id", request_id); });
    (void)user_context_id;
    (void)api_group;
    (void)path;
    (void)method;
    (void)content_parameter;
    if (!request_id) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_ARGUMENT);
    *request_id = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2CreateUserContext(int lib_ctx_id, int user_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("lib_ctx_id", static_cast<std::int64_t>(lib_ctx_id)).Int("user_id", static_cast<std::int64_t>(user_id)); });
    (void)lib_ctx_id;
    (void)user_id;
    return call.Return(g_nextHandle.fetch_add(1, std::memory_order_relaxed));
}

int APS5_VABI sceNpWebApi2DeleteRequest(int64_t request_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)); });
    (void)request_id;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2DeleteUserContext(int user_context_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_context_id", static_cast<std::int64_t>(user_context_id)); });
    (void)user_context_id;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2GetHttpResponseHeaderValue(int64_t request_id, const char* field_name, char* value, size_t value_size) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Str("field_name", field_name).Ptr("value", value).Uint("value_size", static_cast<std::uint64_t>(value_size)); });
    (void)request_id;
    (void)field_name;
    (void)value;
    (void)value_size;
    return call.Return(SCE_NP_WEBAPI2_ERROR_UNAVAILABLE);
}

int APS5_VABI sceNpWebApi2GetHttpResponseHeaderValueLength(int64_t request_id, const char* field_name, size_t* value_length) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Str("field_name", field_name).Ptr("value_length", value_length); });
    (void)request_id;
    (void)field_name;
    (void)value_length;
    return call.Return(SCE_NP_WEBAPI2_ERROR_UNAVAILABLE);
}

int APS5_VABI sceNpWebApi2Initialize(int lib_http_ctx_id, size_t pool_size) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("lib_http_ctx_id", static_cast<std::int64_t>(lib_http_ctx_id)).Uint("pool_size", static_cast<std::uint64_t>(pool_size)); });
    (void)lib_http_ctx_id;
    return call.Return(CreateLibraryContext(pool_size));
}

int APS5_VABI sceNpWebApi2GetMemoryPoolStats(int libraryContextId, NpWebApi2MemoryPoolStats* stats) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)).Ptr("stats", stats); });
    std::lock_guard lock(g_poolsMutex);
    const auto pool = g_pools.find(libraryContextId);
    if (pool == g_pools.end()) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT);
    if (!stats) return call.Return(0);
    std::memset(stats, 0, sizeof(*stats));
    stats->pool_size = pool->second;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventCreateFilter(int lib_ctx_id, int handle_id, const char* np_service_name, uint32_t np_service_label, const void* filter_param, size_t filter_param_num) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("lib_ctx_id", static_cast<std::int64_t>(lib_ctx_id)).Int("handle_id", static_cast<std::int64_t>(handle_id)).Str("np_service_name", np_service_name).Uint("np_service_label", static_cast<std::uint64_t>(np_service_label)).Ptr("filter_param", filter_param).Uint("filter_param_num", static_cast<std::uint64_t>(filter_param_num)); });
    (void)lib_ctx_id;
    (void)handle_id;
    (void)np_service_name;
    (void)np_service_label;
    (void)filter_param;
    (void)filter_param_num;
    return call.Return(g_nextHandle.fetch_add(1, std::memory_order_relaxed));
}

int APS5_VABI sceNpWebApi2PushEventCreateHandle(int libraryContextId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)); });
    std::lock_guard lock(g_poolsMutex);
    if (!g_pools.contains(libraryContextId)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT);
    const int handleId = g_nextHandle.fetch_add(1, std::memory_order_relaxed);
    pushHandles.emplace(handleId, PushHandle{libraryContextId});
    return call.Return(handleId);
}

int APS5_VABI sceNpWebApi2PushEventAbortHandle(int libraryContextId, int handleId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)).Int("handleId", static_cast<std::int64_t>(handleId)); });
    std::lock_guard lock(g_poolsMutex);
    if (!g_pools.contains(libraryContextId)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT);
    const auto handle = pushHandles.find(handleId);
    if (handle == pushHandles.end() || handle->second.libraryContextId != libraryContextId) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_HANDLE);
    handle->second.aborted = true;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventDeleteHandle(int libraryContextId, int handleId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)).Int("handleId", static_cast<std::int64_t>(handleId)); });
    std::lock_guard lock(g_poolsMutex);
    if (!g_pools.contains(libraryContextId)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT);
    const auto handle = pushHandles.find(handleId);
    if (handle == pushHandles.end() || handle->second.libraryContextId != libraryContextId) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_HANDLE);
    pushHandles.erase(handle);
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventDeletePushContext(int user_context_id, const void* push_context_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_context_id", static_cast<std::int64_t>(user_context_id)).Ptr("push_context_id", push_context_id); });
    (void)user_context_id;
    (void)push_context_id;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventRegisterCallback(int user_context_id, int filter_id, void* callback, void* user_arg) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("user_context_id", static_cast<std::int64_t>(user_context_id)).Int("filter_id", static_cast<std::int64_t>(filter_id)).Ptr("callback", callback).Ptr("user_arg", user_arg); });
    (void)user_context_id;
    (void)filter_id;
    (void)callback;
    (void)user_arg;
    return call.Return(g_nextHandle.fetch_add(1, std::memory_order_relaxed));
}

int APS5_VABI sceNpWebApi2ReadData(int64_t request_id, void* data, size_t size) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Ptr("data", data).Uint("size", static_cast<std::uint64_t>(size)); });
    (void)request_id;
    (void)data;
    (void)size;
    return call.Return(SCE_NP_WEBAPI2_ERROR_UNAVAILABLE);
}

int APS5_VABI sceNpWebApi2SendRequest(int64_t request_id, const void* data, size_t data_size, NpWebApi2ResponseInformationOption* response_info_option) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Data("data", data, data_size).Uint("data_size", static_cast<std::uint64_t>(data_size)).Ptr("response_info_option", response_info_option); });
    (void)request_id;
    (void)data;
    (void)data_size;
    (void)response_info_option;
    return call.Return(SCE_NP_WEBAPI2_ERROR_UNAVAILABLE);
}

int APS5_VABI sceNpWebApi2Terminate(int lib_ctx_id) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("lib_ctx_id", static_cast<std::int64_t>(lib_ctx_id)); });
    std::lock_guard lock(g_poolsMutex);
    std::erase_if(pushHandles, [lib_ctx_id](const auto& item) { return item.second.libraryContextId == lib_ctx_id; });
    g_pools.erase(lib_ctx_id);
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventCreatePushContext(std::int32_t userContextId, NpWebApi2PushContextId* pushContextId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userContextId", static_cast<std::int64_t>(userContextId)).Ptr("pushContextId", pushContextId); });
    return call.Return(SCE_NP_WEBAPI2_ERROR_UNAVAILABLE);
}

int APS5_VABI sceNpWebApi2PushEventDeleteFilter(std::int32_t libraryContextId, std::int32_t filterId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)).Int("filterId", static_cast<std::int64_t>(filterId)); });
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventSetHandleTimeout(int libraryContextId, int handleId, std::uint32_t timeout) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("libraryContextId", static_cast<std::int64_t>(libraryContextId)).Int("handleId", static_cast<std::int64_t>(handleId)).Uint("timeout", static_cast<std::uint64_t>(timeout)); });
    std::lock_guard lock(g_poolsMutex);
    if (!g_pools.contains(libraryContextId)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_CONTEXT);
    const auto handle = pushHandles.find(handleId);
    if (handle == pushHandles.end() || handle->second.libraryContextId != libraryContextId) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_HANDLE);
    handle->second.timeout = timeout;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventRegisterPushContextCallback() {
    Online::Call call("libSceNpWebApi2", __func__);
    return call.Return(g_nextHandle.fetch_add(1, std::memory_order_relaxed));
}

int APS5_VABI sceNpWebApi2PushEventStartPushContextCallback(std::int32_t userContextId, const NpWebApi2PushContextId* pushContextId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userContextId", static_cast<std::int64_t>(userContextId)).Ptr("pushContextId", pushContextId); });
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventUnregisterCallback(std::int32_t userContextId, std::int32_t callbackId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userContextId", static_cast<std::int64_t>(userContextId)).Int("callbackId", static_cast<std::int64_t>(callbackId)); });
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2PushEventUnregisterPushContextCallback(std::int32_t userContextId, std::int32_t callbackId) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("userContextId", static_cast<std::int64_t>(userContextId)).Int("callbackId", static_cast<std::int64_t>(callbackId)); });
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2SetRequestTimeout(int64_t request_id, uint32_t timeout) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("request_id", static_cast<std::int64_t>(request_id)).Uint("timeout", static_cast<std::uint64_t>(timeout)); });
    (void)request_id;
    (void)timeout;
    return call.Return(0);
}

int APS5_VABI sceNpWebApi2AddMultipartPart() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2CreateMultipartRequest(int user_ctx_id, const char* api_group, const char* path, const char* method, int64_t* request_id) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2InitializeForPresence(int lib_http_ctx_id, uint64_t pool_size) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Int("lib_http_ctx_id", static_cast<std::int64_t>(lib_http_ctx_id)).Uint("pool_size", static_cast<std::uint64_t>(pool_size)); });
    (void)lib_http_ctx_id;
    return call.Return(CreateLibraryContext(pool_size));
}

int APS5_VABI sceNpWebApi2IntCreateRequest() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2IntInitialize(const NpWebApi2IntInitializeArgs* args) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("args", args); });
    if (args == nullptr || args->struct_size != sizeof(NpWebApi2IntInitializeArgs)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_ARGUMENT);
    return call.Return(CreateLibraryContext(args->pool_size));
}

int APS5_VABI sceNpWebApi2IntInitialize2(const NpWebApi2IntInitialize2Args* args) {
    Online::Call call("libSceNpWebApi2", __func__);
    call.Args([&](Online::Fields& in) { in.Ptr("args", args); });
    if (args == nullptr || args->struct_size != sizeof(NpWebApi2IntInitialize2Args)) return call.Return(SCE_NP_WEBAPI2_ERROR_INVALID_ARGUMENT);
    return call.Return(CreateLibraryContext(args->pool_size));
}

int APS5_VABI sceNpWebApi2IntPushEventCreateCtxIndFilter() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2IntPushEventCreateDestPs4CtxIndFilter() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2SendMultipartRequest(int64_t request_id, int part_index, void* data, uint64_t data_size, void* resp_info_option) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceNpWebApi2SetMultipartContentType() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
