#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int SCE_AUDIO_OUT2_ERROR_INVALID_ARGUMENT = static_cast<int>(0x80260502);
constexpr std::uint32_t MASTERING_OUTPUT_RECORDING = 2;
constexpr std::uint32_t MASTERING_STATES_ID_DEFAULT = 1;
constexpr std::uint32_t MASTERING_STATES_ID_V2 = 2;
constexpr std::uint32_t MASTERING_STATES_COMPRESSOR_DEFAULT = 0x01010001;
constexpr std::uint32_t MASTERING_STATES_COMPRESSOR_V2 = 0x01020001;
constexpr std::uint32_t MASTERING_STATES_LIMITER_DEFAULT = 0x01010003;

std::string hex(std::uint32_t value) {
    char text[16];
    std::snprintf(text, sizeof(text), "%x", value);
    return text;
}

template<typename TStates>
void writeIdleStates(AudioOut2MasteringStatesHeader* state, std::uint32_t statesId, std::uint32_t compressorId) {
    TStates states{};
    states.header.states_id = statesId;
    states.compressor.desc = {compressorId, static_cast<std::uint32_t>(sizeof(states.compressor))};
    states.limiter.desc = {MASTERING_STATES_LIMITER_DEFAULT, static_cast<std::uint32_t>(sizeof(states.limiter))};
    std::memcpy(state, &states, sizeof(states));
}

}

extern "C" {

int APS5_VABI sceAudioOut2MasteringInit(uint32_t flags) {
    if (flags != 0) throw std::runtime_error(std::string(__func__) + ": flags 0x" + hex(flags) + " unknown");
    return 0;
}

int APS5_VABI sceAudioOut2MasteringTerm(void) {
    return 0;
}

int APS5_VABI sceAudioOut2MasteringGetState(AudioOut2MasteringStatesHeader* state, uint32_t output, AudioOut2UserHandle user) {
    (void)user;
    if (state == nullptr || output > MASTERING_OUTPUT_RECORDING) return SCE_AUDIO_OUT2_ERROR_INVALID_ARGUMENT;
    switch (state->states_id) {
        case MASTERING_STATES_ID_DEFAULT:
            writeIdleStates<AudioOut2MasteringStates>(state, MASTERING_STATES_ID_DEFAULT, MASTERING_STATES_COMPRESSOR_DEFAULT);
            return 0;
        case MASTERING_STATES_ID_V2:
            writeIdleStates<AudioOut2MasteringStatesV2>(state, MASTERING_STATES_ID_V2, MASTERING_STATES_COMPRESSOR_V2);
            return 0;
        default:
            return SCE_AUDIO_OUT2_ERROR_INVALID_ARGUMENT;
    }
}

// The output has no mastering stage, so valid parameters are accepted without effect.
int APS5_VABI sceAudioOut2MasteringSetParam(const AudioOut2MasteringParamsHeader* param, uint32_t output, uint32_t flags) {
    (void)output;
    (void)flags;
    if (param == nullptr) return static_cast<int>(0x80260502);
    return 0;
}

}
