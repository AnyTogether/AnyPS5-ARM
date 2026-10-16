#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI socketpair_nid_postfix(int, int, int, int*);
int APS5_VABI bind_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI listen_nid_postfix(int, int);
int APS5_VABI getsockname_nid_postfix(int, void*, std::uint32_t*);
int APS5_VABI connect_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI accept_nid_postfix(int, void*, std::uint32_t*);
int APS5_VABI shutdown_nid_postfix(int, int);
int APS5_VABI setsockopt_nid_postfix(int, int, int, const void*, std::uint32_t);
int APS5_VABI getsockopt_nid_postfix(int, int, int, void*, std::uint32_t*);
int APS5_VABI fcntl_nid_postfix(int, int, ...);
int APS5_VABI close_nid_postfix(int);
std::int64_t APS5_VABI send_nid_postfix(int, const void*, std::uint64_t, int);
std::int64_t APS5_VABI recv_nid_postfix(int, void*, std::uint64_t, int);
std::int64_t APS5_VABI write_nid_postfix(int, const char*, std::int64_t);
int* APS5_VABI __error_nid_postfix();
}

static void Check(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "socket stream option check failed at line %d, errno %d\n", line, *__error_nid_postfix());
        std::abort();
    }
}
#define Require(value) Check((value), __LINE__)

constexpr int SocketLevel = 0xffff;
constexpr int TcpLevel = 6;
constexpr int TcpNoDelay = 1;
constexpr int TcpMaximumSegment = 2;
constexpr int NoSigpipe = 0x800;
constexpr int NonBlockingOption = 0x1200;
constexpr int NoSignalFlag = 0x20000;
constexpr int GetStatusFlags = 3;
constexpr int NonBlockingFlag = 4;
constexpr int Invalid = 22;
constexpr int BrokenPipe = 32;
constexpr int Again = 35;
constexpr int NoProtocolOption = 42;

#ifndef _WIN32
static volatile std::sig_atomic_t brokenPipes = 0;
static void CountBrokenPipe(int) {
    brokenPipes = brokenPipes + 1;
}
#endif

static int BrokenPipes() {
#ifdef _WIN32
    return 0;
#else
    return brokenPipes;
#endif
}

static bool Fails(std::int64_t result, int error) {
    return result == -1 && *__error_nid_postfix() == error;
}

static bool Set(int descriptor, int level, int option, int value) {
    return setsockopt_nid_postfix(descriptor, level, option, &value, sizeof(value)) == 0;
}

static int Get(int descriptor, int level, int option) {
    int value = -1;
    std::uint32_t length = sizeof(value);
    Require(getsockopt_nid_postfix(descriptor, level, option, &value, &length) == 0 && length == sizeof(value));
    return value;
}

int main() {
    const int listener = socket_nid_postfix(2, 1, 0);
    Require(listener >= 0);
    std::array<std::uint8_t, 16> address{16, 2, 0, 0, 127, 0, 0, 1};
    Require(bind_nid_postfix(listener, address.data(), address.size()) == 0);
    Require(listen_nid_postfix(listener, 4) == 0);
    std::uint32_t addressSize = address.size();
    Require(getsockname_nid_postfix(listener, address.data(), &addressSize) == 0);
    const int client = socket_nid_postfix(2, 1, 0);
    Require(client >= 0 && connect_nid_postfix(client, address.data(), address.size()) == 0);
    const int server = accept_nid_postfix(listener, nullptr, nullptr);
    Require(server >= 0);
    Require(Set(listener, SocketLevel, NoSigpipe, 1) && Set(listener, TcpLevel, TcpNoDelay, 1));
    const int secondClient = socket_nid_postfix(2, 1, 0);
    Require(secondClient >= 0 && connect_nid_postfix(secondClient, address.data(), address.size()) == 0);
    const int inheriting = accept_nid_postfix(listener, nullptr, nullptr);
    Require(inheriting >= 0);
    Require(Get(inheriting, SocketLevel, NoSigpipe) == NoSigpipe && Get(inheriting, TcpLevel, TcpNoDelay) == 4);
    Require(Get(server, SocketLevel, NoSigpipe) == 0 && Get(server, TcpLevel, TcpNoDelay) == 0);
    Require(close_nid_postfix(inheriting) == 0 && close_nid_postfix(secondClient) == 0);
    const int datagram = socket_nid_postfix(2, 2, 0);
    std::array<std::uint8_t, 16> datagramAddress{16, 2, 0, 0, 127, 0, 0, 1};
    Require(datagram >= 0 && bind_nid_postfix(datagram, datagramAddress.data(), datagramAddress.size()) == 0);
    int local[2]{-1, -1};
    Require(socketpair_nid_postfix(1, 1, 0, local) == 0);

    int one = 1;
    Require(Get(client, TcpLevel, TcpNoDelay) == 0);
    Require(Set(client, TcpLevel, TcpNoDelay, 7) && Get(client, TcpLevel, TcpNoDelay) == 4);
    unsigned char byte = 0x7f;
    std::uint32_t length = sizeof(byte);
    Require(getsockopt_nid_postfix(client, TcpLevel, TcpNoDelay, &byte, &length) == 0 && length == sizeof(byte) && byte == 4);
    int value = 0;
    Require(Set(client, TcpLevel, TcpNoDelay, 0) && Get(client, TcpLevel, TcpNoDelay) == 0);
    Require(Fails(setsockopt_nid_postfix(client, TcpLevel, TcpNoDelay, &one, sizeof(one) - 1), Invalid));
    Require(Fails(setsockopt_nid_postfix(client, TcpLevel, TcpMaximumSegment, &one, sizeof(one)), NoProtocolOption));
    length = sizeof(value);
    Require(Fails(setsockopt_nid_postfix(datagram, TcpLevel, TcpNoDelay, &one, sizeof(one)), Invalid));
    Require(Fails(getsockopt_nid_postfix(datagram, TcpLevel, TcpNoDelay, &value, &length), Invalid));
    Require(Fails(setsockopt_nid_postfix(local[0], TcpLevel, TcpNoDelay, &one, sizeof(one)), Invalid));
    Require(Fails(getsockopt_nid_postfix(local[0], TcpLevel, TcpNoDelay, &value, &length), Invalid));

    char received = 0;
    Require(Get(server, SocketLevel, NonBlockingOption) == 0);
    Require((fcntl_nid_postfix(server, GetStatusFlags) & NonBlockingFlag) == 0);
    Require(Set(server, SocketLevel, NonBlockingOption, 5) && Get(server, SocketLevel, NonBlockingOption) == 1);
    Require((fcntl_nid_postfix(server, GetStatusFlags) & NonBlockingFlag) != 0);
    Require(Fails(recv_nid_postfix(server, &received, sizeof(received), 0), Again));
    Require(Set(server, SocketLevel, NonBlockingOption, 0) && Get(server, SocketLevel, NonBlockingOption) == 0);
    Require((fcntl_nid_postfix(server, GetStatusFlags) & NonBlockingFlag) == 0);
    Require(Fails(setsockopt_nid_postfix(server, SocketLevel, NonBlockingOption, &one, sizeof(one) - 1), Invalid));
    Require(Set(datagram, SocketLevel, NonBlockingOption, 1) && Get(datagram, SocketLevel, NonBlockingOption) == 1);
    Require(Fails(recv_nid_postfix(datagram, &received, sizeof(received), 0), Again));

#ifndef _WIN32
    std::signal(SIGPIPE, CountBrokenPipe);
#endif
    Require(Get(client, SocketLevel, NoSigpipe) == 0);
    Require(Set(client, SocketLevel, NoSigpipe, 3) && Get(client, SocketLevel, NoSigpipe) == NoSigpipe);
    Require(Fails(setsockopt_nid_postfix(client, SocketLevel, NoSigpipe, &one, sizeof(one) - 1), Invalid));
    Require(shutdown_nid_postfix(client, 1) == 0);
    Require(Fails(send_nid_postfix(client, "x", 1, 0), BrokenPipe));
    Require(Fails(write_nid_postfix(client, "x", 1), BrokenPipe));
    Require(BrokenPipes() == 0);
    Require(Set(client, SocketLevel, NoSigpipe, 0) && Get(client, SocketLevel, NoSigpipe) == 0);
    Require(Fails(send_nid_postfix(client, "x", 1, NoSignalFlag), BrokenPipe));
    Require(BrokenPipes() == 0);
#ifndef _WIN32
    Require(Fails(send_nid_postfix(client, "x", 1, 0), BrokenPipe));
    Require(BrokenPipes() == 1);
#endif

    Require(close_nid_postfix(local[0]) == 0 && close_nid_postfix(local[1]) == 0);
    Require(close_nid_postfix(datagram) == 0 && close_nid_postfix(server) == 0);
    Require(close_nid_postfix(client) == 0 && close_nid_postfix(listener) == 0);
    return 0;
}
