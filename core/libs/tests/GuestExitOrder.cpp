#include "prx/libc/include/Shutdown.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>

extern "C" int APS5_VABI __cxa_thread_atexit_impl_nid_postfix(void (APS5_VABI *func)(void*), void* arg, void* dso);
extern "C" int APS5_VABI __cxa_atexit_nid_postfix(void (APS5_VABI *func)(void*), void* arg, void* dsoHandle);
extern "C" int APS5_VABI atexit_nid_postfix(void (APS5_VABI *func)());

namespace {

int events[2];

void Record(char value) {
    static_cast<void>(!write(events[1], &value, 1));
}

void APS5_VABI GuestThreadDestructor(void*) { Record('T'); }

void APS5_VABI GuestDestructor(void*) { Record('D'); }

void APS5_VABI GuestHandler() { Record('A'); }

void HostHandler() { Record('H'); }

bool GuestHandlersRunAndHostHandlersAreSkipped() {
    if (pipe(events) != 0) return false;
    const pid_t child = fork();
    if (child < 0) return false;
    if (child == 0) {
        close(events[0]);
        __cxa_thread_atexit_impl_nid_postfix(GuestThreadDestructor, nullptr, &events);
        __cxa_atexit_nid_postfix(GuestDestructor, nullptr, nullptr);
        atexit_nid_postfix(GuestHandler);
        std::atexit(HostHandler);
        LibcExit_nid_no_patch(7);
    }
    close(events[1]);
    char order[8] = {};
    ssize_t length = 0;
    for (;;) {
        const ssize_t count = read(events[0], order + length, sizeof(order) - 1 - static_cast<std::size_t>(length));
        if (count <= 0) break;
        length += count;
    }
    close(events[0]);
    int status = 0;
#ifdef __APPLE__
    const std::string_view expected = "TDA";
#else
    const std::string_view expected = "DA";
#endif
    return waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 7 && std::string_view(order, static_cast<std::size_t>(length)) == expected;
}

}

int main() {
    if (!GuestHandlersRunAndHostHandlersAreSkipped()) {
        std::fputs("exit must run the guest thread-local destructors (macOS), the guest destructors, then the guest atexit handlers, and end the process before the host exit handlers\n", stderr);
        return 1;
    }
    return 0;
}
