#include "SceTypes.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string_view>

extern "C" {
int APS5_VABI sceVoiceInit(VoiceInitParam*, int32_t);
int APS5_VABI sceVoiceEnd_nid_postfix(void);
int APS5_VABI sceVoiceCreatePort(uint32_t*, const VoicePortParam*);
int APS5_VABI sceVoiceDeletePort(uint32_t);
int APS5_VABI sceVoiceGetPortAttr(uint32_t, int32_t, void*, int32_t);
}

static void Require(bool value) { if (!value) std::abort(); }

template <typename Call>
static bool Throws(Call call, std::string_view message) {
    try {
        call();
    } catch (const std::logic_error& error) {
        return std::string_view(error.what()).find(message) != std::string_view::npos;
    }
    return false;
}

int main() {
    constexpr std::int32_t voiceActivity = 1001;

    Require(Throws([] { sceVoiceGetPortAttr(0, voiceActivity, nullptr, 1); }, "library not initialized"));

    VoiceInitParam init{};
    Require(sceVoiceInit(&init, 0) == 0);

    VoicePortParam param{};
    param.port_type = 2;
    param.volume = 1.0f;
    param.voice.bitrate = 16000;
    std::uint32_t port = 0;
    Require(sceVoiceCreatePort(&port, &param) == 0);

    std::array<unsigned char, 3> buffer{0xa5, 0xa5, 0xa5};
    Require(sceVoiceGetPortAttr(port, voiceActivity, &buffer[1], 1) == 0);
    Require(buffer[0] == 0xa5 && buffer[1] == 0 && buffer[2] == 0xa5);

    Require(Throws([port, &buffer] { sceVoiceGetPortAttr(port, 1, &buffer[1], 1); }, "attribute 1 not implemented"));

    Require(Throws([&buffer] { sceVoiceGetPortAttr(0x1234, voiceActivity, &buffer[1], 1); }, "unknown port"));

    Require(sceVoiceDeletePort(port) == 0);
    Require(Throws([port, &buffer] { sceVoiceGetPortAttr(port, voiceActivity, &buffer[1], 1); }, "unknown port"));

    Require(sceVoiceEnd_nid_postfix() == 0);
    return 0;
}
