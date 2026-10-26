#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_GYROAIM_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_GYROAIM_HPP

#include <array>
#include <optional>
#include <string_view>
#include "prx/libScePad/include/PadState.hpp"

// Gyro aiming for every game (Steam Input's gyro to joystick camera): a controller's or phone's
// turn moves the right stick, on top of what the stick itself does, so any game that aims with
// the right stick aims with the pad's motion. The turn is read in player space: about the
// world's vertical (from gravity) for left and right, about the pad's own left-right axis for up
// and down, so a DualSense held at any angle and a phone held upright both aim the same way.
namespace GyroAim {

// When the gyro aims: always, while L2 is held (aiming down the sights), or while a finger is on
// the touchpad.
enum class Activation { Always, WhileL2, WhileTouching };

struct Settings {
    // Full stick at FullTurnDegrees / sensitivity degrees per second.
    double sensitivity = 1.0;
    bool invertX = false;
    bool invertY = false;
    Activation activation = Activation::Always;
    // Turns slower than this many degrees per second (a resting hand) move nothing.
    double deadzone = 2.0;

    bool operator==(const Settings&) const = default;
};

constexpr double FullTurnDegrees = 90.0;
constexpr double LeastSensitivity = 0.1;
constexpr double MostSensitivity = 10.0;
constexpr double MostDeadzone = 45.0;
// How quickly the gravity the turn is read against follows the accelerometer.
constexpr double GravitySeconds = 0.25;

// ANYPS5_GYRO_AIM: unset or empty is off; otherwise comma-separated key=value settings, any of
// sensitivity=<0.1-10>, invert=none|x|y|xy, activate=always|l2|touch, deadzone=<0-45>, such
// as "sensitivity=1.5,activate=l2". A malformed value throws an error naming the variable.
std::optional<Settings> Parse(std::string_view text);
std::optional<Settings> FromEnvironment();

// One device's aim: it keeps the gravity it reads the turn against.
class Aim {
public:
    explicit Aim(Settings settings);
    // The state with the turn added to its right stick; seconds since the last call smooth the
    // gravity. A state without motion, or with the activation not held, is left as it is.
    PadInputState Apply(const PadInputState& state, double seconds);
    const Settings& Configuration() const { return settings; }

private:
    Settings settings;
    std::optional<std::array<double, 3>> up;
};

}

#endif
