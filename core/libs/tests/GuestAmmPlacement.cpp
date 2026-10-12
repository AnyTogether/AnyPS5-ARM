#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/GuestArena.hpp"
#include <cstdint>
#include <cstdio>
#include <exception>
#include <stdexcept>

extern "C" {
int APS5_VABI sceAmprAmmGetVirtualAddressRanges(std::uint64_t*, std::uint64_t*, std::uint64_t*, std::uint64_t*);
}

static void Require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

int main() {
    try {
        std::uintptr_t arenaBase = 0;
        std::size_t arenaBytes = 0;
        GuestArena::GuestArenaRange_nid_postfix(&arenaBase, &arenaBytes);
        Require(arenaBase != 0 && arenaBytes != 0, "the guest arena is unavailable");
        const std::uint64_t arenaEnd = arenaBase + arenaBytes;
        constexpr std::uint64_t occupied = 4ull << 20;
        GuestArena::GuestArenaMarkUsed_nid_postfix(reinterpret_cast<void*>(arenaEnd - occupied), occupied);

        std::uint64_t start = 0;
        std::uint64_t end = 0;
        std::uint64_t multimapStart = 0;
        std::uint64_t multimapEnd = 0;
        Require(sceAmprAmmGetVirtualAddressRanges(&start, &end, &multimapStart, &multimapEnd) == 0, "AMM ranges were not reported");
        Require(end == multimapStart && multimapEnd - start == 64ull << 30, "AMM ranges are not two adjacent 32 GiB ranges");
        Require(start >= arenaBase && multimapEnd <= arenaEnd - occupied, "AMM ranges overlap the used top of the guest arena");
        Require(GuestArena::GuestArenaHighestFree_nid_no_patch(64ull << 30, 2ull << 20) < start, "AMM ranges are not at the top of the free guest arena");
        std::puts("AMM ranges placed below the used top of the guest arena");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
