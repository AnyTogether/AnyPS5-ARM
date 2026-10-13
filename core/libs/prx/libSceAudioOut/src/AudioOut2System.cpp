#include <cstdint>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

static constexpr int SCE_AUDIO_OUT2_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80260502);
static constexpr int USER_ID_SYSTEM = 0xFF;
static constexpr std::uint32_t MIN_SUPPORTED_3D_LATENCY = 1;
static constexpr std::uint32_t MAX_SUPPORTED_3D_LATENCY = 2;

extern "C" {

int APS5_VABI sceAudioOut2Initialize(void) {
    return 0;
}

// The latency only selects how far ahead 3D audio is rendered, which the stereo SDL output does not do.
int APS5_VABI sceAudioOut2Set3DLatency(int userId, std::uint32_t latency) {
    if (userId != USER_ID_SYSTEM || latency < MIN_SUPPORTED_3D_LATENCY || latency > MAX_SUPPORTED_3D_LATENCY) return SCE_AUDIO_OUT2_ERROR_INVALID_ARGUMENT;
    return 0;
}

int APS5_VABI sceAudioOut2GetSystemState(AudioOut2SystemState* state) {
    if (!state) return static_cast<int>(0x80260502);
    state->loudness = 0.0f;
    return 0;
}

int APS5_VABI sceAudioOut2SetSystemDebugState(const AudioOut2SystemDebugStateParam* param) {
    (void)param;
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

// Lets system chat audio play alongside the title's output. The host has no chat audio to let through,
// so there is nothing to change.
int APS5_VABI sceAudioOut2EnableChat(void) {
    return 0;
}

}
