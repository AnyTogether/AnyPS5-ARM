#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceCoredumpRegisterCoredumpHandler(std::uint64_t handler, std::size_t stackSize, std::uint64_t context);
int APS5_VABI sceCoredumpUnregisterCoredumpHandler(void);
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    Require(sceCoredumpRegisterCoredumpHandler(0x1000, 0x4000, 7) == 0);
    Require(sceCoredumpUnregisterCoredumpHandler() == 0);
}
