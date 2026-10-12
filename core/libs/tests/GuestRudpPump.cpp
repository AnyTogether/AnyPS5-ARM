#include "prx/libc/include/general/VabiMacros.hpp"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceRudpInit_nid_postfix(void*, int);
int APS5_VABI sceRudpTerminate();
int APS5_VABI sceRudpProcessEvents();
int APS5_VABI sceRudpNetFlush();
int APS5_VABI sceRudpGetMaxSegmentSize();
int APS5_VABI sceRudpNetReceived();
}

static void Require(bool value, int line) {
    if (!value) {
        std::fprintf(stderr, "rudp check failed at line %d\n", line);
        std::abort();
    }
}
#define CHECK(value) Require((value), __LINE__)

int main() {
    constexpr int notInitialized = static_cast<int>(0x80770001);
    CHECK(sceRudpProcessEvents() == notInitialized);
    CHECK(sceRudpNetFlush() == notInitialized);

    alignas(8) static unsigned char pool[0xC58];
    CHECK(sceRudpInit_nid_postfix(pool, sizeof(pool)) == 0);
    CHECK(sceRudpProcessEvents() == 0);
    CHECK(sceRudpNetFlush() == 0);
    CHECK(sceRudpTerminate() == 0);

    for (const auto call : {&sceRudpNetReceived, &sceRudpGetMaxSegmentSize}) {
        bool threw = false;
        try {
            call();
        } catch (const std::runtime_error&) {
            threw = true;
        }
        CHECK(threw);
    }
    return 0;
}
