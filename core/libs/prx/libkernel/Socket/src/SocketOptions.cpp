#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/socket.h>
#endif
#include "prx/libkernel/Socket/include/SocketError.hpp"
#include "prx/libkernel/Socket/include/SocketOptions.hpp"
#include <algorithm>
#include <cstring>

namespace GuestSockets {
namespace {

constexpr int GuestAcceptConnection = 0x2;
constexpr int GuestReuseAddress = 0x4;
constexpr int GuestKeepAlive = 0x8;
constexpr int GuestDontRoute = 0x10;
constexpr int GuestBroadcast = 0x20;
constexpr int GuestLinger = 0x80;
constexpr int GuestOobInline = 0x100;
constexpr int GuestSendBuffer = 0x1001;
constexpr int GuestReceiveBuffer = 0x1002;
constexpr int GuestError = 0x1007;
constexpr int GuestType = 0x1008;

constexpr int ErrorInvalid = 22;
constexpr int ErrorDomain = 33;
constexpr int ErrorNoProtocolOption = 42;
constexpr int MaximumLinger = 65535;

struct GuestLingerValue {
    std::int32_t enabled;
    std::int32_t seconds;
};

#ifdef _WIN32
using NativeHandle = SOCKET;
using NativeOptionValue = const char*;
using NativeOptionOutput = char*;
int HostError() { return GuestErrorFromHost(WSAGetLastError()); }
#else
using NativeHandle = int;
using NativeOptionValue = const void*;
using NativeOptionOutput = void*;
int HostError() { return GuestErrorFromHost(errno); }
#endif

int NativeBoolean(int option) {
    switch (option) {
        case GuestReuseAddress: return SO_REUSEADDR;
        case GuestKeepAlive: return SO_KEEPALIVE;
        case GuestDontRoute: return SO_DONTROUTE;
        case GuestBroadcast: return SO_BROADCAST;
        case GuestOobInline: return SO_OOBINLINE;
        default: return -1;
    }
}

int Copy(void* output, std::uint32_t* length, const void* value, std::uint32_t size) {
    const std::uint32_t count = std::min(*length, size);
    if (count != 0 && !output) return ErrorInvalid;
    if (count != 0) std::memcpy(output, value, count);
    *length = count;
    return 0;
}

}

int SetSocketLevelOption(std::uintptr_t native, SocketOptionState& state, int option, const void* value, std::uint32_t length) {
    const auto handle = static_cast<NativeHandle>(native);
    if (option == GuestLinger) {
        if (length < sizeof(GuestLingerValue)) return ErrorInvalid;
        if (!value) return ErrorInvalid;
        GuestLingerValue guest;
        std::memcpy(&guest, value, sizeof(guest));
        if (guest.seconds < 0 || guest.seconds > MaximumLinger) return ErrorDomain;
#ifdef _WIN32
        linger request{};
        request.l_onoff = guest.enabled != 0 ? 1 : 0;
        request.l_linger = static_cast<u_short>(guest.seconds);
#else
        linger request{};
        request.l_onoff = guest.enabled != 0 ? 1 : 0;
        request.l_linger = guest.seconds;
#endif
        if (::setsockopt(handle, SOL_SOCKET, SO_LINGER, reinterpret_cast<NativeOptionValue>(&request), sizeof(request))) return HostError();
        return 0;
    }
    const bool native_boolean = NativeBoolean(option) != -1;
    if (native_boolean || option == GuestSendBuffer || option == GuestReceiveBuffer) {
        if (length < sizeof(int)) return ErrorInvalid;
        if (!value) return ErrorInvalid;
        int number;
        std::memcpy(&number, value, sizeof(number));
        if (option == GuestSendBuffer || option == GuestReceiveBuffer) {
            if (number < 1) return ErrorInvalid;
            const int nativeOption = option == GuestSendBuffer ? SO_SNDBUF : SO_RCVBUF;
            if (::setsockopt(handle, SOL_SOCKET, nativeOption, reinterpret_cast<NativeOptionValue>(&number), sizeof(number))) return HostError();
            return 0;
        }
        const int enabled = number != 0 ? 1 : 0;
        if (::setsockopt(handle, SOL_SOCKET, NativeBoolean(option), reinterpret_cast<NativeOptionValue>(&enabled), sizeof(enabled))) return HostError();
        return 0;
    }
    return ErrorNoProtocolOption;
}

int GetSocketLevelOption(std::uintptr_t native, SocketOptionState& state, int type, int option, void* value, std::uint32_t* length) {
    const auto handle = static_cast<NativeHandle>(native);
    if (option == GuestLinger) {
        linger current{};
        socklen_t size = sizeof(current);
        if (::getsockopt(handle, SOL_SOCKET, SO_LINGER, reinterpret_cast<NativeOptionOutput>(&current), &size)) return HostError();
        const GuestLingerValue guest{current.l_onoff != 0 ? GuestLinger : 0, static_cast<std::int32_t>(current.l_linger)};
        return Copy(value, length, &guest, sizeof(guest));
    }
    int number = 0;
    if (const int nativeOption = NativeBoolean(option); nativeOption != -1) {
        int enabled = 0;
        socklen_t size = sizeof(enabled);
        if (::getsockopt(handle, SOL_SOCKET, nativeOption, reinterpret_cast<NativeOptionOutput>(&enabled), &size)) return HostError();
        number = enabled != 0 ? option : 0;
    } else if (option == GuestAcceptConnection) {
        int listening = 0;
        socklen_t size = sizeof(listening);
        if (::getsockopt(handle, SOL_SOCKET, SO_ACCEPTCONN, reinterpret_cast<NativeOptionOutput>(&listening), &size)) return HostError();
        number = listening != 0 ? GuestAcceptConnection : 0;
    } else if (option == GuestType) {
        number = type;
    } else if (option == GuestError) {
        int pending = 0;
        socklen_t size = sizeof(pending);
        if (::getsockopt(handle, SOL_SOCKET, SO_ERROR, reinterpret_cast<NativeOptionOutput>(&pending), &size)) return HostError();
#ifdef _WIN32
        if (pending != 0 && pending == state.reportedError) pending = 0;
        else if (pending != 0) state.reportedError = pending;
#endif
        number = pending == 0 ? 0 : GuestErrorFromHost(pending);
    } else if (option == GuestSendBuffer || option == GuestReceiveBuffer) {
        socklen_t size = sizeof(number);
        if (::getsockopt(handle, SOL_SOCKET, option == GuestSendBuffer ? SO_SNDBUF : SO_RCVBUF, reinterpret_cast<NativeOptionOutput>(&number), &size)) return HostError();
    } else {
        return ErrorNoProtocolOption;
    }
    return Copy(value, length, &number, sizeof(number));
}

}
