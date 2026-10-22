#include "ProcessParametersFixture.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceCoredumpRegisterCoredumpHandler(std::uint64_t handler, std::size_t stackSize, std::uint64_t context);
int APS5_VABI sceCoredumpUnregisterCoredumpHandler(void);
}

namespace {
alignas(16) std::array<std::byte, 0x40> process{};
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    const std::uint64_t processSize = process.size();
    const std::uint32_t processMagic = 0x4942524f;
    std::memcpy(process.data(), &processSize, sizeof(processSize));
    std::memcpy(process.data() + 8, &processMagic, sizeof(processMagic));
    Require(ProcessParametersFixture::Install(process.data(), process.size()));
    Require(sceCoredumpRegisterCoredumpHandler(0x1000, 0x4000, 7) == 0);
    Require(sceCoredumpUnregisterCoredumpHandler() == 0);
}
