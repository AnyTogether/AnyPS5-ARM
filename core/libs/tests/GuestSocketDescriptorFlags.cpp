#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>

extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI dup_nid_postfix(int);
int APS5_VABI dup2_nid_postfix(int, int);
int APS5_VABI fcntl_nid_postfix(int, int, ...);
int* APS5_VABI __error_nid_postfix();
}

namespace {

constexpr int GetDescriptorFlags = 1;
constexpr int SetDescriptorFlags = 2;
constexpr int CloseOnExec = 1;
constexpr int Stream = 1;
constexpr int SocketCloseOnExec = 0x10000000;

void Require(bool condition, const char* what) {
    if (condition) return;
    std::fprintf(stderr, "%s (errno %d)\n", what, *__error_nid_postfix());
    std::abort();
}

}

int main() {
    const int plain = socket_nid_postfix(2, Stream, 0);
    Require(plain >= 0, "socket failed");
    Require(fcntl_nid_postfix(plain, GetDescriptorFlags) == 0, "a new socket must not be close-on-exec (F_GETFD 0)");
    Require(fcntl_nid_postfix(plain, SetDescriptorFlags, CloseOnExec) == 0, "F_SETFD on a socket must succeed");
    Require(fcntl_nid_postfix(plain, GetDescriptorFlags) == CloseOnExec, "F_GETFD must read back FD_CLOEXEC");
    const int copy = dup_nid_postfix(plain);
    Require(copy >= 0 && fcntl_nid_postfix(copy, GetDescriptorFlags) == 0, "dup must clear FD_CLOEXEC on the copy");
    Require(fcntl_nid_postfix(plain, GetDescriptorFlags) == CloseOnExec, "dup must leave the flag of the original");
    Require(fcntl_nid_postfix(plain, SetDescriptorFlags, 0) == 0 && fcntl_nid_postfix(plain, GetDescriptorFlags) == 0, "F_SETFD 0 must clear FD_CLOEXEC");
    Require(close_nid_postfix(copy) == 0, "close failed");

    const int target = socket_nid_postfix(2, Stream, 0);
    Require(target >= 0, "socket failed");
    Require(fcntl_nid_postfix(target, SetDescriptorFlags, CloseOnExec) == 0 && fcntl_nid_postfix(target, GetDescriptorFlags) == CloseOnExec, "F_SETFD on the dup2 target must succeed");
    Require(fcntl_nid_postfix(plain, SetDescriptorFlags, CloseOnExec) == 0, "F_SETFD on a socket must succeed");
    Require(dup2_nid_postfix(plain, target) == target, "dup2 onto another socket must return the target");
    Require(fcntl_nid_postfix(target, GetDescriptorFlags) == 0, "dup2 must clear FD_CLOEXEC on the target");
    Require(fcntl_nid_postfix(plain, GetDescriptorFlags) == CloseOnExec, "dup2 must leave the flag of the original");
    Require(dup2_nid_postfix(plain, plain) == plain && fcntl_nid_postfix(plain, GetDescriptorFlags) == CloseOnExec, "dup2 onto the same descriptor must leave the flag");
    Require(fcntl_nid_postfix(plain, SetDescriptorFlags, 0) == 0, "F_SETFD 0 must clear FD_CLOEXEC");
    Require(close_nid_postfix(target) == 0, "close failed");

    const int marked = socket_nid_postfix(2, Stream | SocketCloseOnExec, 0);
    Require(marked >= 0 && fcntl_nid_postfix(marked, GetDescriptorFlags) == CloseOnExec, "SOCK_CLOEXEC must set FD_CLOEXEC");
    Require(close_nid_postfix(marked) == 0, "close failed");
    const int reused = socket_nid_postfix(2, Stream, 0);
    Require(reused >= 0 && fcntl_nid_postfix(reused, GetDescriptorFlags) == 0, "the flag of a closed socket must not reach the next socket");
    Require(close_nid_postfix(reused) == 0 && close_nid_postfix(plain) == 0, "close failed");
    return 0;
}
