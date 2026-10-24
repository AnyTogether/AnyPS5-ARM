#ifndef CORE_LIBS_PRX_LIBSCENET_VIRTUALNET_HPP
#define CORE_LIBS_PRX_LIBSCENET_VIRTUALNET_HPP

#include "prx/libSceNetCtl/include/OnlineWire.hpp"
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

struct sockaddr_storage;

namespace VirtualNet {

constexpr std::size_t HeaderSize = 12;
constexpr std::uint32_t HeaderMagic = 0x314E5641u;

struct Source {
    std::uint32_t address = 0;
    std::uint16_t port = 0;
    std::uint16_t vport = 0;
};

bool Enabled();
std::optional<std::uint32_t> VirtualDestination(const void* guestAddress, std::uint32_t length);
std::uint16_t GuestVport(const void* guestAddress, std::uint32_t length);
std::uint32_t OwnAddress();
bool Register(Online::Wire::DatagramKind kind, std::uint16_t port, std::uint16_t vport, std::uint16_t nativePort, int descriptor);
void Forget(int descriptor);
bool Send(const Online::Wire::Datagram& datagram);
bool FromRelay(const sockaddr_storage& peer);
std::optional<Source> ReadHeader(std::span<const std::uint8_t> bytes);
void WriteGuestAddress(const Source& source, void* address, std::uint32_t* length);

}

#endif
