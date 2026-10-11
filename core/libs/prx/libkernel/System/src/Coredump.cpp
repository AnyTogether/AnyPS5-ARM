#include <cstdint>
#include <cstddef>
#include <atomic>
#include <cstdio>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libkernel/KernelErrors.hpp"

// The handler is recorded but never invoked: host crashes are not turned into guest core dumps.
static std::atomic<uint64_t> g_coredumpHandler{0};
static std::atomic<uint64_t> g_coredumpContext{0};

extern "C" {

int APS5_VABI sceCoredumpRegisterCoredumpHandler(uint64_t handler, size_t stack_size, uint64_t context) {
    (void)stack_size;
    g_coredumpHandler.store(handler, std::memory_order_relaxed);
    g_coredumpContext.store(context, std::memory_order_relaxed);
    return 0;
}

int APS5_VABI sceCoredumpUnregisterCoredumpHandler(void) {
    g_coredumpHandler.store(0, std::memory_order_relaxed);
    g_coredumpContext.store(0, std::memory_order_relaxed);
    return 0;
}

int APS5_VABI sceKernelDebugWriteCppExceptionInfo(const void* exception, uint64_t unknown, const char* typeName, const char* what) {
    (void)unknown;
    std::fprintf(stderr, "[coredump] uncaught C++ exception %p of type %s%s%s\n", exception, typeName ? typeName : "(unknown)", what ? ", what(): " : "", what ? what : "");
    return 0;
}


// No core dump is ever written (see above), so attachments are checked and then have nothing to join.
int APS5_VABI sceCoredumpAttachUserFile(uint32_t userValue, const char* path) {
    (void)userValue;
    return path == nullptr ? SCE_KERNEL_ERROR_EINVAL : 0;
}

int APS5_VABI sceCoredumpGetStopInfoGpu_Agc(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceCoredumpAttachMemoryRegionAsUserFile(uint32_t userValue, const void* memory, size_t size, const char* name) {
    (void)userValue;
    (void)size;
    return memory == nullptr || name == nullptr ? SCE_KERNEL_ERROR_EINVAL : 0;
}

int APS5_VABI sceCoredumpSetUserDataType(void) {
    NotImplemented_nid_no_patch("Uxqkdta7wEg");
    return 0;
}

// The text would go into the core dump; it is shown on the host's error output instead.
void APS5_VABI sceCoredumpDebugTextOut(const char* text, int length) {
    if (text == nullptr || length <= 0) return;
    std::fprintf(stderr, "[coredump] %.*s\n", length, text);
}

int APS5_VABI sceCoredumpGetStopInfoCpu(void) {
    NotImplemented_nid_no_patch("kK0DUW1Ukgc");
    return 0;
}

int APS5_VABI sceCoredumpWriteUserString() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceCoredumpAttachUserMemoryFile(uint32_t userValue, const void* memory, size_t size) {
    (void)userValue;
    (void)size;
    return memory == nullptr ? SCE_KERNEL_ERROR_EINVAL : 0;
}

int APS5_VABI sceCoredumpAttachMemoryRegion(uint32_t userValue, const void* memory, size_t size) {
    (void)userValue;
    (void)size;
    return memory == nullptr ? SCE_KERNEL_ERROR_EINVAL : 0;
}
}
