#include "prx/libSceAgc/Misc/include/Platform.hpp"
#include "prx/libSceAgc/Command/include/Packet.hpp"

#include <atomic>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <mutex>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int AGC_ERROR_INVALID_ALIGNMENT = static_cast<int>(0x8a6c0002u);
constexpr int AGC_ERROR_INVALID_VALUE = static_cast<int>(0x8a6c000bu);
constexpr int AGC_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x8a6c0048u);
constexpr int AGC_ERROR_NOT_INITIALIZED = static_cast<int>(0x8a6c0049u);

constexpr std::uint64_t AmmSemaphoreAlignment = 0x4000;
constexpr std::uint64_t AmmSemaphoreLabelSize = 32;

std::atomic<std::uint32_t> shaderInstrumentation{0};

std::mutex ammSemaphoreLock;
std::uint8_t* ammSemaphoreMemory = nullptr;
std::uint64_t ammSemaphoreSize = 0;

}

extern "C" {

int APS5_VABI sceAgcGetIsTrinityMode(bool* isTrinityMode) {
    Agc::Command::CheckAddress(reinterpret_cast<std::uintptr_t>(isTrinityMode), alignof(bool), __func__);
    *isTrinityMode = false;
    return 0;
}

// The flags are kept verbatim: no shader is instrumented, and the system adds no bits of its own.
std::uint32_t APS5_VABI sceAgcGetShaderInstrumentation(void) {
    return shaderInstrumentation.load(std::memory_order_relaxed);
}

int APS5_VABI sceAgcSetShaderInstrumentation(std::uint32_t flags) {
    shaderInstrumentation.store(flags, std::memory_order_relaxed);
    return 0;
}

// A retail console has no debugger to raise the exception to, so the request is only reported.
int APS5_VABI sceAgcDebugRaiseException(std::uint32_t exceptionId) {
    std::fprintf(stderr, "[agc] sceAgcDebugRaiseException(0x%08x) ignored: no GPU debugger is attached\n", exceptionId);
    return 0;
}

// The AMM semaphore memory is set once per process and split into 32-byte labels.
int APS5_VABI sceAgcSetAmmSemaphoreMemory(void* memory, std::uint64_t sizeInBytes) {
    std::lock_guard guard(ammSemaphoreLock);
    if (ammSemaphoreSize != 0) return AGC_ERROR_ALREADY_INITIALIZED;
    const auto address = reinterpret_cast<std::uintptr_t>(memory);
    if (memory == nullptr || sizeInBytes == 0 || ((address | sizeInBytes) & (AmmSemaphoreAlignment - 1)) != 0) return AGC_ERROR_INVALID_ALIGNMENT;
    std::memset(memory, 0, static_cast<std::size_t>(sizeInBytes));
    ammSemaphoreMemory = static_cast<std::uint8_t*>(memory);
    ammSemaphoreSize = sizeInBytes;
    return 0;
}

int APS5_VABI sceAgcGetSemaphoreLabel(std::uint32_t index, void** label) {
    std::lock_guard guard(ammSemaphoreLock);
    if (ammSemaphoreSize == 0) return AGC_ERROR_NOT_INITIALIZED;
    if ((static_cast<std::uint64_t>(index) + 1) * AmmSemaphoreLabelSize > ammSemaphoreSize) return AGC_ERROR_INVALID_VALUE;
    if (label == nullptr) return AGC_ERROR_INVALID_ALIGNMENT;
    *label = ammSemaphoreMemory + static_cast<std::uint64_t>(index) * AmmSemaphoreLabelSize;
    return 0;
}

}
