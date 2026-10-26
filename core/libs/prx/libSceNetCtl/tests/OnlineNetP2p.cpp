#include "FakeLauncher.hpp"
#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <algorithm>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <arpa/inet.h>
#endif
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern "C" {
int APS5_VABI sceNetInit_nid_postfix(void);
int APS5_VABI sceNetSocket(const char*, int, int, int);
int APS5_VABI sceNetBind_nid_postfix(int, const void*, std::uint32_t);
int APS5_VABI sceNetGetsockname(int, void*, std::uint32_t*);
int APS5_VABI sceNetConnect(int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetSend(int, const void*, std::size_t, int);
std::int64_t APS5_VABI sceNetRecv(int, void*, std::size_t, int);
std::int64_t APS5_VABI sceNetSendto(int, const void*, std::size_t, int, const void*, std::uint32_t);
std::int64_t APS5_VABI sceNetRecvfrom(int, void*, std::size_t, int, void*, std::uint32_t*);
int APS5_VABI sceNetSocketClose(int);
int APS5_VABI sceNetListen(int, int);
int APS5_VABI sceNetAccept(int, void*, std::uint32_t*);
int APS5_VABI sceNetGetpeername(int, void*, std::uint32_t*);
int APS5_VABI sceNetSetsockopt(int, int, int, const void*, std::uint32_t);
int APS5_VABI sceNetGetsockopt(int, int, int, void*, std::uint32_t*);
int APS5_VABI sceNetShutdown(int, int);
int APS5_VABI sceNetEpollCreate(const char*, int);
int APS5_VABI sceNetEpollDestroy(int);
int APS5_VABI sceNetEpollControl(int, int, int, const NetEpollEvent*);
int APS5_VABI sceNetEpollWait(int, NetEpollEvent*, int, int);
}

namespace {

using namespace std::chrono_literals;

constexpr int AfInet = 2;
constexpr int SockDgram = 2;
constexpr int SockDgramP2p = 6;
constexpr int SockStreamP2p = 10;
constexpr int MsgDontwait = 0x80;
constexpr int ErrorBase = static_cast<int>(0x80410100u);
constexpr std::uint32_t Own = 0xC6120001u;
constexpr std::uint32_t Peer = 0xC6120002u;
constexpr std::uint32_t OtherPeer = 0xC6120003u;

struct Address {
    std::uint8_t length = 16;
    std::uint8_t family = AfInet;
    std::uint16_t port = 0;
    std::uint32_t address = 0;
    std::uint16_t vport = 0;
    std::uint8_t zero[6] = {};
};
static_assert(sizeof(Address) == 16);

Address make(std::uint32_t address, std::uint16_t port, std::uint16_t vport = 0) {
    Address out;
    out.port = htons(port);
    out.address = htonl(address);
    out.vport = htons(vport);
    return out;
}

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::string receive(int socket, Address& from, int flags = 0) {
    char buffer[256];
    std::uint32_t length = sizeof(from);
    for (int attempt = 0; attempt < 300; ++attempt) {
        const auto got = sceNetRecvfrom(socket, buffer, sizeof(buffer), flags | MsgDontwait, &from, &length);
        if (got >= 0) return std::string(buffer, static_cast<std::size_t>(got));
        std::this_thread::sleep_for(10ms);
    }
    throw std::runtime_error("nothing arrived");
}

constexpr int SolSocket = 0xffff;
constexpr int SoNbio = 0x1200;
constexpr int SoError = 0x1007;
constexpr int EpollIn = 1;
constexpr int EpollOut = 2;

// Reads exactly `size` bytes from a stream socket (blocking), or what came before the end.
std::string readStream(int socket, std::size_t size) {
    std::string out;
    char buffer[4096];
    while (out.size() < size) {
        const auto got = sceNetRecv(socket, buffer, std::min(sizeof(buffer), size - out.size()), 0);
        if (got <= 0) break;
        out.append(buffer, static_cast<std::size_t>(got));
    }
    return out;
}

bool waitFor(int epoll, int socket, std::uint32_t events) {
    NetEpollEvent event{};
    event.events = events;
    if (sceNetEpollControl(epoll, 1, socket, &event) != 0) return false;
    NetEpollEvent ready[4]{};
    const int count = sceNetEpollWait(epoll, ready, 4, 3000000);
    sceNetEpollControl(epoll, 3, socket, nullptr);
    return count == 1 && (ready[0].events & events) != 0;
}

// Stream P2P sockets through the bridge. The fake launcher plays the other player too: a stream
// this engine opens to a peer comes back to this engine as one from that peer.
void streams(Online::Testing::FakeLauncher& launcher) {
    launcher.SetStreamLoopback(true);
    const int listener = sceNetSocket("listen", AfInet, SockStreamP2p, 0);
    require(listener >= 0, "a stream P2P socket opens while the bridge is configured");
    const auto listening = make(0, 3659, 1);
    require(sceNetBind_nid_postfix(listener, &listening, sizeof(listening)) == 0, "the stream P2P socket binds port and virtual port");
    require(sceNetListen(listener, 4) == 0, "the stream P2P socket listens");
    Address name;
    std::uint32_t nameLength = sizeof(name);
    require(sceNetGetsockname(listener, &name, &nameLength) == 0 && ntohl(name.address) == Own && ntohs(name.port) == 3659 && ntohs(name.vport) == 1,
        "the listener's name is its virtual address, port and virtual port");
    const int twin = sceNetSocket("twin listen", AfInet, SockStreamP2p, 0);
    require(sceNetBind_nid_postfix(twin, &listening, sizeof(listening)) == 0 && sceNetListen(twin, 4) == (ErrorBase | 48),
        "a second listener on the same port and virtual port is in use");
    sceNetSocketClose(twin);

    const int client = sceNetSocket("client", AfInet, SockStreamP2p, 0);
    const auto clientName = make(0, 3660, 5);
    require(sceNetBind_nid_postfix(client, &clientName, sizeof(clientName)) == 0, "the client binds its port and virtual port");
    const auto target = make(Peer, 3659, 1);
    require(sceNetConnect(client, &target, sizeof(target)) == 0, "a stream P2P socket connects to a listening peer");
    require(launcher.WaitForStreams(1, 3000ms), "the stream open reaches the launcher");
    const auto opened = launcher.Streams()[0];
    require(opened.type == Online::Wire::Type::StreamOpen && opened.stream != 0 && (opened.stream & Online::Wire::LauncherStream) == 0 && opened.peer == Peer &&
                opened.peerPort == 3659 && opened.peerVport == 1 && opened.localPort == 3660 && opened.localVport == 5,
        "the launcher gets the stream, the peer, ports and virtual ports");

    Address from;
    std::uint32_t fromLength = sizeof(from);
    const int accepted = sceNetAccept(listener, &from, &fromLength);
    require(accepted >= 0, "the listener accepts the peer's stream");
    require(fromLength == 16 && ntohl(from.address) == Peer && ntohs(from.port) == 3660 && ntohs(from.vport) == 5, "the accepted stream comes from the peer's virtual address");
    Address peerName;
    std::uint32_t peerLength = sizeof(peerName);
    require(sceNetGetpeername(client, &peerName, &peerLength) == 0 && ntohl(peerName.address) == Peer && ntohs(peerName.port) == 3659 && ntohs(peerName.vport) == 1,
        "the connected socket's peer is the virtual address it connected to");
    nameLength = sizeof(name);
    require(sceNetGetsockname(accepted, &name, &nameLength) == 0 && ntohl(name.address) == Own && ntohs(name.port) == 3659 && ntohs(name.vport) == 1,
        "the accepted socket's name is the listener's");

    require(sceNetSend(client, "ping", 4, 0) == 4, "the client sends on the stream");
    require(readStream(accepted, 4) == "ping", "the bytes reach the accepted socket");
    require(sceNetSend(accepted, "pong!", 5, 0) == 5, "the accepted socket answers");
    require(readStream(client, 5) == "pong!", "the answer reaches the client");

    std::string big(300000, '\0');
    for (std::size_t index = 0; index < big.size(); ++index) big[index] = static_cast<char>(index * 7 + index / 251);
    std::thread sender([&] {
        std::size_t done = 0;
        while (done < big.size()) {
            const auto sent = sceNetSend(accepted, big.data() + done, big.size() - done, 0);
            if (sent <= 0) break;
            done += static_cast<std::size_t>(sent);
        }
    });
    const auto bigBack = readStream(client, big.size());
    sender.join();
    require(bigBack == big, "a large write arrives whole and in order");

    const int epoll = sceNetEpollCreate("streams", 0);
    require(epoll >= 0, "an epoll opens");
    require(waitFor(epoll, client, EpollOut), "the connected socket is writable");
    require(sceNetSend(accepted, "x", 1, 0) == 1, "one more byte goes out");
    require(waitFor(epoll, client, EpollIn), "epoll says the client is readable once bytes arrive");
    require(readStream(client, 1) == "x", "and the byte is there");

    const int nonblocking = sceNetSocket("nonblocking", AfInet, SockStreamP2p, 0);
    const int on = 1;
    require(sceNetSetsockopt(nonblocking, SolSocket, SoNbio, &on, sizeof(on)) == 0, "the socket turns non-blocking");
    const int started = sceNetConnect(nonblocking, &target, sizeof(target));
    require(started == 0 || started == (ErrorBase | 36), "a non-blocking connect starts");
    require(waitFor(epoll, nonblocking, EpollOut), "the non-blocking connect completes");
    int error = -1;
    std::uint32_t errorLength = sizeof(error);
    require(sceNetGetsockopt(nonblocking, SolSocket, SoError, &error, &errorLength) == 0 && error == 0, "without an error");
    require(waitFor(epoll, listener, EpollIn), "epoll says the listener has a stream to accept");
    fromLength = sizeof(from);
    const int second = sceNetAccept(listener, &from, &fromLength);
    require(second >= 0 && ntohl(from.address) == Peer && ntohs(from.vport) == 0, "the second stream is accepted from the peer");
    require(sceNetSend(nonblocking, "nb", 2, 0) == 2 && readStream(second, 2) == "nb", "the non-blocking stream carries bytes");
    sceNetSocketClose(nonblocking);
    char end[4];
    require(sceNetRecv(second, end, sizeof(end), 0) == 0, "closing one end ends the other's reads");
    sceNetSocketClose(second);

    require(sceNetShutdown(client, 1) == 0, "the client stops writing");
    require(sceNetRecv(accepted, end, sizeof(end), 0) == 0, "the accepted socket reads the end");
    require(sceNetSend(accepted, "late", 4, 0) == 4 && readStream(client, 4) == "late", "the other direction still works after a half close");
    sceNetSocketClose(accepted);
    require(sceNetRecv(client, end, sizeof(end), 0) == 0, "and then ends too");
    sceNetSocketClose(client);

    const int refused = sceNetSocket("refused", AfInet, SockStreamP2p, 0);
    const auto nobody = make(Peer, 4000, 1);
    require(sceNetConnect(refused, &nobody, sizeof(nobody)) == (ErrorBase | 61), "a connect to a port nobody listens on is refused");
    sceNetSocketClose(refused);
    const int refusedLater = sceNetSocket("refused later", AfInet, SockStreamP2p, 0);
    require(sceNetSetsockopt(refusedLater, SolSocket, SoNbio, &on, sizeof(on)) == 0, "non-blocking");
    const int later = sceNetConnect(refusedLater, &nobody, sizeof(nobody));
    require(later == 0 || later == (ErrorBase | 36), "a non-blocking connect to nobody starts");
    std::int64_t refusedRead = ErrorBase | 35;
    for (int attempt = 0; attempt < 300 && refusedRead == (ErrorBase | 35); ++attempt) {
        refusedRead = sceNetRecv(refusedLater, end, sizeof(end), 0);
        if (refusedRead == (ErrorBase | 35)) std::this_thread::sleep_for(10ms);
    }
    require(refusedRead == (ErrorBase | 54), "and the refusal resets it, never a clean end: " + std::to_string(refusedRead));
    sceNetSocketClose(refusedLater);
    const int outside = sceNetSocket("outside", AfInet, SockStreamP2p, 0);
    const auto real = make(0x7F000001u, 3659, 1);
    require(sceNetConnect(outside, &real, sizeof(real)) == (ErrorBase | 65), "a stream P2P socket cannot reach a real address");
    sceNetSocketClose(outside);

    require(sceNetSocketClose(listener) == 0, "the listener closes");
    const int again = sceNetSocket("again", AfInet, SockStreamP2p, 0);
    require(sceNetBind_nid_postfix(again, &listening, sizeof(listening)) == 0 && sceNetListen(again, 4) == 0, "a closed listener frees its port");
    sceNetSocketClose(again);
    const int late = sceNetSocket("late", AfInet, SockStreamP2p, 0);
    require(sceNetConnect(late, &target, sizeof(target)) == (ErrorBase | 61), "with nobody listening again the connect is refused");
    sceNetSocketClose(late);
    sceNetEpollDestroy(epoll);
}

}

int main() {
    try {
        Online::Wire::Secret secret{};
        for (std::size_t index = 0; index < secret.size(); ++index) secret[index] = static_cast<std::uint8_t>(0x50 + index);
        Online::Testing::FakeLauncher launcher(secret);
        Online::Wire::Account account;
        account.signedIn = true;
        account.accountId = 7;
        account.onlineId = "player";
        account.address = Own;
        launcher.SetAccount(account);
        launcher.SetDatagramHandler([](const Online::Wire::Datagram& in) -> std::optional<Online::Wire::Datagram> {
            Online::Wire::Datagram out = in;
            std::reverse(out.data.begin(), out.data.end());
            return out;
        });
        std::string hex;
        static constexpr char digits[] = "0123456789abcdef";
        for (const auto byte : secret) {
            hex += digits[byte >> 4];
            hex += digits[byte & 15];
        }
        const std::string endpoint = "127.0.0.1:" + std::to_string(launcher.Port());
        Online::Testing::SetEnvironment("ANYPS5_ONLINE", endpoint);
        Online::Testing::SetEnvironment("ANYPS5_ONLINE_SECRET", hex);
        sceNetInit_nid_postfix();

        const int p2p = sceNetSocket("p2p", AfInet, SockDgramP2p, 0);
        require(p2p >= 0, "a datagram P2P socket opens while the bridge is configured");
        const auto bound = make(0, 3658, 1);
        require(sceNetBind_nid_postfix(p2p, &bound, sizeof(bound)) == 0, "the P2P socket binds port and virtual port");
        Address name;
        std::uint32_t nameLength = sizeof(name);
        require(sceNetGetsockname(p2p, &name, &nameLength) == 0 && nameLength == 16 && ntohl(name.address) == Own && ntohs(name.port) == 3658 && ntohs(name.vport) == 1,
            "the P2P socket's name is its virtual address, port and virtual port");
        const int twin = sceNetSocket("twin", AfInet, SockDgramP2p, 0);
        require(sceNetBind_nid_postfix(twin, &bound, sizeof(bound)) == (ErrorBase | 48), "a second socket on the same port and virtual port is in use");
        const auto otherVport = make(0, 3658, 2);
        require(sceNetBind_nid_postfix(twin, &otherVport, sizeof(otherVport)) == 0, "another virtual port on the same port binds");

        const auto peer = make(Peer, 3658, 1);
        require(sceNetSendto(p2p, "ping", 4, 0, &peer, sizeof(peer)) == 4, "a send to a virtual address succeeds");
        require(launcher.WaitForDatagrams(1, 3000ms), "the datagram reaches the launcher");
        const auto sent = launcher.Datagrams()[0];
        require(sent.kind == Online::Wire::DatagramKind::P2p && sent.peer == Peer && sent.peerPort == 3658 && sent.peerVport == 1 && sent.localPort == 3658 &&
                sent.localVport == 1 && std::string(sent.data.begin(), sent.data.end()) == "ping",
            "the launcher gets peer, ports, virtual ports and bytes");
        Address from;
        require(receive(p2p, from) == "gnip", "the peer's answer arrives");
        require(ntohl(from.address) == Peer && ntohs(from.port) == 3658 && ntohs(from.vport) == 1 && from.family == AfInet, "the answer comes from the peer's virtual address");

        launcher.Send(Online::Wire::Type::Datagram, 0, 0, Online::Wire::Encode(Online::Wire::Datagram{OtherPeer, 3658, 9, 3658, 77, Online::Wire::DatagramKind::P2p, {'x'}}));
        launcher.Send(Online::Wire::Type::Datagram, 0, 0, Online::Wire::Encode(Online::Wire::Datagram{OtherPeer, 3658, 9, 3658, 2, Online::Wire::DatagramKind::P2p, {'h', 'i'}}));
        require(receive(twin, from) == "hi" && ntohl(from.address) == OtherPeer && ntohs(from.vport) == 9, "a datagram reaches the socket of its virtual port");
        char none[8];
        std::uint32_t noneLength = sizeof(from);
        require(sceNetRecvfrom(p2p, none, sizeof(none), MsgDontwait, &from, &noneLength) == (ErrorBase | 35), "a datagram for an unbound virtual port is dropped");

        const auto real = make(0x7F000001u, 3658, 1);
        require(sceNetSendto(p2p, "x", 1, 0, &real, sizeof(real)) == (ErrorBase | 65), "a P2P socket cannot reach a real address");

        const int udp = sceNetSocket("udp", AfInet, SockDgram, 0);
        require(udp >= 0, "an ordinary UDP socket opens");
        const auto server = make(Peer, 9000);
        require(sceNetSendto(udp, "hello", 5, 0, &server, sizeof(server)) == 5, "a UDP send to a virtual address succeeds");
        require(launcher.WaitForDatagrams(2, 3000ms), "the UDP datagram reaches the launcher");
        const auto udpSent = launcher.Datagrams()[1];
        require(udpSent.kind == Online::Wire::DatagramKind::Udp && udpSent.peer == Peer && udpSent.peerPort == 9000 && udpSent.localPort != 0, "UDP datagrams carry the socket's port");
        require(receive(udp, from) == "olleh" && ntohl(from.address) == Peer && ntohs(from.port) == 9000, "the UDP answer comes from the virtual peer");

        const int connected = sceNetSocket("connected", AfInet, SockDgram, 0);
        require(sceNetConnect(connected, &server, sizeof(server)) == 0, "a UDP socket connects to a virtual address");
        require(sceNetSend(connected, "abc", 3, 0) == 3, "a send on the connected socket goes to the peer");
        char reply[8];
        std::int64_t got = -1;
        for (int attempt = 0; attempt < 300 && got < 0; ++attempt) {
            got = sceNetRecv(connected, reply, sizeof(reply), MsgDontwait);
            if (got < 0) std::this_thread::sleep_for(10ms);
        }
        require(got == 3 && std::string(reply, 3) == "cba", "the connected socket reads the answer");

        require(sceNetSocketClose(p2p) == 0, "the P2P socket closes");
        const int again = sceNetSocket("again", AfInet, SockDgramP2p, 0);
        require(sceNetBind_nid_postfix(again, &bound, sizeof(bound)) == 0, "a closed socket frees its virtual port");
        sceNetSocketClose(again);
        sceNetSocketClose(twin);
        sceNetSocketClose(udp);
        sceNetSocketClose(connected);

        streams(launcher);
    } catch (const std::exception& error) {
        std::cerr << "online net p2p: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online net p2p: ok\n";
    return 0;
}
