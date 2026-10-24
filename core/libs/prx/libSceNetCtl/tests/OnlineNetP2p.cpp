#include "FakeLauncher.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <algorithm>
#include <arpa/inet.h>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

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
        ::setenv("ANYPS5_ONLINE", endpoint.c_str(), 1);
        ::setenv("ANYPS5_ONLINE_SECRET", hex.c_str(), 1);
        sceNetInit_nid_postfix();

        require(sceNetSocket("stream", AfInet, SockStreamP2p, 0) == (ErrorBase | 43), "stream P2P sockets are still refused");
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
    } catch (const std::exception& error) {
        std::cerr << "online net p2p: " << error.what() << '\n';
        return 1;
    }
    std::cout << "online net p2p: ok\n";
    return 0;
}
