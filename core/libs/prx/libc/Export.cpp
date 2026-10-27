#include "prx/libc/include/Api.hpp"
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include "prx/libc/include/HeapDiagnostics.hpp"

uint32_t Need_sceLibc = 1;

extern "C" {

    int APS5_VABI std_execute_once_nid_postfix(int* flag, int (APS5_VABI *func)(void*, void*, void**), void* arg) {
        return _ZSt13_Execute_onceRSt9once_flagPFiPvS1_PS1_ES1__nid_postfix(flag, func, arg);
    }

    void APS5_VABI LibcHeapGetTraceInfo_nid_postfix(LibcHeapInfo* info) {
        LibcHeapTraceInfo_nid_no_patch(info);
    }

// std::_Atomic_assert(expression, location): Dinkumware's failure report for an atomic operation
// given an invalid memory order. Imported (without call sites) by Cyberpunk 2077 (PPSA04029).
[[noreturn]] void APS5_VABI _ZSt14_Atomic_assertPKcS0__nid_postfix(const char* expression, const char* location) {
    std::fprintf(stderr, "[libc] guest atomic assertion failed: %s (%s)\n", expression ? expression : "?", location ? location : "?");
    std::fflush(stderr);
    std::abort();
}

APS5_EXPORT("H2e8t5ScQGc", libc___cxa_finalize);
void APS5_VABI libc___cxa_finalize(void* dsoHandle) {
    CxaFinalize_nid_no_patch(dsoHandle);
}
}
