#include "prx/libSceAgc/Misc/include/Semaphore.hpp"
#include "prx/libSceAgc/Command/include/Packet.hpp"

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <limits>
#include <mutex>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr std::uint64_t semaphoreMemoryAlignment = 0x4000u;
constexpr std::uint64_t semaphoreLabelBytes = 32u;
constexpr std::uint64_t semaphoreCounterBytes = 8u;

std::mutex semaphoreMutex;
std::uint8_t* semaphoreMemory = nullptr;
std::uint64_t semaphoreBytes = 0;

bool hasOnlyZeroLabelTails(const std::uint8_t* memory, std::uint64_t sizeInBytes) {
    for (std::uint64_t label = 0; label < sizeInBytes; label += semaphoreLabelBytes) {
        for (std::uint64_t byte = semaphoreCounterBytes; byte < semaphoreLabelBytes; ++byte) {
            if (memory[label + byte] != 0) return false;
        }
    }
    return true;
}

}

extern "C" {

int APS5_VABI sceAgcSetAmmSemaphoreMemory(void* memory, std::uint64_t sizeInBytes) {
    const auto address = reinterpret_cast<std::uintptr_t>(memory);
    std::lock_guard lock(semaphoreMutex);
    Agc::Command::Require(semaphoreMemory == nullptr, __func__, "the AMM semaphore memory is already registered; the console's error is unknown");
    Agc::Command::Require(memory != nullptr && sizeInBytes != 0, __func__, "null or empty AMM semaphore memory; the console's error is unknown");
    Agc::Command::Require(((address | sizeInBytes) & (semaphoreMemoryAlignment - 1u)) == 0, __func__, "AMM semaphore memory or size is not 16 KiB aligned; the console's error is unknown");
    Agc::Command::Require(sizeInBytes - 1u <= std::numeric_limits<std::uintptr_t>::max() - address, __func__, "AMM semaphore memory wraps the address space");
    auto* labels = static_cast<std::uint8_t*>(memory);
    Agc::Command::Require(hasOnlyZeroLabelTails(labels, sizeInBytes), __func__, "AMM semaphore labels hold data past their first 8 bytes; whether registration clears it is unknown");
    for (std::uint64_t label = 0; label < sizeInBytes; label += semaphoreLabelBytes) {
        std::memset(labels + label, 0, semaphoreCounterBytes);
    }
    semaphoreMemory = labels;
    semaphoreBytes = sizeInBytes;
    return 0;
}

int APS5_VABI sceAgcGetSemaphoreLabel(std::uint32_t index, void** label) {
    std::lock_guard lock(semaphoreMutex);
    Agc::Command::Require(semaphoreMemory != nullptr, __func__, "no AMM semaphore memory is registered; the console's error is unknown");
    Agc::Command::Require(index < semaphoreBytes / semaphoreLabelBytes, __func__, "the semaphore label lies outside the AMM semaphore memory; the console's error is unknown");
    Agc::Command::Require(label != nullptr, __func__, "null semaphore label output; the console's error is unknown");
    *label = semaphoreMemory + static_cast<std::uint64_t>(index) * semaphoreLabelBytes;
    return 0;
}

}
