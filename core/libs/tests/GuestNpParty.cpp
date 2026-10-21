#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" int APS5_VABI sceNpPartyGetState(std::uint16_t* state);

int main() {
    std::uint16_t states[3];
    std::memset(states, 0xa5, sizeof(states));
    if (sceNpPartyGetState(nullptr) != static_cast<int>(0x80552504u)) {
        std::fprintf(stderr, "a null state was not refused with INVALID_ARGUMENT\n");
        return 1;
    }
    if (sceNpPartyGetState(&states[1]) != 0 || states[1] != 2) {
        std::fprintf(stderr, "the state is not NOT_IN_PARTY\n");
        return 1;
    }
    if (states[0] != 0xa5a5 || states[2] != 0xa5a5) {
        std::fprintf(stderr, "sceNpPartyGetState wrote past its 16-bit state\n");
        return 1;
    }
    std::puts("NpParty state tests passed");
    return 0;
}
