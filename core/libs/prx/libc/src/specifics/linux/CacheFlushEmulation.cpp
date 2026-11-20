// CLFLUSHOPT and CLWB on Linux x86-64 hosts without them (#127): the PS5's Zen 2 has both, Intel CPUs
// before Skylake have neither, so a title's cache-line flush raises SIGILL there. libc's SIGILL handler
// (the fatal signal report in CrashReport.cpp) offers each SIGILL to EmulateSignal first, which runs a
// CLFLUSHOPT or CLWB as CLFLUSH on the same operand (CacheFlushEmulation.hpp) and resumes after it;
// any other SIGILL is reported and passed on as before. The emulation has no handler of its own, so
// the disposition a host program installed before libc loaded stays what the crash report keeps.
// libkernel's guest exception delivery (Exception.cpp) offers SIGILL to the same emulation before a
// guest handler sees it. APS5_NO_CACHE_FLUSH_EMULATION=1 leaves SIGILL alone.
#if defined(__linux__) && defined(__x86_64__)
#include "prx/libc/include/CacheFlushEmulation.hpp"
#include <csignal>
#include <cstdlib>
#include <signal.h>
#include <ucontext.h>

namespace {

// Read once at load: the handler only reads the flag.
const bool g_cacheFlushEmulationEnabled = [] {
    const char* disabled = std::getenv("APS5_NO_CACHE_FLUSH_EMULATION");
    return !(disabled != nullptr && *disabled != '\0' && !(disabled[0] == '0' && disabled[1] == '\0'));
}();

}

namespace cache_flush {

bool EmulateSignal(int signal, siginfo_t* info, void* context) {
    if (!g_cacheFlushEmulationEnabled || signal != SIGILL || info == nullptr || info->si_code <= 0 || context == nullptr) return false;
    return EmulateContext(static_cast<ucontext_t*>(context)->uc_mcontext);
}

}
#endif
