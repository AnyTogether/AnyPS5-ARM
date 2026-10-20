#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI bind_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI connect_nid_postfix(int, const void*, std::uint32_t);
std::int64_t APS5_VABI sendto_nid_postfix(int, const void*, std::uint64_t, int, const void*, std::uint32_t);
int APS5_VABI close_nid_postfix(int);
int* APS5_VABI __error_nid_postfix();
}

namespace {

constexpr int Stream = 1;
constexpr int Datagram = 2;
constexpr int ErrorFault = 14;
constexpr int ErrorInvalid = 22;
constexpr int ErrorNameTooLong = 63;

void Require(bool condition, const char* what) {
    if (condition) return;
    std::fprintf(stderr, "%s (errno %d)\n", what, *__error_nid_postfix());
    std::abort();
}

bool Fails(long result, int error) { return result == -1 && *__error_nid_postfix() == error; }

std::array<std::uint8_t, 16> Loopback() {
    std::array<std::uint8_t, 16> address{16, 2};
    address[4] = 127;
    address[7] = 1;
    return address;
}

void ShortAddressesAreInvalid() {
    const int stream = socket_nid_postfix(2, Stream, 0);
    const int datagram = socket_nid_postfix(2, Datagram, 0);
    Require(stream >= 0 && datagram >= 0, "socket failed");
    const auto address = Loopback();
    Require(Fails(connect_nid_postfix(stream, address.data(), 1), ErrorInvalid), "connect with a length below the size of sa_family must fail with EINVAL (22)");
    Require(Fails(bind_nid_postfix(stream, address.data(), 0), ErrorInvalid), "bind with length 0 must fail with EINVAL (22)");
    Require(Fails(connect_nid_postfix(stream, address.data(), 3), ErrorInvalid), "connect with an AF_INET address shorter than sockaddr_in must fail with EINVAL (22)");
    Require(Fails(bind_nid_postfix(stream, address.data(), 15), ErrorInvalid), "bind with an AF_INET address shorter than sockaddr_in must fail with EINVAL (22)");
    Require(Fails(sendto_nid_postfix(datagram, "x", 1, 0, address.data(), 8), ErrorInvalid), "sendto with an AF_INET address shorter than sockaddr_in must fail with EINVAL (22)");
    std::array<std::uint8_t, 28> v6{28, 28};
    const int stream6 = socket_nid_postfix(28, Stream, 0);
    Require(stream6 >= 0, "socket failed");
    Require(Fails(connect_nid_postfix(stream6, v6.data(), 20), ErrorInvalid), "connect with an AF_INET6 address shorter than sockaddr_in6 must fail with EINVAL (22)");
    Require(Fails(bind_nid_postfix(stream, address.data(), 256), ErrorNameTooLong), "an address longer than SOCK_MAXADDRLEN (255) must fail with ENAMETOOLONG (63)");
    Require(Fails(bind_nid_postfix(stream, nullptr, address.size()), ErrorFault), "a null address must fail with EFAULT (14)");
    Require(close_nid_postfix(stream) == 0 && close_nid_postfix(datagram) == 0 && close_nid_postfix(stream6) == 0, "close failed");
}

void FullAddressesStillWork() {
    const int stream = socket_nid_postfix(2, Stream, 0);
    Require(stream >= 0, "socket failed");
    const auto address = Loopback();
    Require(bind_nid_postfix(stream, address.data(), address.size()) == 0, "bind of a full sockaddr_in failed");
    Require(close_nid_postfix(stream) == 0, "close failed");
}

}

int main() {
    ShortAddressesAreInvalid();
    FullAddressesStillWork();
    return 0;
}
