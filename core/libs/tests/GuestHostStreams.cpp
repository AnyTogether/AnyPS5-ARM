#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>

extern "C" {
int APS5_VABI dup_nid_postfix(int);
int APS5_VABI pipe_nid_postfix(int*);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI sceKernelClose(int);
int* APS5_VABI __error_nid_postfix();
}

static void Require(bool value) { if (!value) std::abort(); }

constexpr int GuestEbadf = 9;
constexpr int SceKernelErrorEbadf = static_cast<int>(0x80020009);

static bool Open(int fd) {
    const int duplicate = dup_nid_postfix(fd);
    if (duplicate < 0) return false;
    Require(close_nid_postfix(duplicate) == 0);
    return true;
}

int main() {
    bool open[3];
    for (int fd = 0; fd < 3; ++fd) open[fd] = Open(fd);
    for (int fd = 0; fd < 3; ++fd) {
        if (!open[fd]) continue;
        Require(close_nid_postfix(fd) == -1 && *__error_nid_postfix() == GuestEbadf);
        Require(sceKernelClose(fd) == SceKernelErrorEbadf);
        Require(Open(fd));
    }
    int pipe[2];
    Require(pipe_nid_postfix(pipe) == 0);
    for (const int fd : pipe) Require(fd >= 3 || !open[fd]);
    Require(close_nid_postfix(pipe[0]) == 0 && close_nid_postfix(pipe[1]) == 0);
    return 0;
}
