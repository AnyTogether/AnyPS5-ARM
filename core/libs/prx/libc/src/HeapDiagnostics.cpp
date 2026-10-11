#include "prx/libc/include/General.hpp"
#include "prx/libc/include/HeapDiagnostics.hpp"
#include "prx/libc/include/specifics/itanium/UnwindAbi.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <stdexcept>

extern "C" {
_Unwind_Reason_Code APS5_VABI _Unwind_Backtrace_nid_postfix(_Unwind_Trace_Fn trace, void* argument);
_Unwind_Ptr APS5_VABI _Unwind_GetIP_nid_postfix(_Unwind_Context* context);
}

namespace {

std::uint64_t mspaceAtomicIdMask = 0;
std::array<std::uint64_t, 64> mstateTable{};

static_assert(sizeof(LibcHeapInfo) == 32);
static_assert(offsetof(LibcHeapInfo, mspace_atomic_id_mask) == 16);
static_assert(offsetof(LibcHeapInfo, mstate_table) == 24);

constexpr unsigned MaxBacktraceFrames = 64;

// Frame 0 is sceLibcInternalBacktraceForGame itself; the trace starts at its caller.
_Unwind_Reason_Code PrintFrame(_Unwind_Context* context, void* argument) {
    auto& frame = *static_cast<unsigned*>(argument);
    if (frame++ == 0) return _URC_NO_REASON;
    std::fprintf(stderr, "[libc]   #%u 0x%llx\n", frame - 2, static_cast<unsigned long long>(_Unwind_GetIP_nid_postfix(context)));
    return frame <= MaxBacktraceFrames ? _URC_NO_REASON : _URC_NORMAL_STOP;
}

}

extern "C" {

void LibcHeapTraceInfo_nid_no_patch(LibcHeapInfo* info) {
    if (info == nullptr)
        throw std::invalid_argument("heap trace info: null output");
    if (info->size != sizeof(LibcHeapInfo))
        throw std::invalid_argument("heap trace info: unsupported structure size");
    info->unknown2 = 0;
    info->mspace_atomic_id_mask = &mspaceAtomicIdMask;
    info->mstate_table = mstateTable.data();
}

// A title's own libc calls this after printing a heap report, with the heap name the report carried.
void APS5_VABI sceLibcInternalBacktraceForGame_nid_postfix(const char* heapName) {
    std::fprintf(stderr, "[libc] backtrace for heap %s:\n", heapName ? heapName : "(unnamed)");
    unsigned frame = 0;
    _Unwind_Backtrace_nid_postfix(PrintFrame, &frame);
    std::fflush(stderr);
}

// A title's own heap checks call this when they find a bad block; the report is the only effect.
int APS5_VABI sceLibcInternalHeapErrorReportForGame_nid_postfix(void* heap, void* block, std::uint64_t error) {
    std::fprintf(stderr, "[libc] guest heap error report: heap %p, block %p, error 0x%llx\n", heap, block, static_cast<unsigned long long>(error));
    std::fflush(stderr);
    return 0;
}

}
