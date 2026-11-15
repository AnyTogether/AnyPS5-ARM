// CLFLUSHOPT and CLWB on Linux x86-64 hosts without them (#127): the PS5's Zen 2 has both, Intel CPUs
// before Skylake have neither, so a title's cache-line flush raises SIGILL there. This handler runs
// each one as CLFLUSH on the same operand (CacheFlushEmulation.hpp) and resumes after it; any other
// SIGILL goes to the handler installed before, as before. libkernel's guest exception delivery
// (Exception.cpp) offers SIGILL to the same emulation before a guest handler sees it.
// APS5_NO_CACHE_FLUSH_EMULATION=1 leaves SIGILL alone.
#if defined(__linux__) && defined(__x86_64__)
#include "prx/libc/include/CacheFlushEmulation.hpp"
#include "prx/libc/include/FatalLine.hpp"
#include <csignal>
#include <cstdlib>
#include <signal.h>
#include <ucontext.h>

namespace {

struct sigaction g_previousIllegal {};

void Chain(int signal, siginfo_t* info, void* context) {
    const auto& previous = g_previousIllegal;
    if ((previous.sa_flags & SA_SIGINFO) != 0 && previous.sa_sigaction != nullptr) {
        previous.sa_sigaction(signal, info, context);
        return;
    }
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN && previous.sa_handler != nullptr) {
        previous.sa_handler(signal);
        return;
    }
    if (info->si_code <= 0 && previous.sa_handler == SIG_IGN) return;
    FatalLine::Write(signal, info, context);
    ::signal(signal, SIG_DFL);
    // A fault the kernel raised faults again on return, now with the default action.
    if (info->si_code <= 0) ::raise(signal);
}

void HandleIllegal(int signal, siginfo_t* info, void* context) {
    if (info != nullptr && info->si_code > 0 && context != nullptr && cache_flush::EmulateContext(static_cast<ucontext_t*>(context)->uc_mcontext)) return;
    Chain(signal, info, context);
}

const bool g_cacheFlushEmulationInstalled = [] {
    const char* disabled = std::getenv("APS5_NO_CACHE_FLUSH_EMULATION");
    if (disabled != nullptr && *disabled != '\0' && !(disabled[0] == '0' && disabled[1] == '\0')) return false;
    struct sigaction action {};
    action.sa_sigaction = HandleIllegal;
    action.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&action.sa_mask);
    return sigaction(SIGILL, &action, &g_previousIllegal) == 0;
}();

}
#endif
