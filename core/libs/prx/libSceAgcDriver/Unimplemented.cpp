#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

// Submit validation is a development-kit feature: retail drivers answer every validation call with
// this error and neither read nor write their arguments.
constexpr int AgcDriverDebugUnavailable = static_cast<int>(0x8a6c1000u);

extern "C" {

// A retail console reports this status as 1 without inspecting anything.
int APS5_VABI sceAgcDriverGetShaderDebuggingStatus(void) {
    return 1;
}

int APS5_VABI sceAgcDriverRegisterDefaultOwner(uint32_t* owner_handle) {
    (void)owner_handle;
    return static_cast<int>(0x8A6C9018);
}

int APS5_VABI sceAgcDriverSetValidationErrorOutputFrequency(std::uint32_t frequency) {
    (void)frequency;
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverSetSubmitValidationMode(std::uint32_t mode) {
    (void)mode;
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverGetSubmitValidationConfig(void* config) {
    (void)config;
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverGetSubmitValidationMode(std::uint32_t* mode) {
    (void)mode;
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverSetSubmitValidationConfig(const void* config) {
    (void)config;
    return AgcDriverDebugUnavailable;
}

}
