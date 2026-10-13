#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#else
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#ifdef __linux__
#include <netpacket/packet.h>
#endif
#ifdef __APPLE__
#include <net/route.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <cerrno>
#include <vector>
#endif
#endif
#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"
#include <fstream>
#include <mutex>
#include <stdexcept>
#include <string>
#ifdef _WIN32
#include <vector>
#endif

// Network-control state reflects host interface addressing, not PSN sign-in status.
static constexpr int SCE_NET_CTL_ERROR_CALLBACK_MAX = static_cast<int>(0x80412103);
static constexpr int SCE_NET_CTL_ERROR_INVALID_ID = static_cast<int>(0x80412105);
static constexpr int SCE_NET_CTL_ERROR_INVALID_ADDR = static_cast<int>(0x80412107);
static constexpr int SCE_NET_CTL_ERROR_NOT_CONNECTED = static_cast<int>(0x80412108);
static constexpr int NET_CTL_STATE_DISCONNECTED = 0;
static constexpr int NET_CTL_STATE_IPOBTAINED = 3;
static constexpr int MAX_CALLBACKS = 8;

static std::mutex g_callbackLock;
static NetCtlCallback g_callbacks[MAX_CALLBACKS] = {};

static bool HostHasAddress(int family) {
#ifdef _WIN32
    static const int socket_status = [] {
        WSADATA data{};
        return WSAStartup(MAKEWORD(2, 2), &data);
    }();
    if (socket_status != 0) return false;
    ULONG size = 0;
    const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
    if (GetAdaptersAddresses(family, flags, nullptr, nullptr, &size) != ERROR_BUFFER_OVERFLOW) return false;
    std::vector<std::uint8_t> storage(size);
    auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(storage.data());
    if (GetAdaptersAddresses(family, flags, nullptr, adapters, &size) != NO_ERROR) return false;
    for (auto* adapter = adapters; adapter; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp || adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
        for (auto* address = adapter->FirstUnicastAddress; address; address = address->Next) {
            if (!address->Address.lpSockaddr) continue;
            if (address->Address.lpSockaddr->sa_family == AF_INET) {
                const auto* v4 = reinterpret_cast<const sockaddr_in*>(address->Address.lpSockaddr);
                const auto host = ntohl(v4->sin_addr.s_addr);
                if (host != 0 && (host >> 24) != 127) return true;
            } else if (address->Address.lpSockaddr->sa_family == AF_INET6) {
                const auto* v6 = reinterpret_cast<const sockaddr_in6*>(address->Address.lpSockaddr);
                if (!IN6_IS_ADDR_UNSPECIFIED(&v6->sin6_addr) && !IN6_IS_ADDR_LOOPBACK(&v6->sin6_addr)) return true;
            }
        }
    }
    return false;
#else
    ifaddrs* interfaces = nullptr;
    if (getifaddrs(&interfaces) != 0) return false;
    bool found = false;
    for (auto* item = interfaces; item && !found; item = item->ifa_next) {
        if (!item->ifa_addr || !(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK)) continue;
        const int address_family = item->ifa_addr->sa_family;
        if ((family == AF_UNSPEC || family == address_family) && address_family == AF_INET) {
            const auto* v4 = reinterpret_cast<const sockaddr_in*>(item->ifa_addr);
            const auto host = ntohl(v4->sin_addr.s_addr);
            found = host != 0 && (host >> 24) != 127;
        } else if ((family == AF_UNSPEC || family == address_family) && address_family == AF_INET6) {
            const auto* v6 = reinterpret_cast<const sockaddr_in6*>(item->ifa_addr);
            found = !IN6_IS_ADDR_UNSPECIFIED(&v6->sin6_addr) && !IN6_IS_ADDR_LOOPBACK(&v6->sin6_addr);
        }
    }
    freeifaddrs(interfaces);
    return found;
#endif
}

extern "C" std::uint64_t NetCtlReadByteCounter_nid_no_patch(const char* path) {
    std::ifstream file(path);
    std::uint64_t value = 0;
    if (!(file >> value)) throw std::runtime_error(std::string("sceNetCtlGetIfStat: no byte counter in ") + path);
    return value;
}

static void HostTraffic(std::uint64_t& sent, std::uint64_t& received) {
    sent = 0;
    received = 0;
#ifdef _WIN32
    MIB_IF_TABLE2* table = nullptr;
    if (GetIfTable2(&table) != NO_ERROR) throw std::runtime_error("sceNetCtlGetIfStat: the host interface table is unavailable");
    for (ULONG index = 0; index < table->NumEntries; ++index) {
        const auto& row = table->Table[index];
        if (row.OperStatus != IfOperStatusUp || row.Type == IF_TYPE_SOFTWARE_LOOPBACK || !row.InterfaceAndOperStatusFlags.HardwareInterface) continue;
        sent += row.OutOctets;
        received += row.InOctets;
    }
    FreeMibTable(table);
#elif defined(__linux__)
    ifaddrs* interfaces = nullptr;
    if (getifaddrs(&interfaces) != 0) throw std::runtime_error("sceNetCtlGetIfStat: the host interface list is unavailable");
    for (auto* item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_PACKET) continue;
        if (!(item->ifa_flags & IFF_UP) || (item->ifa_flags & IFF_LOOPBACK)) continue;
        const std::string statistics = std::string("/sys/class/net/") + item->ifa_name + "/statistics/";
        sent += NetCtlReadByteCounter_nid_no_patch((statistics + "tx_bytes").c_str());
        received += NetCtlReadByteCounter_nid_no_patch((statistics + "rx_bytes").c_str());
    }
    freeifaddrs(interfaces);
#elif defined(__APPLE__)
    // NET_RT_IFLIST2 reports each interface with 64-bit byte counters (getifaddrs' if_data wraps at 4 GiB).
    int request[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    std::vector<char> table;
    for (;;) {
        std::size_t size = 0;
        if (::sysctl(request, 6, nullptr, &size, nullptr, 0) != 0)
            throw std::runtime_error("sceNetCtlGetIfStat: the host interface table size is unavailable, errno=" + std::to_string(errno));
        table.resize(size);
        if (::sysctl(request, 6, table.data(), &size, nullptr, 0) == 0) {
            table.resize(size);
            break;
        }
        if (errno != ENOMEM)
            throw std::runtime_error("sceNetCtlGetIfStat: the host interface table is unavailable, errno=" + std::to_string(errno));
    }
    for (std::size_t offset = 0; offset < table.size();) {
        const auto* header = reinterpret_cast<const if_msghdr*>(table.data() + offset);
        if (header->ifm_msglen == 0 || offset + header->ifm_msglen > table.size())
            throw std::runtime_error("sceNetCtlGetIfStat: the host interface table is malformed");
        offset += header->ifm_msglen;
        if (header->ifm_type != RTM_IFINFO2) continue;
        const auto* item = reinterpret_cast<const if_msghdr2*>(header);
        if (!(item->ifm_flags & IFF_UP) || (item->ifm_flags & IFF_LOOPBACK)) continue;
        sent += item->ifm_data.ifi_obytes;
        received += item->ifm_data.ifi_ibytes;
    }
#else
    throw std::runtime_error("sceNetCtlGetIfStat: host interface byte counters are not implemented on this platform");
#endif
}

extern "C" {

int APS5_VABI sceNetCtlCheckCallback(void) {
    return 0;
}

int APS5_VABI sceNetCtlGetIfStat(NetCtlIfStat* stat) {
    if (!stat) return SCE_NET_CTL_ERROR_INVALID_ADDR;
    if (!HostHasAddress(AF_UNSPEC)) return SCE_NET_CTL_ERROR_NOT_CONNECTED;
    *stat = {};
    HostTraffic(stat->tx_bytes, stat->rx_bytes);
    return 0;
}

int APS5_VABI sceNetCtlGetInfo(int code, NetCtlInfo* info) {
    (void)code;
    (void)info;
    return SCE_NET_CTL_ERROR_NOT_CONNECTED;
}

int APS5_VABI sceNetCtlGetNatInfo(NetCtlNatInfo* nat_info) {
    (void)nat_info;
    return SCE_NET_CTL_ERROR_NOT_CONNECTED;
}

int APS5_VABI sceNetCtlGetResult(int event_type, int* error_code) {
    (void)event_type;
    if (!error_code) return SCE_NET_CTL_ERROR_INVALID_ADDR;
    *error_code = 0;
    return 0;
}

int APS5_VABI sceNetCtlGetState(int* state) {
    if (!state) return SCE_NET_CTL_ERROR_INVALID_ADDR;
    *state = HostHasAddress(AF_UNSPEC) ? NET_CTL_STATE_IPOBTAINED : NET_CTL_STATE_DISCONNECTED;
    return 0;
}

int APS5_VABI sceNetCtlGetStateV6(int* state) {
    if (!state) return SCE_NET_CTL_ERROR_INVALID_ADDR;
    *state = HostHasAddress(AF_INET6) ? NET_CTL_STATE_IPOBTAINED : NET_CTL_STATE_DISCONNECTED;
    return 0;
}

int APS5_VABI sceNetCtlInit(void) {
    return 0;
}

int APS5_VABI sceNetCtlRegisterCallback(NetCtlCallback func, void* arg, int* cid) {
    if (!func || !cid) return SCE_NET_CTL_ERROR_INVALID_ADDR;
    std::lock_guard lock(g_callbackLock);
    for (int index = 0; index < MAX_CALLBACKS; ++index) {
        if (!g_callbacks[index]) {
            g_callbacks[index] = func;
            *cid = index;
            return 0;
        }
    }
    return SCE_NET_CTL_ERROR_CALLBACK_MAX;
}

void APS5_VABI sceNetCtlTerm(void) {
}

int APS5_VABI sceNetCtlUnregisterCallback(int cid) {
    if (cid < 0 || cid >= MAX_CALLBACKS) return SCE_NET_CTL_ERROR_INVALID_ID;
    std::lock_guard lock(g_callbackLock);
    g_callbacks[cid] = nullptr;
    return 0;
}

}
