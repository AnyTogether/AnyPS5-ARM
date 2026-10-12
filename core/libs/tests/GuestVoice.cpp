#include "SceTypes.hpp"
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>

extern "C" {
int APS5_VABI sceVoiceInit(VoiceInitParam*, std::int32_t);
int APS5_VABI sceVoiceEnd_nid_postfix(void);
int APS5_VABI sceVoiceCreatePort(std::uint32_t*, const VoicePortParam*);
int APS5_VABI sceVoiceDeletePort(std::uint32_t);
int APS5_VABI sceVoiceConnectIPortToOPort(std::uint32_t, std::uint32_t);
int APS5_VABI sceVoiceDisconnectIPortFromOPort(std::uint32_t, std::uint32_t);
int APS5_VABI sceVoiceResetPort(std::uint32_t);
int APS5_VABI sceVoiceSetVolume(std::uint32_t, float);
int APS5_VABI sceVoiceGetVolume(std::uint32_t, float*);
int APS5_VABI sceVoiceSetMuteFlag(std::uint32_t, bool);
int APS5_VABI sceVoiceGetMuteFlag(std::uint32_t, bool*);
int APS5_VABI sceVoiceGetBitRate(std::uint32_t, std::uint32_t*);
int APS5_VABI sceVoiceGetPortInfo(std::uint32_t, VoicePortInfo*);
int APS5_VABI sceVoiceWriteToIPort(std::uint32_t, const void*, std::uint32_t*, std::int16_t);
int APS5_VABI sceVoiceReadFromOPort(std::uint32_t, void*, std::uint32_t*);
}

namespace {

constexpr std::int32_t portInPcm = 1;
constexpr std::int32_t portInVoice = 2;
constexpr std::int32_t portOutPcm = 3;
constexpr std::int32_t portStateReady = 1;
constexpr std::int32_t bitrate = 16000;

void Require(bool value) { if (!value) std::abort(); }

bool ResetThrows(std::uint32_t portId) {
    try {
        static_cast<void>(sceVoiceResetPort(portId));
    } catch (const std::logic_error&) {
        return true;
    }
    return false;
}

VoicePortParam PortParam(std::int32_t type) {
    VoicePortParam param{};
    param.port_type = type;
    param.volume = 1.0f;
    return param;
}

}

int main() {
    Require(ResetThrows(0));
    VoiceInitParam initParam{};
    Require(sceVoiceInit(&initParam, 0x100) == 0);
    Require(ResetThrows(0));

    std::uint32_t input = 0xffffffffu;
    std::uint32_t output = 0xffffffffu;
    std::uint32_t encoded = 0xffffffffu;
    VoicePortParam inputParam = PortParam(portInPcm);
    inputParam.pcmaudio.buffer_size = 3200;
    inputParam.pcmaudio.sample_rate = 16000;
    Require(sceVoiceCreatePort(&input, &inputParam) == 0);
    const VoicePortParam outputParam = PortParam(portOutPcm);
    Require(sceVoiceCreatePort(&output, &outputParam) == 0);
    VoicePortParam encodedParam = PortParam(portInVoice);
    encodedParam.voice.bitrate = bitrate;
    Require(sceVoiceCreatePort(&encoded, &encodedParam) == 0);
    Require(sceVoiceConnectIPortToOPort(input, output) == 0);
    Require(sceVoiceSetVolume(input, 0.25f) == 0);
    Require(sceVoiceSetMuteFlag(input, true) == 0);

    std::int16_t samples[320]{};
    std::uint32_t size = sizeof(samples);
    Require(sceVoiceWriteToIPort(input, samples, &size, 0) == 0);
    Require(size == sizeof(samples));
    for (std::uint32_t port : {input, output, encoded}) Require(sceVoiceResetPort(port) == 0);
    Require(sceVoiceResetPort(input) == 0);

    float volume = -1.0f;
    Require(sceVoiceGetVolume(input, &volume) == 0);
    Require(volume == 0.25f);
    bool muted = false;
    Require(sceVoiceGetMuteFlag(input, &muted) == 0);
    Require(muted);
    std::uint32_t readBitrate = 0;
    Require(sceVoiceGetBitRate(encoded, &readBitrate) == 0);
    Require(readBitrate == static_cast<std::uint32_t>(bitrate));
    VoicePortInfo info{};
    Require(sceVoiceGetPortInfo(input, &info) == 0);
    Require(info.port_type == portInPcm && info.state == portStateReady);
    Require(sceVoiceGetPortInfo(output, &info) == 0);
    Require(info.port_type == portOutPcm && info.state == portStateReady);
    size = sizeof(samples);
    Require(sceVoiceReadFromOPort(output, samples, &size) == 0);
    Require(size == 0);
    Require(sceVoiceDisconnectIPortFromOPort(input, output) == 0);

    Require(ResetThrows(input + output + encoded + 1));
    Require(sceVoiceDeletePort(encoded) == 0);
    Require(ResetThrows(encoded));
    Require(sceVoiceResetPort(input) == 0);
    Require(sceVoiceEnd_nid_postfix() == 0);
    Require(ResetThrows(input));
    Require(ResetThrows(output));
    return 0;
}
