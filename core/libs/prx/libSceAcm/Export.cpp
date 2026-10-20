#include <cstdint>
#include <cstddef>
#include <cstring>
#include <atomic>
#include <mutex>
#include <unordered_set>
#include <unordered_map>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int SCE_ACM_ERROR_BAD_CONTEXT = static_cast<int>(0x81940002);
constexpr int SCE_ACM_ERROR_BAD_POINTER = static_cast<int>(0x81940006);

std::mutex g_mutex;
std::unordered_set<AcmContextId> g_contexts;
std::atomic<uint32_t> g_nextId{1};

}

extern "C" {

int APS5_VABI sceAcmBatchStartBuffer(AcmContextId context, const void* batch_commands, size_t batch_size, AcmBatchError* batch_error, AcmBatchId* batch) {
    (void)batch_commands;
    (void)batch_size;
    if (!batch) return SCE_ACM_ERROR_BAD_POINTER;
    if (context == 0) return SCE_ACM_ERROR_BAD_CONTEXT;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_contexts.contains(context)) return SCE_ACM_ERROR_BAD_CONTEXT;
    AcmBatchId id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    while (id == 0) id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    if (batch_error) std::memset(batch_error, 0, sizeof(*batch_error));
    *batch = id;
    return 0;
}

int APS5_VABI sceAcmBatchStartBuffers(AcmContextId context, uint32_t batch_info_count, const AcmBatchInfo* const batch_info[], AcmBatchError* batch_error, AcmBatchId* batch) {
    (void)batch_info_count;
    (void)batch_info;
    if (!batch) return SCE_ACM_ERROR_BAD_POINTER;
    if (context == 0) return SCE_ACM_ERROR_BAD_CONTEXT;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_contexts.contains(context)) return SCE_ACM_ERROR_BAD_CONTEXT;
    AcmBatchId id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    while (id == 0) id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    if (batch_error) std::memset(batch_error, 0, sizeof(*batch_error));
    *batch = id;
    return 0;
}

int APS5_VABI sceAcmBatchWait(AcmContextId context, AcmBatchId batch, uint32_t timeout) {
    (void)batch;
    (void)timeout;
    if (context == 0) return SCE_ACM_ERROR_BAD_CONTEXT;
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_contexts.contains(context)) return SCE_ACM_ERROR_BAD_CONTEXT;
    return 0;
}

int APS5_VABI sceAcmContextCreate(AcmContextId* context) {
    if (!context) return SCE_ACM_ERROR_BAD_POINTER;
    AcmContextId id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    while (id == 0) id = g_nextId.fetch_add(1, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_contexts.insert(id);
    }
    *context = id;
    return 0;
}

int APS5_VABI sceAcmContextDestroy(AcmContextId context) {
    if (context == 0) return SCE_ACM_ERROR_BAD_CONTEXT;
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(context);
    if (it == g_contexts.end()) return SCE_ACM_ERROR_BAD_CONTEXT;
    g_contexts.erase(it);
    return 0;
}

int APS5_VABI sceAcm_ConvReverb_SharedInput(void) {
    return 0;
}

int APS5_VABI sceAcm_FFT(void) {
    return 0;
}

int APS5_VABI sceAcm_Panner(void) {
    return 0;
}

int APS5_VABI sceAcmBatchJobPriority(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAcm_ConvReverb_SharedIr() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceAcm_IFFT() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
