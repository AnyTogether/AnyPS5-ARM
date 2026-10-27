#include "prx/libSceAgc/Misc/include/Platform.hpp"
#include "prx/libSceAgc/include/Agc.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/Shutdown.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>
#include <cstdio>
#include <stdexcept>

extern "C" std::uint32_t APS5_VABI sceAgcGetShaderInstrumentation(void);
extern "C" int APS5_VABI sceAgcSetShaderInstrumentation(std::uint32_t flags);
extern "C" int APS5_VABI sceAgcDebugRaiseException(std::uint32_t exceptionId);
namespace {

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename TAction>
void expectFailure(TAction action) {
    try {
        action();
    } catch (const std::runtime_error& error) {
        check(error.what()[0] != '\0', "empty exception message");
        return;
    }
    throw std::runtime_error("expected an exception");
}

void testTrinityMode() {
    std::array<bool, 3> flags{true, true, true};
    check(sceAgcGetIsTrinityMode(&flags[1]) == 0, "Trinity mode query did not return 0");
    check(!flags[1], "base PS5 GPU reported as Trinity");
    check(flags[0] && flags[2], "Trinity mode query wrote past its one-byte flag");
}

void testRejections() {
    expectFailure([] { sceAgcGetIsTrinityMode(nullptr); });
}

void testShaderInstrumentation() {
    check(sceAgcGetShaderInstrumentation() == 0, "shader instrumentation is not off by default");
    check(sceAgcSetShaderInstrumentation(0x8000000du) == 0, "setting shader instrumentation failed");
    check(sceAgcGetShaderInstrumentation() == 0x8000000du, "shader instrumentation flags were not kept verbatim");
    check(sceAgcSetShaderInstrumentation(0) == 0 && sceAgcGetShaderInstrumentation() == 0, "shader instrumentation was not cleared");
}

void testDebugRaiseException() {
    check(sceAgcDebugRaiseException(0x1234) == 0, "debug exception request did not return 0");
}

void testExportLinked() {
    auto* volatile linked = &sceAgcSuspendPointAndCheckStatus;
    check(linked != nullptr, "sceAgcSuspendPointAndCheckStatus is not linked");
}

}

int main() {
    try {
        testTrinityMode();
        testRejections();
        testShaderInstrumentation();
        testDebugRaiseException();
        testExportLinked();
        LibcRunShutdown_nid_postfix();
        std::puts("AGC platform tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        try { LibcRunShutdown_nid_postfix(); }
        catch (const std::exception& shutdown) { std::fprintf(stderr, "shutdown: %s\n", shutdown.what()); }
        return 1;
    }
}
