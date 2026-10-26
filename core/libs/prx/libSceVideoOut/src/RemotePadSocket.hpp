#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPADSOCKET_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPADSOCKET_HPP

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <system_error>
#ifndef SIO_UDP_CONNRESET
#define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12)
#endif
#else
#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

namespace RemotePad::Net {

using Handle = std::intptr_t;
constexpr Handle None = -1;

#ifdef _WIN32

constexpr bool StampsArrivals = false;

inline SOCKET native(Handle handle) {
    return static_cast<SOCKET>(handle);
}

inline std::string LastError() {
    return std::system_category().message(::WSAGetLastError());
}

inline Handle OpenUdp() {
    static const int started = [] {
        WSADATA data{};
        return ::WSAStartup(MAKEWORD(2, 2), &data);
    }();
    if (started != 0) {
        ::WSASetLastError(started);
        return None;
    }
    const SOCKET opened = ::socket(AF_INET, SOCK_DGRAM, 0);
    if (opened == INVALID_SOCKET) return None;
    BOOL report = FALSE;
    DWORD returned = 0;
    ::WSAIoctl(opened, SIO_UDP_CONNRESET, &report, sizeof(report), nullptr, 0, &returned, nullptr, nullptr);
    return static_cast<Handle>(opened);
}

inline bool StampArrivals(Handle) {
    return true;
}

inline std::optional<std::uint16_t> BindLoopback(Handle handle) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int length = sizeof(address);
    if (::bind(native(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::getsockname(native(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0) {
        return std::nullopt;
    }
    return ntohs(address.sin_port);
}

inline bool MakeNonBlocking(Handle handle) {
    u_long nonBlocking = 1;
    return ::ioctlsocket(native(handle), FIONBIO, &nonBlocking) == 0;
}

inline bool SetReceiveTimeout(Handle handle, std::chrono::milliseconds timeout) {
    const DWORD milliseconds = static_cast<DWORD>(timeout.count());
    return ::setsockopt(native(handle), SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&milliseconds), sizeof(milliseconds)) == 0;
}

inline std::optional<std::size_t> Receive(Handle handle, std::uint8_t* buffer, std::size_t size, std::optional<std::int64_t>& arrivedMicros) {
    arrivedMicros.reset();
    while (true) {
        const int got = ::recv(native(handle), reinterpret_cast<char*>(buffer), static_cast<int>(size), 0);
        if (got >= 0) return static_cast<std::size_t>(got);
        const int error = ::WSAGetLastError();
        if (error == WSAEMSGSIZE) return size;
        if (error == WSAECONNRESET) continue;
        return std::nullopt;
    }
}

inline std::int64_t WallMicros() {
    return 0;
}

inline bool SendTo(Handle handle, const std::uint8_t* bytes, std::size_t size, std::uint16_t port) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    const int sent = ::sendto(native(handle), reinterpret_cast<const char*>(bytes), static_cast<int>(size), 0, reinterpret_cast<sockaddr*>(&address), sizeof(address));
    return sent >= 0 && static_cast<std::size_t>(sent) == size;
}

inline void Close(Handle handle) {
    ::closesocket(native(handle));
}

#else

constexpr bool StampsArrivals = true;

inline std::string LastError() {
    return std::strerror(errno);
}

inline Handle OpenUdp() {
    const int opened = ::socket(AF_INET, SOCK_DGRAM, 0);
    return opened < 0 ? None : opened;
}

inline bool StampArrivals(Handle handle) {
    const int stamped = 1;
    return ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_TIMESTAMP, &stamped, sizeof(stamped)) == 0;
}

inline std::optional<std::uint16_t> BindLoopback(Handle handle) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof(address);
    if (::bind(static_cast<int>(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::getsockname(static_cast<int>(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0) {
        return std::nullopt;
    }
    return ntohs(address.sin_port);
}

inline bool MakeNonBlocking(Handle handle) {
    const int descriptor = static_cast<int>(handle);
    return ::fcntl(descriptor, F_SETFL, ::fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0;
}

inline bool SetReceiveTimeout(Handle handle, std::chrono::milliseconds timeout) {
    timeval value{};
    value.tv_sec = static_cast<decltype(value.tv_sec)>(timeout.count() / 1000);
    value.tv_usec = static_cast<decltype(value.tv_usec)>(timeout.count() % 1000 * 1000);
    return ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_RCVTIMEO, &value, sizeof(value)) == 0;
}

inline std::int64_t micros(const timeval& time) {
    return static_cast<std::int64_t>(time.tv_sec) * 1000000 + static_cast<std::int64_t>(time.tv_usec);
}

inline std::optional<std::size_t> Receive(Handle handle, std::uint8_t* buffer, std::size_t size, std::optional<std::int64_t>& arrivedMicros) {
    arrivedMicros.reset();
    alignas(cmsghdr) std::uint8_t control[CMSG_SPACE(sizeof(timeval))]{};
    iovec vector{buffer, size};
    msghdr message{};
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = static_cast<socklen_t>(sizeof(control));
    const auto got = ::recvmsg(static_cast<int>(handle), &message, 0);
    if (got < 0) return std::nullopt;
    for (auto* header = CMSG_FIRSTHDR(&message); header != nullptr; header = CMSG_NXTHDR(&message, header)) {
        if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_TIMESTAMP) continue;
        timeval arrived{};
        std::memcpy(&arrived, CMSG_DATA(header), sizeof(arrived));
        arrivedMicros = micros(arrived);
    }
    return static_cast<std::size_t>(got);
}

inline std::int64_t WallMicros() {
    timeval current{};
    ::gettimeofday(&current, nullptr);
    return micros(current);
}

inline bool SendTo(Handle handle, const std::uint8_t* bytes, std::size_t size, std::uint16_t port) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    const auto sent = ::sendto(static_cast<int>(handle), bytes, size, 0, reinterpret_cast<sockaddr*>(&address), sizeof(address));
    return sent >= 0 && static_cast<std::size_t>(sent) == size;
}

inline void Close(Handle handle) {
    ::close(static_cast<int>(handle));
}

#endif

}

#endif
