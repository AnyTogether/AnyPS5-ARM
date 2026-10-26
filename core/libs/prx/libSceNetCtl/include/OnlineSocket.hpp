#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINESOCKET_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINESOCKET_HPP

// The few loopback TCP calls the online bridge (and the tests' fake launcher) make, with a
// POSIX and a Winsock side. On macOS and Linux these are the calls the bridge made before.

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include "prx/libSceNetCtl/include/OnlineSocketHandle.hpp"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

namespace Online::Net {

#ifdef _WIN32

inline SOCKET native(Handle handle) {
    return static_cast<SOCKET>(handle);
}

// Winsock needs WSAStartup once per process before the first socket.
inline bool Start() {
    static const int started = [] {
        WSADATA data{};
        return ::WSAStartup(MAKEWORD(2, 2), &data);
    }();
    return started == 0;
}

inline Handle OpenTcp() {
    if (!Start()) return None;
    const SOCKET opened = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    return opened == INVALID_SOCKET ? None : static_cast<Handle>(opened);
}

inline void SetNoDelay(Handle handle) {
    const BOOL one = TRUE;
    ::setsockopt(native(handle), IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&one), sizeof(one));
}

inline bool ConnectLoopback(Handle handle, std::uint16_t port) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return ::connect(native(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0;
}

// Listens on 127.0.0.1 at a port the system picks and returns it. No SO_REUSEADDR: on
// Windows it would let another program take the same port.
inline std::optional<std::uint16_t> ListenLoopback(Handle handle, int backlog) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int length = sizeof(address);
    if (::bind(native(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || ::listen(native(handle), backlog) != 0 ||
        ::getsockname(native(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0) {
        return std::nullopt;
    }
    return ntohs(address.sin_port);
}

inline bool WaitReadable(Handle handle, int milliseconds) {
    WSAPOLLFD waiting{native(handle), POLLRDNORM, 0};
    return ::WSAPoll(&waiting, 1, milliseconds) > 0;
}

inline Handle Accept(Handle listener) {
    const SOCKET accepted = ::accept(native(listener), nullptr, nullptr);
    return accepted == INVALID_SOCKET ? None : static_cast<Handle>(accepted);
}

// Bytes received (0 when the peer closed), or -1.
inline long Receive(Handle handle, std::uint8_t* out, std::size_t size) {
    while (true) {
        const int got = ::recv(native(handle), reinterpret_cast<char*>(out), static_cast<int>(size > 0x7fffffff ? 0x7fffffff : size), 0);
        if (got >= 0) return got;
        if (::WSAGetLastError() == WSAEINTR) continue;
        return -1;
    }
}

// Bytes sent, or -1.
inline long Send(Handle handle, const std::uint8_t* bytes, std::size_t size) {
    while (true) {
        const int sent = ::send(native(handle), reinterpret_cast<const char*>(bytes), static_cast<int>(size > 0x7fffffff ? 0x7fffffff : size), 0);
        if (sent >= 0) return sent;
        if (::WSAGetLastError() == WSAEINTR) continue;
        return -1;
    }
}

// 0 waits without end, as on POSIX.
inline void SetReceiveTimeout(Handle handle, std::chrono::milliseconds timeout) {
    const DWORD milliseconds = static_cast<DWORD>(timeout.count());
    ::setsockopt(native(handle), SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&milliseconds), sizeof(milliseconds));
}

// Ends both directions and wakes a thread blocked in recv on it: shutdown alone does not
// always end a blocking Winsock recv, cancelling the socket's pending I/O does.
inline void ShutdownBoth(Handle handle) {
    ::shutdown(native(handle), SD_BOTH);
    ::CancelIoEx(reinterpret_cast<HANDLE>(native(handle)), nullptr);
}

inline void Close(Handle handle) {
    ::closesocket(native(handle));
}

inline std::uint32_t ProcessId() {
    return static_cast<std::uint32_t>(::GetCurrentProcessId());
}

inline std::uint16_t LocalPort(Handle handle) {
    sockaddr_in address{};
    int length = sizeof(address);
    if (::getsockname(native(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0 || address.sin_family != AF_INET) return 0;
    return ntohs(address.sin_port);
}

inline std::uint16_t PeerPort(Handle handle) {
    sockaddr_in address{};
    int length = sizeof(address);
    if (::getpeername(native(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0 || address.sin_family != AF_INET) return 0;
    return ntohs(address.sin_port);
}

inline bool SetBlocking(Handle handle, bool blocking) {
    u_long mode = blocking ? 0 : 1;
    return ::ioctlsocket(native(handle), FIONBIO, &mode) == 0;
}

inline bool WaitWritable(Handle handle, int milliseconds) {
    WSAPOLLFD waiting{native(handle), POLLWRNORM, 0};
    return ::WSAPoll(&waiting, 1, milliseconds) > 0 && (waiting.revents & (POLLERR | POLLHUP)) == 0;
}

inline int PendingError(Handle handle) {
    int error = 0;
    int length = sizeof(error);
    if (::getsockopt(native(handle), SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &length) != 0) return -1;
    return error;
}

inline bool InProgress() {
    return ::WSAGetLastError() == WSAEWOULDBLOCK;
}

inline void ShutdownWrite(Handle handle) {
    ::shutdown(native(handle), SD_SEND);
}

// Wakes a thread blocked receiving on the socket (and, on Windows, one blocked sending) without
// sending the peer anything.
inline void WakeReceiver(Handle handle) {
    ::shutdown(native(handle), SD_RECEIVE);
    ::CancelIoEx(reinterpret_cast<HANDLE>(native(handle)), nullptr);
}

// Nothing on Windows: a Winsock send that times out leaves the socket unusable, and WakeReceiver's
// CancelIoEx already ends a blocked send.
inline void SetSendTimeout(Handle, std::chrono::milliseconds) {}

// The last send failed because its timeout passed.
inline bool TimedOut() {
    return false;
}

// The next close sends a reset instead of a graceful end.
inline void ResetOnClose(Handle handle) {
    linger value{1, 0};
    ::setsockopt(native(handle), SOL_SOCKET, SO_LINGER, reinterpret_cast<const char*>(&value), sizeof(value));
}

#else

#ifdef MSG_NOSIGNAL
constexpr int SendFlags = MSG_NOSIGNAL;
#else
constexpr int SendFlags = 0;
#endif

inline bool Start() {
    return true;
}

inline Handle OpenTcp() {
    const int opened = ::socket(AF_INET, SOCK_STREAM, 0);
    return opened < 0 ? None : static_cast<Handle>(opened);
}

inline void SetNoDelay(Handle handle) {
    const int one = 1;
    ::setsockopt(static_cast<int>(handle), IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
}

inline bool ConnectLoopback(Handle handle, std::uint16_t port) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return ::connect(static_cast<int>(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0;
}

inline std::optional<std::uint16_t> ListenLoopback(Handle handle, int backlog) {
    const int socket = static_cast<int>(handle);
    const int one = 1;
    ::setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof(address);
    if (::bind(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || ::listen(socket, backlog) != 0 ||
        ::getsockname(socket, reinterpret_cast<sockaddr*>(&address), &length) != 0) {
        return std::nullopt;
    }
    return ntohs(address.sin_port);
}

inline bool WaitReadable(Handle handle, int milliseconds) {
    pollfd waiting{static_cast<int>(handle), POLLIN, 0};
    return ::poll(&waiting, 1, milliseconds) > 0;
}

inline Handle Accept(Handle listener) {
    const int accepted = ::accept(static_cast<int>(listener), nullptr, nullptr);
    return accepted < 0 ? None : static_cast<Handle>(accepted);
}

inline long Receive(Handle handle, std::uint8_t* out, std::size_t size) {
    while (true) {
        const auto got = ::recv(static_cast<int>(handle), out, size, 0);
        if (got >= 0) return static_cast<long>(got);
        if (errno == EINTR) continue;
        return -1;
    }
}

inline long Send(Handle handle, const std::uint8_t* bytes, std::size_t size) {
    while (true) {
        const auto sent = ::send(static_cast<int>(handle), bytes, size, SendFlags);
        if (sent >= 0) return static_cast<long>(sent);
        if (errno == EINTR) continue;
        return -1;
    }
}

inline void SetReceiveTimeout(Handle handle, std::chrono::milliseconds timeout) {
    timeval value{};
    value.tv_sec = static_cast<decltype(value.tv_sec)>(timeout.count() / 1000);
    value.tv_usec = static_cast<decltype(value.tv_usec)>((timeout.count() % 1000) * 1000);
    ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_RCVTIMEO, &value, sizeof(value));
}

inline void ShutdownBoth(Handle handle) {
    ::shutdown(static_cast<int>(handle), SHUT_RDWR);
}

inline void Close(Handle handle) {
    ::close(static_cast<int>(handle));
}

inline std::uint32_t ProcessId() {
    return static_cast<std::uint32_t>(::getpid());
}

inline std::uint16_t LocalPort(Handle handle) {
    sockaddr_in address{};
    socklen_t length = sizeof(address);
    if (::getsockname(static_cast<int>(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0 || address.sin_family != AF_INET) return 0;
    return ntohs(address.sin_port);
}

inline std::uint16_t PeerPort(Handle handle) {
    sockaddr_in address{};
    socklen_t length = sizeof(address);
    if (::getpeername(static_cast<int>(handle), reinterpret_cast<sockaddr*>(&address), &length) != 0 || address.sin_family != AF_INET) return 0;
    return ntohs(address.sin_port);
}

inline bool SetBlocking(Handle handle, bool blocking) {
    const int flags = ::fcntl(static_cast<int>(handle), F_GETFL, 0);
    if (flags < 0) return false;
    return ::fcntl(static_cast<int>(handle), F_SETFL, blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK)) == 0;
}

inline bool WaitWritable(Handle handle, int milliseconds) {
    pollfd waiting{static_cast<int>(handle), POLLOUT, 0};
    return ::poll(&waiting, 1, milliseconds) > 0 && (waiting.revents & (POLLERR | POLLHUP)) == 0;
}

inline int PendingError(Handle handle) {
    int error = 0;
    socklen_t length = sizeof(error);
    if (::getsockopt(static_cast<int>(handle), SOL_SOCKET, SO_ERROR, &error, &length) != 0) return -1;
    return error;
}

inline bool InProgress() {
    return errno == EINPROGRESS;
}

inline void ShutdownWrite(Handle handle) {
    ::shutdown(static_cast<int>(handle), SHUT_WR);
}

inline void WakeReceiver(Handle handle) {
    ::shutdown(static_cast<int>(handle), SHUT_RD);
}

inline void SetSendTimeout(Handle handle, std::chrono::milliseconds timeout) {
    timeval value{};
    value.tv_sec = static_cast<decltype(value.tv_sec)>(timeout.count() / 1000);
    value.tv_usec = static_cast<decltype(value.tv_usec)>((timeout.count() % 1000) * 1000);
    ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_SNDTIMEO, &value, sizeof(value));
}

inline bool TimedOut() {
    return errno == EAGAIN || errno == EWOULDBLOCK;
}

inline void ResetOnClose(Handle handle) {
    linger value{1, 0};
    ::setsockopt(static_cast<int>(handle), SOL_SOCKET, SO_LINGER, &value, sizeof(value));
}

#endif

// Binds to 127.0.0.1 at a port the system picks and returns it.
inline std::optional<std::uint16_t> BindLoopback(Handle handle) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::bind(static_cast<decltype(::socket(0, 0, 0))>(handle), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) return std::nullopt;
    const auto port = LocalPort(handle);
    if (port == 0) return std::nullopt;
    return port;
}

// Connects to 127.0.0.1:port, waiting at most `milliseconds` (a full backlog on macOS drops the
// handshake instead of refusing it); the socket is blocking again afterwards.
inline bool ConnectLoopbackWithin(Handle handle, std::uint16_t port, int milliseconds) {
    if (!SetBlocking(handle, false)) return false;
    bool connected = ConnectLoopback(handle, port);
    if (!connected && InProgress()) connected = WaitWritable(handle, milliseconds) && PendingError(handle) == 0;
    return SetBlocking(handle, true) && connected;
}

}

#endif
