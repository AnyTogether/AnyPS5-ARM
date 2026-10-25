#include "prx/libSceNet/include/VirtualNet.hpp"
#include "prx/libSceNetCtl/include/Online.hpp"
#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <arpa/inet.h>
#include <cstring>
#include <map>
#include <mutex>
#include <netinet/in.h>
#include <sys/socket.h>
#include <tuple>
#include <unistd.h>
#include <vector>

namespace VirtualNet {

namespace {

using Key = std::tuple<std::uint8_t, std::uint16_t, std::uint16_t>;

struct Route {
    std::uint16_t nativePort = 0;
    int descriptor = -1;
};

std::mutex routesMutex;
std::map<Key, Route> routes;
int relay = -1;
std::uint16_t relayPort = 0;
std::atomic<std::uint64_t> undelivered{0};

// A datagram the game's socket could not be given (no socket on its port, or the loopback hop
// refused it) is dropped and counted, never fatal; the count is logged at powers of two.
void dropped(const char* why) {
    const auto count = ++undelivered;
    if ((count & (count - 1)) == 0) std::fprintf(stderr, "[online] dropped %llu incoming game datagram(s) so far (last: %s)\n", static_cast<unsigned long long>(count), why);
}

void deliver(const Online::Wire::Datagram& datagram) {
    std::uint16_t nativePort = 0;
    int socket = -1;
    {
        std::lock_guard lock(routesMutex);
        const auto found = routes.find({static_cast<std::uint8_t>(datagram.kind), datagram.localPort, datagram.localVport});
        if (found == routes.end() || relay < 0) {
            dropped("no socket on its port");
            return;
        }
        nativePort = found->second.nativePort;
        socket = relay;
    }
    std::vector<std::uint8_t> packet(HeaderSize + datagram.data.size());
    const std::uint32_t magic = HeaderMagic;
    const std::uint32_t address = htonl(datagram.peer);
    const std::uint16_t port = htons(datagram.peerPort);
    const std::uint16_t vport = htons(datagram.peerVport);
    std::memcpy(packet.data(), &magic, 4);
    std::memcpy(packet.data() + 4, &address, 4);
    std::memcpy(packet.data() + 8, &port, 2);
    std::memcpy(packet.data() + 10, &vport, 2);
    if (!datagram.data.empty()) std::memcpy(packet.data() + HeaderSize, datagram.data.data(), datagram.data.size());
    sockaddr_in target{};
    target.sin_family = AF_INET;
    target.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    target.sin_port = htons(nativePort);
    if (::sendto(socket, packet.data(), packet.size(), 0, reinterpret_cast<const sockaddr*>(&target), sizeof(target)) < 0) dropped(std::strerror(errno));
}

bool openRelay() {
    if (relay >= 0) return true;
    const int socket = ::socket(AF_INET, SOCK_DGRAM, 0);
    if (socket < 0) return false;
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof(address);
    // macOS caps a UDP send at the socket's send buffer (9216 bytes by default), and the hop to the
    // game's socket carries datagrams up to 65535 bytes plus the header.
    const int sendBuffer = static_cast<int>(Online::Wire::MaxDatagram + HeaderSize) * 4;
    ::setsockopt(socket, SOL_SOCKET, SO_SNDBUF, &sendBuffer, sizeof(sendBuffer));
    if (::bind(socket, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) != 0 ||
        ::getsockname(socket, reinterpret_cast<sockaddr*>(&address), &length) != 0) {
        ::close(socket);
        return false;
    }
    relay = socket;
    relayPort = ntohs(address.sin_port);
    OnlineSetDatagramReceiver_nid_no_patch(deliver);
    return true;
}

}

bool Enabled() {
    return Online::Enabled();
}

std::optional<std::uint32_t> VirtualDestination(const void* guestAddress, std::uint32_t length) {
    if (!guestAddress || length < 8) return std::nullopt;
    const auto* bytes = static_cast<const std::uint8_t*>(guestAddress);
    if (bytes[1] != 2) return std::nullopt;
    std::uint32_t address = 0;
    std::memcpy(&address, bytes + 4, 4);
    address = ntohl(address);
    if (!Online::Wire::IsVirtual(address) && !Online::Wire::IsGroup(address)) return std::nullopt;
    return address;
}

std::uint16_t GuestVport(const void* guestAddress, std::uint32_t length) {
    if (!guestAddress || length < 10) return 0;
    std::uint16_t vport = 0;
    std::memcpy(&vport, static_cast<const std::uint8_t*>(guestAddress) + 8, 2);
    return ntohs(vport);
}

std::uint32_t OwnAddress() {
    const auto state = Online::CurrentAccount();
    return state && state->account.signedIn ? state->account.address : 0;
}

bool Register(Online::Wire::DatagramKind kind, std::uint16_t port, std::uint16_t vport, std::uint16_t nativePort, int descriptor) {
    std::lock_guard lock(routesMutex);
    if (!openRelay()) return false;
    const Key key{static_cast<std::uint8_t>(kind), port, vport};
    const auto found = routes.find(key);
    if (found != routes.end() && found->second.descriptor != descriptor) return false;
    routes[key] = Route{nativePort, descriptor};
    return true;
}

void Forget(int descriptor) {
    std::lock_guard lock(routesMutex);
    std::erase_if(routes, [descriptor](const auto& entry) { return entry.second.descriptor == descriptor; });
}

bool Send(const Online::Wire::Datagram& datagram) {
    return OnlineSendDatagram_nid_no_patch(datagram);
}

bool FromRelay(const sockaddr_storage& peer) {
    if (peer.ss_family != AF_INET) return false;
    const auto& v4 = reinterpret_cast<const sockaddr_in&>(peer);
    std::lock_guard lock(routesMutex);
    return relay >= 0 && v4.sin_addr.s_addr == htonl(INADDR_LOOPBACK) && v4.sin_port == htons(relayPort);
}

std::optional<Source> ReadHeader(std::span<const std::uint8_t> bytes) {
    if (bytes.size() < HeaderSize) return std::nullopt;
    std::uint32_t magic = 0;
    std::memcpy(&magic, bytes.data(), 4);
    if (magic != HeaderMagic) return std::nullopt;
    std::uint32_t address = 0;
    std::uint16_t port = 0;
    std::uint16_t vport = 0;
    std::memcpy(&address, bytes.data() + 4, 4);
    std::memcpy(&port, bytes.data() + 8, 2);
    std::memcpy(&vport, bytes.data() + 10, 2);
    return Source{ntohl(address), ntohs(port), ntohs(vport)};
}

void WriteGuestAddress(const Source& source, void* address, std::uint32_t* length) {
    if (!address || !length) return;
    std::uint8_t bytes[16]{};
    bytes[0] = 16;
    bytes[1] = 2;
    const std::uint16_t port = htons(source.port);
    const std::uint32_t ip = htonl(source.address);
    const std::uint16_t vport = htons(source.vport);
    std::memcpy(bytes + 2, &port, 2);
    std::memcpy(bytes + 4, &ip, 4);
    std::memcpy(bytes + 8, &vport, 2);
    const auto copied = std::min<std::uint32_t>(*length, 16);
    std::memcpy(address, bytes, copied);
    *length = copied;
}

}
