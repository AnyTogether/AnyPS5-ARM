// Sockets made by libkernel's POSIX socket() and sockets made by sceNetSocket share one descriptor namespace on the
// console, so libSceNet calls take either. IL2CPP's socket layer (PPSA02429, Il2CppUserAssemblies.prx) creates its
// sockets with socket() and then polls them with sceNetEpollControl/sceNetEpollWait and checks blocking mode with
// sceNetSetsockopt/sceNetGetsockopt(SOL_SOCKET, SO_NBIO).
#include "SceTypes.hpp"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string_view>

extern "C" {
int APS5_VABI socket_nid_postfix(int, int, int);
int APS5_VABI bind_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI getsockname_nid_postfix(int, void*, std::uint32_t*);
std::int64_t APS5_VABI sendto_nid_postfix(int, const void*, std::size_t, int, const void*, std::uint32_t);
int APS5_VABI close_nid_postfix(int);
int APS5_VABI sceNetEpollCreate(const char*, int);
int APS5_VABI sceNetEpollDestroy(int);
int APS5_VABI sceNetEpollControl(int, int, int, const NetEpollEvent*);
int APS5_VABI sceNetEpollWait(int, NetEpollEvent*, int, int);
int APS5_VABI sceNetSetsockopt(int, int, int, const void*, std::uint32_t);
int APS5_VABI sceNetGetsockopt(int, int, int, void*, std::uint32_t*);
int APS5_VABI sceNetGetSockInfo(int, void*, int, int);
}

namespace {

constexpr int Inet = 2;
constexpr int Datagram = 2;
constexpr int Add = 1;
constexpr int Modify = 2;
constexpr int Delete = 3;
constexpr int In = 1;
constexpr int Out = 2;
constexpr int BadDescriptor = static_cast<int>(0x80410109);
constexpr int NoEntry = static_cast<int>(0x80410102);
constexpr int SocketLevel = 0xffff;
constexpr int NonBlocking = 0x1200;
constexpr int SocketError = 0x1007;
constexpr std::uint64_t Data = 0x1122334455667788;

void Require(bool value, const char* message) {
    if (value) return;
    std::fprintf(stderr, "kernel socket: %s\n", message);
    std::exit(1);
}

struct Bound {
    int descriptor;
    std::array<std::uint8_t, 16> address{16, 2, 0, 0, 127, 0, 0, 1};

    Bound() : descriptor(socket_nid_postfix(Inet, Datagram, 0)) {
        Require(descriptor >= 0, "socket()");
        Require(bind_nid_postfix(descriptor, address.data(), address.size()) == 0, "bind()");
        std::uint32_t size = address.size();
        Require(getsockname_nid_postfix(descriptor, address.data(), &size) == 0, "getsockname()");
    }
};

NetEpollEvent Event(std::uint32_t events) {
    NetEpollEvent event{};
    event.events = events;
    std::memcpy(&event.data, &Data, sizeof(Data));
    return event;
}

void CheckEpoll() {
    Bound receiver;
    const int sender = socket_nid_postfix(Inet, Datagram, 0);
    Require(sender >= 0, "sender socket()");
    const int epoll = sceNetEpollCreate("kernel-socket", 0);
    Require(epoll >= 0, "sceNetEpollCreate");
    const auto readable = Event(In);
    Require(sceNetEpollControl(epoll, Add, receiver.descriptor, &readable) == 0, "ADD of a socket() descriptor");
    std::array<NetEpollEvent, 4> events{};
    Require(sceNetEpollWait(epoll, events.data(), events.size(), 0) == 0, "an idle socket reported an event");
    const char payload[] = "kernel";
    Require(sendto_nid_postfix(sender, payload, sizeof(payload), 0, receiver.address.data(), receiver.address.size()) ==
        static_cast<std::int64_t>(sizeof(payload)), "sendto()");
    Require(sceNetEpollWait(epoll, events.data(), events.size(), 2000000) == 1, "no event after a datagram arrived");
    std::uint64_t data = 0;
    std::memcpy(&data, &events[0].data, sizeof(data));
    Require(events[0].ident == static_cast<std::uint64_t>(receiver.descriptor) && (events[0].events & In) != 0 && data == Data,
        "event did not name the descriptor, readability and its data");
    const auto writable = Event(Out);
    Require(sceNetEpollControl(epoll, Modify, receiver.descriptor, &writable) == 0, "MOD of a socket() descriptor");
    Require(sceNetEpollWait(epoll, events.data(), events.size(), 2000000) == 1 && (events[0].events & Out) != 0,
        "MOD did not take effect");
    Require(sceNetEpollControl(epoll, Delete, receiver.descriptor, nullptr) == 0, "DEL of a socket() descriptor");
    Require(sceNetEpollControl(epoll, Delete, receiver.descriptor, nullptr) == NoEntry, "second DEL must be ENOENT");
    Require(sceNetEpollWait(epoll, events.data(), events.size(), 0) == 0, "deleted descriptor still reported");

    // A descriptor closed with close() while registered stops reporting, and its number is free for a new socket.
    Require(sceNetEpollControl(epoll, Add, receiver.descriptor, &readable) == 0, "ADD after DEL");
    Require(close_nid_postfix(receiver.descriptor) == 0, "close()");
    Require(sceNetEpollWait(epoll, events.data(), events.size(), 0) == 0, "closed descriptor reported an event");
    Require(sceNetEpollControl(epoll, Add, receiver.descriptor, &readable) == BadDescriptor, "ADD of a closed descriptor");
    Bound reused;
    Require(sceNetEpollControl(epoll, Add, reused.descriptor, &readable) == 0, "ADD of a new socket on a reused number");
    Require(sceNetEpollControl(epoll, Delete, reused.descriptor, nullptr) == 0, "DEL of the new socket");
    Require(close_nid_postfix(reused.descriptor) == 0 && close_nid_postfix(sender) == 0, "close() sockets");
    Require(sceNetEpollDestroy(epoll) == 0, "sceNetEpollDestroy");
    std::printf("epoll: ADD, MOD, DEL and wait work on socket() descriptors\n");
}

void CheckOptions() {
    Bound socket;
    for (const int enabled : {1, 0}) {
        Require(sceNetSetsockopt(socket.descriptor, SocketLevel, NonBlocking, &enabled, sizeof(enabled)) == 0,
            "sceNetSetsockopt(SO_NBIO) on a socket() descriptor");
        int value = -1;
        std::uint32_t size = sizeof(value);
        Require(sceNetGetsockopt(socket.descriptor, SocketLevel, NonBlocking, &value, &size) == 0 && size == sizeof(value),
            "sceNetGetsockopt(SO_NBIO) on a socket() descriptor");
        Require((value != 0) == (enabled != 0), "SO_NBIO did not read back what was set");
    }
    int pending = -1;
    std::uint32_t size = sizeof(pending);
    Require(sceNetGetsockopt(socket.descriptor, SocketLevel, SocketError, &pending, &size) == 0 && pending == 0,
        "sceNetGetsockopt(SO_ERROR) on a socket() descriptor");
    std::array<std::uint8_t, 0x200> info{};
    Require(sceNetGetSockInfo(socket.descriptor, info.data(), 1, 0) == 1, "sceNetGetSockInfo on a socket() descriptor");
    int reported = -1;
    std::memcpy(&reported, info.data() + 0x24, sizeof(reported));
    Require(reported == socket.descriptor && info[0x28] == Datagram && std::memcmp(info.data() + 0x3c, socket.address.data() + 2, 2) == 0,
        "sceNetGetSockInfo did not describe the socket() descriptor");
    Require(close_nid_postfix(socket.descriptor) == 0, "close()");
    int value = 0;
    size = sizeof(value);
    Require(sceNetGetsockopt(socket.descriptor, SocketLevel, NonBlocking, &value, &size) == BadDescriptor,
        "sceNetGetsockopt on a closed descriptor must be EBADF");
    std::printf("options: SO_NBIO and SO_ERROR read back on socket() descriptors\n");
}

}

int main(int argc, char** argv) {
    const std::string_view test = argc > 1 ? argv[1] : "";
    if (test == "epoll") CheckEpoll();
    else if (test == "options") CheckOptions();
    else Require(false, "usage: guest_net_kernel_socket_tests epoll|options");
    return 0;
}
