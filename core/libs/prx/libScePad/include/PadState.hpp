#ifndef CORE_LIBS_PRX_LIBSCEPAD_PADSTATE_HPP
#define CORE_LIBS_PRX_LIBSCEPAD_PADSTATE_HPP

#include <array>
#include <cstdint>
#include <exception>
#include "SceTypes.hpp"

constexpr std::uint16_t kTouchPadWidth = 1920;
constexpr std::uint16_t kTouchPadHeight = 1080;

struct PadTouchPoint {
    bool active = false;
    std::uint16_t x = 0;
    std::uint16_t y = 0;
    std::uint8_t id = 0;

    bool operator==(const PadTouchPoint&) const = default;
};

struct PadInputState {
    std::uint32_t buttons = 0;
    std::array<std::uint8_t, 4> sticks{128, 128, 128, 128};
    std::uint8_t analogButtonsL2 = 0;
    std::uint8_t analogButtonsR2 = 0;
    bool touchLeft = false;
    bool touchRight = false;
    bool hasMotion = false;
    std::array<float, 3> accel{0.0f, 9.80665f, 0.0f};
    std::array<float, 3> gyro{0.0f, 0.0f, 0.0f};
    std::array<PadTouchPoint, 2> touch{};
    std::uint8_t deviceKind = 0;
};

struct PadTriggerRequest {
    bool valid = false;
    std::uint8_t effect[11]{};
    std::uint8_t fallback = 0;
    std::uint32_t mode = 0;
};

struct PadOutputState {
    std::uint32_t sequence = 0;
    std::uint8_t vibrationLarge = 0;
    std::uint8_t vibrationSmall = 0;
    std::uint8_t audioVibrationLarge = 0;
    std::uint8_t audioVibrationSmall = 0;
    bool lightBarValid = false;
    std::uint8_t lightBar[3]{};
    PadTriggerRequest trigger[2];
    bool triggerTouched = false;
    bool motionEnabled = true;
    int vibrationMode = 0;
};

// The DualSenses of up to four users. Player 0 is the first user's pad; player n belongs to the
// user logged in (n + 1)th.
constexpr int kPadPlayers = 4;

namespace Pad {
void Initialize();
bool IsInitialized();
bool IsConnected(int player);
// The players whose pad has ever been connected, a bit each; player 0 is always in.
std::uint32_t JoinedPlayers();
PadData ReadState(int player = 0);
int Read(PadData* data, int num, int player = 0);
void SetVibration(std::uint8_t large, std::uint8_t small, int player = 0);
void SetVibrationMode(int mode, int player = 0);
void SetLightBar(bool valid, std::uint8_t r, std::uint8_t g, std::uint8_t b, int player = 0);
void SetTriggerCommand(int trigger, const std::uint8_t* command, int player = 0);
void ResetOrientation(int player = 0);
void SetMotionEnabled(bool enabled, int player = 0);
void SetTiltCorrection(bool enabled, int player = 0);
void SetAngularVelocityDeadband(bool enabled, int player = 0);
void SetAngularVelocityBiasCorrection(bool enabled, int player = 0);
}

extern "C" void PadPublishInput_nid_postfix(const PadInputState& input);
extern "C" void PadPublishPlayerInput_nid_postfix(int player, const PadInputState& input);
extern "C" void PadDisconnectPlayer_nid_postfix(int player);
extern "C" bool PadFetchPlayerOutput_nid_postfix(int player, std::uint32_t* seenSequence, PadOutputState* out);
extern "C" std::uint32_t PadJoinedPlayers_nid_postfix();
extern "C" void PadReportInputFailure_nid_postfix(std::exception_ptr error);
extern "C" bool PadFetchOutput_nid_postfix(std::uint32_t* seenSequence, PadOutputState* out);
extern "C" void PadSubmitAudioHaptics_nid_postfix(std::uint8_t large, std::uint8_t small);
extern "C" void PadQueueLegacyAudioHaptics_nid_postfix(int source, std::uint64_t begin, std::uint64_t end, std::uint8_t large, std::uint8_t small);
extern "C" void PadClearLegacyAudioHaptics_nid_postfix(int source);

#endif
