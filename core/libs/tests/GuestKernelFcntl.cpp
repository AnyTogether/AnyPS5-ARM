#include "prx/libc/include/General.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI pipe_nid_postfix(int*);
int APS5_VABI fcntl_nid_postfix(int, int, ...);
int APS5_VABI ioctl_nid_postfix(int, std::uint64_t, void*);
std::int64_t APS5_VABI read_nid_postfix(int, void*, std::uint64_t);
std::int64_t APS5_VABI write_nid_postfix(int, const char*, std::int64_t);
int* APS5_VABI __error_nid_postfix();
int APS5_VABI sceKernelFcntl(int, int, ...);
int APS5_VABI sceKernelOpen(const char*, int, std::uint16_t);
int APS5_VABI sceKernelClose(int);
std::int64_t APS5_VABI sceKernelLseek(int, std::int64_t, int);
}
static void Require(bool value) { if (!value) std::abort(); }
static constexpr int DuplicateCommand = 0;
static constexpr int GetDescriptorFlags = 1;
static constexpr int SetDescriptorFlags = 2;
static constexpr int GetFlags = 3;
static constexpr int SetFlags = 4;
static constexpr int GetLock = 11;
static constexpr int SetLock = 12;
static constexpr int DarwinReadAhead = 16;
static constexpr int DuplicateCloseOnExec = 17;
static constexpr int ReadOnly = 0;
static constexpr int WriteOnly = 1;
static constexpr int ReadWrite = 2;
static constexpr int NonBlocking = 4;
static constexpr int Append = 8;
static constexpr int ReadAheadFlag = 0x200;
static constexpr int CreateReadWrite = 0x202;
static constexpr int CreateWriteAppend = 0x209;
static constexpr int GuestEbadf = 9;
static constexpr int GuestEfault = 14;
static constexpr int GuestEinval = 22;
static constexpr int GuestEagain = 35;
static constexpr std::uint64_t ReadableRequest = 0x4004667f;
static constexpr int SceEbadf = static_cast<int>(0x80020009u);
static constexpr int SceEinval = static_cast<int>(0x80020016u);
static constexpr int SceEnotsup = static_cast<int>(0x8002002du);

struct GuestLock {
    std::int64_t start;
    std::int64_t length;
    std::int32_t pid;
    std::int16_t type;
    std::int16_t whence;
    std::int32_t system;
};

static void RequireFailure(int result, int error) {
    Require(result == -1);
    Require(*__error_nid_postfix() == error);
}

template <typename TCall> static bool ThrowsWith(TCall call, const std::string& prefix) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        return std::string(error.what()).rfind(prefix, 0) == 0;
    }
    return false;
}

static void SocketsKeepTheirPath() {
    const int socket = socket_nid_postfix(2, 2, 0);
    Require(socket >= 0);
    Require(sceKernelFcntl(socket, GetFlags) == ReadWrite);
    Require(sceKernelFcntl(socket, SetFlags, ReadWrite | NonBlocking) == 0);
    Require(sceKernelFcntl(socket, GetFlags) == (ReadWrite | NonBlocking));
    Require(sceKernelFcntl(socket, SetFlags, 0) == 0);
    Require(sceKernelFcntl(socket, GetFlags) == ReadWrite);
    Require(sceKernelFcntl(socket, SetFlags, 0x8000) == SceEnotsup);
    Require(sceKernelFcntl(socket, GetFlags) == ReadWrite);
    Require(sceKernelFcntl(socket, 5) == SceEinval);
    Require(sceKernelFcntl(socket + 4096, GetFlags) == SceEbadf);
    int queued = -1;
    Require(ioctl_nid_postfix(socket, ReadableRequest, &queued) == 0 && queued == 0);
    Require(close_nid_postfix(socket) == 0);
    Require(sceKernelFcntl(socket, GetFlags) == SceEbadf);
    Require(sceKernelFcntl(-1, GetFlags) == SceEbadf);
    Require(sceKernelFcntl(12345, GetFlags) == SceEbadf);
}

static void FileFlagsRoundTrip() {
    const int file = sceKernelOpen("kernel_fcntl_probe.bin", CreateReadWrite, 0644);
    Require(file >= 0);
    Require(sceKernelFcntl(file, GetFlags) == ReadWrite);
    Require(fcntl_nid_postfix(file, SetFlags, ReadWrite | NonBlocking | 0x8000) == 0);
    Require(fcntl_nid_postfix(file, GetFlags) == (ReadWrite | NonBlocking));
    Require(fcntl_nid_postfix(file, SetFlags, 0) == 0);
    Require(fcntl_nid_postfix(file, GetFlags) == ReadWrite);
    Require(fcntl_nid_postfix(file, GetDescriptorFlags) == 0);
    Require(fcntl_nid_postfix(file, SetDescriptorFlags, 1) == 0);
    Require(fcntl_nid_postfix(file, GetDescriptorFlags) == 1);
    Require(sceKernelFcntl(file, SetDescriptorFlags, 0) == 0);
    Require(sceKernelFcntl(file, GetDescriptorFlags) == 0);
    Require(fcntl_nid_postfix(file, DarwinReadAhead, 1) == 0);
    Require(fcntl_nid_postfix(file, GetFlags) == (ReadWrite | ReadAheadFlag));

    const int duplicate = fcntl_nid_postfix(file, DuplicateCommand, 20);
    Require(duplicate >= 20);
    Require(fcntl_nid_postfix(duplicate, GetDescriptorFlags) == 0);
    Require(fcntl_nid_postfix(file, SetFlags, NonBlocking) == 0);
    Require(fcntl_nid_postfix(duplicate, GetFlags) == (ReadWrite | NonBlocking));
    const int closing = fcntl_nid_postfix(file, DuplicateCloseOnExec, duplicate);
    Require(closing > duplicate);
    Require(fcntl_nid_postfix(closing, GetDescriptorFlags) == 1);
    Require(fcntl_nid_postfix(file, GetDescriptorFlags) == 0);

    Require(write_nid_postfix(file, "abcde", 5) == 5);
    Require(sceKernelLseek(file, 2, 0) == 2);

    RequireFailure(fcntl_nid_postfix(file, DuplicateCommand, -1), GuestEinval);
    Require(sceKernelFcntl(file, DuplicateCommand, -1) == SceEinval);
    RequireFailure(fcntl_nid_postfix(file, 99), GuestEinval);
    RequireFailure(fcntl_nid_postfix(file, GetLock, nullptr), GuestEfault);
#ifdef _WIN32
    GuestLock lock{0, 0, 0, 3, 0, 0};
    Require(ThrowsWith([file, &lock] { fcntl_nid_postfix(file, SetLock, &lock); }, "fcntl: record locks are not implemented on Windows"));
#else
    GuestLock lock{0, 0, 0, 3, 0, 0};
    Require(fcntl_nid_postfix(file, SetLock, &lock) == 0);
    GuestLock probe{0, 0, 0, 1, 0, 0};
    Require(fcntl_nid_postfix(file, GetLock, &probe) == 0 && probe.type == 2);
    lock.type = 2;
    Require(fcntl_nid_postfix(file, SetLock, &lock) == 0);
    lock.type = 7;
    RequireFailure(fcntl_nid_postfix(file, SetLock, &lock), GuestEinval);
#endif

    for (const int descriptor : {closing, duplicate, file}) Require(close_nid_postfix(descriptor) == 0);
    RequireFailure(fcntl_nid_postfix(file, GetDescriptorFlags), GuestEbadf);
    RequireFailure(fcntl_nid_postfix(file, DuplicateCommand, 0), GuestEbadf);
    Require(sceKernelFcntl(file, GetFlags) == SceEbadf);

    const int appending = sceKernelOpen("kernel_fcntl_probe.bin", CreateWriteAppend, 0644);
    Require(appending >= 0);
    Require(fcntl_nid_postfix(appending, GetFlags) == (WriteOnly | Append));
    Require(fcntl_nid_postfix(appending, SetFlags, Append | NonBlocking) == 0);
    Require(fcntl_nid_postfix(appending, GetFlags) == (WriteOnly | Append | NonBlocking));
#ifdef _WIN32
    Require(ThrowsWith([appending] { fcntl_nid_postfix(appending, SetFlags, 0); }, "fcntl: changing O_APPEND on a file is not implemented"));
#else
    Require(fcntl_nid_postfix(appending, SetFlags, 0) == 0);
    Require(fcntl_nid_postfix(appending, GetFlags) == WriteOnly);
#endif
    Require(ThrowsWith([appending] { fcntl_nid_postfix(appending, SetFlags, Append | 0x80); }, "fcntl: changing O_FSYNC on a file is not implemented"));
    Require(sceKernelClose(appending) == 0);
    std::remove("kernel_fcntl_probe.bin");
}

static void PipeFlagsRoundTrip() {
    int pipe[2];
    Require(pipe_nid_postfix(pipe) == 0);
    Require(fcntl_nid_postfix(pipe[0], GetFlags) == ReadOnly);
    Require(fcntl_nid_postfix(pipe[1], GetFlags) == WriteOnly);
    Require(fcntl_nid_postfix(pipe[1], SetDescriptorFlags, 1) == 0);
    Require(fcntl_nid_postfix(pipe[1], GetDescriptorFlags) == 1);
    Require(fcntl_nid_postfix(pipe[0], GetDescriptorFlags) == 0);

    Require(fcntl_nid_postfix(pipe[0], SetFlags, fcntl_nid_postfix(pipe[0], GetFlags) | NonBlocking) == 0);
    Require(fcntl_nid_postfix(pipe[0], GetFlags) == (ReadOnly | NonBlocking));
    char buffer[8] = {};
    RequireFailure(static_cast<int>(read_nid_postfix(pipe[0], buffer, sizeof(buffer))), GuestEagain);
    Require(write_nid_postfix(pipe[1], "abc", 3) == 3);
    Require(read_nid_postfix(pipe[0], buffer, sizeof(buffer)) == 3);
    RequireFailure(static_cast<int>(read_nid_postfix(pipe[0], buffer, sizeof(buffer))), GuestEagain);

    Require(fcntl_nid_postfix(pipe[1], SetFlags, NonBlocking) == 0);
    char block[1024] = {};
    std::int64_t written = 0;
    std::int64_t result = 0;
    while (written < (1 << 22) && (result = write_nid_postfix(pipe[1], block, sizeof(block))) > 0) written += result;
    Require(written > 0);
    RequireFailure(static_cast<int>(result), GuestEagain);

    RequireFailure(fcntl_nid_postfix(pipe[0], DarwinReadAhead, 1), GuestEbadf);
    GuestLock lock{0, 0, 0, 3, 0, 0};
    RequireFailure(fcntl_nid_postfix(pipe[1], SetLock, &lock), GuestEbadf);
    Require(ThrowsWith([&pipe] { fcntl_nid_postfix(pipe[0], SetFlags, NonBlocking | 0x40); }, "fcntl: O_ASYNC on a pipe is not implemented"));
    for (const int descriptor : pipe) Require(close_nid_postfix(descriptor) == 0);
}

static void StandardInputFlags() {
    const int flags = fcntl_nid_postfix(0, GetFlags);
    Require(flags >= 0);
    Require((flags & 3) != WriteOnly);
    Require(fcntl_nid_postfix(0, SetFlags, fcntl_nid_postfix(0, GetFlags) & ~NonBlocking) == 0);
    Require(fcntl_nid_postfix(0, GetFlags) == (flags & ~NonBlocking));
    Require(fcntl_nid_postfix(0, SetDescriptorFlags, 1) == 0);
    Require(fcntl_nid_postfix(0, GetDescriptorFlags) == 1);
    Require(fcntl_nid_postfix(0, SetDescriptorFlags, 0) == 0);
    Require(fcntl_nid_postfix(0, GetDescriptorFlags) == 0);
}

int main() {
    SocketsKeepTheirPath();
    FileFlagsRoundTrip();
    PipeFlagsRoundTrip();
    StandardInputFlags();
    return 0;
}
