#include "SceTypes.hpp"
#include <array>
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceAgcDriverGetShaderDebuggingStatus();
int APS5_VABI sceAgcDriverSetValidationErrorOutputFrequency(std::uint32_t);
int APS5_VABI sceAgcDriverSetSubmitValidationMode(std::uint32_t);
int APS5_VABI sceAgcDriverGetSubmitValidationMode(std::uint32_t*);
int APS5_VABI sceAgcDriverSetSubmitValidationConfig(const void*);
int APS5_VABI sceAgcDriverGetSubmitValidationConfig(void*);
}

static constexpr int DebugUnavailable = static_cast<int>(0x8A6C1000);
static void Require(bool value) { if (!value) std::abort(); }

int main() {
    Require(sceAgcDriverGetShaderDebuggingStatus() == 1);

    Require(sceAgcDriverSetValidationErrorOutputFrequency(0u) == DebugUnavailable);
    Require(sceAgcDriverSetValidationErrorOutputFrequency(60u) == DebugUnavailable);
    Require(sceAgcDriverSetSubmitValidationMode(0u) == DebugUnavailable);
    Require(sceAgcDriverSetSubmitValidationMode(1u) == DebugUnavailable);

    std::uint32_t mode = 0xA5A5A5A5u;
    Require(sceAgcDriverGetSubmitValidationMode(&mode) == DebugUnavailable);
    Require(sceAgcDriverGetSubmitValidationMode(nullptr) == DebugUnavailable);
    Require(mode == 0xA5A5A5A5u);

    std::array<std::uint8_t, 64> config{};
    config.fill(0x5A);
    Require(sceAgcDriverSetSubmitValidationConfig(config.data()) == DebugUnavailable);
    Require(sceAgcDriverSetSubmitValidationConfig(nullptr) == DebugUnavailable);
    Require(sceAgcDriverGetSubmitValidationConfig(config.data()) == DebugUnavailable);
    Require(sceAgcDriverGetSubmitValidationConfig(nullptr) == DebugUnavailable);
    for (const std::uint8_t byte : config) Require(byte == 0x5A);
}
