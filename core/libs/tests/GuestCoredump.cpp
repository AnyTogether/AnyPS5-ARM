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
    Require(region[0] == 0x5a && region[63] == 0x5a);
    Require(sceCoredumpRegisterCoredumpHandler(0x1000, 0x4000, 7) == 0);
    Require(sceCoredumpUnregisterCoredumpHandler() == 0);
}
