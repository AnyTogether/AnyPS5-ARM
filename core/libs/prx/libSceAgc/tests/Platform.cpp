#include "prx/libc/include/general/VabiMacros.hpp"
#include "prx/libc/include/Shutdown.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>
#include <cstdio>
#include <stdexcept>

extern "C" int APS5_VABI sceAgcGetIsTrinityMode(bool* isTrinityMode);
extern "C" std::uint32_t APS5_VABI sceAgcGetShaderInstrumentation(void);
extern "C" int APS5_VABI sceAgcSetShaderInstrumentation(std::uint32_t flags);
extern "C" int APS5_VABI sceAgcDebugRaiseException(std::uint32_t exceptionId);
extern "C" int APS5_VABI sceAgcSetAmmSemaphoreMemory(void* memory, std::uint64_t sizeInBytes);
extern "C" int APS5_VABI sceAgcGetSemaphoreLabel(std::uint32_t index, void** label);

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

constexpr int InvalidAlignment = static_cast<int>(0x8a6c0002u);
constexpr int InvalidValue = static_cast<int>(0x8a6c000bu);
constexpr int AlreadyInitialized = static_cast<int>(0x8a6c0048u);
constexpr int NotInitialized = static_cast<int>(0x8a6c0049u);

void testAmmSemaphores() {
    void* label = nullptr;
    check(sceAgcGetSemaphoreLabel(0, &label) == NotInitialized && label == nullptr, "semaphore label returned before the memory was set");
    std::vector<std::uint8_t> storage(0xc000);
    const auto base = (reinterpret_cast<std::uintptr_t>(storage.data()) + 0x3fff) & ~std::uintptr_t{0x3fff};
    auto* const memory = reinterpret_cast<std::uint8_t*>(base);
    std::fill_n(memory, 0x8000, std::uint8_t{0xa5});
    check(sceAgcSetAmmSemaphoreMemory(nullptr, 0x4000) == InvalidAlignment, "null semaphore memory accepted");
    check(sceAgcSetAmmSemaphoreMemory(memory, 0) == InvalidAlignment, "empty semaphore memory accepted");
    check(sceAgcSetAmmSemaphoreMemory(memory + 0x100, 0x4000) == InvalidAlignment, "misaligned semaphore memory accepted");
    check(sceAgcSetAmmSemaphoreMemory(memory, 0x4100) == InvalidAlignment, "misaligned semaphore size accepted");
    check(memory[0] == 0xa5, "rejected semaphore memory was cleared");
    check(sceAgcSetAmmSemaphoreMemory(memory, 0x4000) == 0, "setting semaphore memory failed");
    check(memory[0] == 0 && memory[0x3fff] == 0 && memory[0x4000] == 0xa5, "semaphore memory was not cleared exactly");
    check(sceAgcSetAmmSemaphoreMemory(memory + 0x4000, 0x4000) == AlreadyInitialized, "semaphore memory set twice");
    check(sceAgcGetSemaphoreLabel(0, &label) == 0 && label == memory, "first semaphore label mismatch");
    check(sceAgcGetSemaphoreLabel(511, &label) == 0 && label == memory + 511 * 32, "last semaphore label mismatch");
    label = nullptr;
    check(sceAgcGetSemaphoreLabel(512, &label) == InvalidValue && label == nullptr, "semaphore label past the memory returned");
    check(sceAgcGetSemaphoreLabel(0xffffffffu, &label) == InvalidValue, "wrapping semaphore label index accepted");
    check(sceAgcGetSemaphoreLabel(1, nullptr) == InvalidAlignment, "null semaphore label output accepted");
}

}

int main() {
    try {
        testTrinityMode();
        testRejections();
        testShaderInstrumentation();
        testDebugRaiseException();
        testAmmSemaphores();
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
