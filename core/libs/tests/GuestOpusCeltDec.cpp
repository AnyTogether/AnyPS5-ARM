#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <functional>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceOpusCeltDecInitialize(std::uint32_t*);
int APS5_VABI sceOpusCeltDecTerminate(std::uint32_t*);
int APS5_VABI sceOpusCeltDecGetSize(int);
int APS5_VABI sceOpusCeltDecCreateEx(std::uint32_t*, void*, int, int);
int APS5_VABI sceOpusCeltDecDecode(void*, const std::uint8_t*, int, std::int16_t*, int);
int APS5_VABI sceOpusCeltDecDestroy(void*);
}

static int failures = 0;

static void RequireNotImplemented(const char* name, const std::function<void()>& call) {
    try {
        call();
    } catch (const std::runtime_error& error) {
        if (std::string(error.what()) == std::string(name) + " not implemented") return;
        std::fprintf(stderr, "%s threw: %s\n", name, error.what());
        ++failures;
        return;
    }
    std::fprintf(stderr, "%s returned instead of reporting that it is not implemented\n", name);
    ++failures;
}

int main() {
    std::uint32_t context = 0;
    std::uint8_t state[64] = {};
    std::int16_t pcm[16] = {};
    const std::uint8_t packet[] = {0xFC, 0x00};
    RequireNotImplemented("sceOpusCeltDecInitialize", [&] { sceOpusCeltDecInitialize(&context); });
    RequireNotImplemented("sceOpusCeltDecTerminate", [&] { sceOpusCeltDecTerminate(&context); });
    RequireNotImplemented("sceOpusCeltDecGetSize", [] { sceOpusCeltDecGetSize(2); });
    RequireNotImplemented("sceOpusCeltDecCreateEx", [&] { sceOpusCeltDecCreateEx(&context, state, 48000, 2); });
    RequireNotImplemented("sceOpusCeltDecDecode", [&] { sceOpusCeltDecDecode(state, packet, sizeof(packet), pcm, sizeof(pcm)); });
    RequireNotImplemented("sceOpusCeltDecDestroy", [&] { sceOpusCeltDecDestroy(state); });
    return failures == 0 ? 0 : 1;
}
