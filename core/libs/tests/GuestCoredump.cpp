#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceCoredumpRegisterCoredumpHandler(std::uint64_t handler, std::size_t stackSize, std::uint64_t context);
int APS5_VABI sceCoredumpUnregisterCoredumpHandler(void);
int APS5_VABI sceCoredumpAttachUserFile(std::uint32_t userValue, const char* path);
int APS5_VABI sceCoredumpAttachMemoryRegionAsUserFile(std::uint32_t userValue, const void* memory, std::size_t size, const char* name);
int APS5_VABI sceCoredumpAttachMemoryRegion(std::uint32_t userValue, const void* memory, std::size_t size);
int APS5_VABI sceCoredumpAttachUserMemoryFile(std::uint32_t userValue, const void* memory, std::size_t size);
void APS5_VABI sceCoredumpDebugTextOut(const char* text, int length);
}

static constexpr int Einval = static_cast<int>(0x80020016);

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    std::array<std::uint8_t, 64> region{};
    region.fill(0x5a);
    Require(sceCoredumpAttachUserFile(1, "/app0/log.txt") == 0);
    Require(sceCoredumpAttachUserFile(1, nullptr) == Einval);
    Require(sceCoredumpAttachMemoryRegionAsUserFile(2, region.data(), region.size(), "state.bin") == 0);
    Require(sceCoredumpAttachMemoryRegionAsUserFile(2, nullptr, region.size(), "state.bin") == Einval);
    Require(sceCoredumpAttachMemoryRegionAsUserFile(2, region.data(), region.size(), nullptr) == Einval);
    Require(sceCoredumpAttachMemoryRegion(3, region.data(), region.size()) == 0);
    Require(sceCoredumpAttachMemoryRegion(3, nullptr, region.size()) == Einval);
    Require(sceCoredumpAttachUserMemoryFile(0x80000000u, region.data(), region.size()) == 0);
    Require(sceCoredumpAttachUserMemoryFile(4, nullptr, 0) == Einval);
    Require(region[0] == 0x5a && region[63] == 0x5a);
    sceCoredumpDebugTextOut("coredump text", 8);
    sceCoredumpDebugTextOut(nullptr, 4);
    sceCoredumpDebugTextOut("ignored", -1);
    Require(sceCoredumpRegisterCoredumpHandler(0x1000, 0x4000, 7) == 0);
    Require(sceCoredumpAttachMemoryRegion(5, region.data(), region.size()) == 0);
    Require(sceCoredumpUnregisterCoredumpHandler() == 0);
}
