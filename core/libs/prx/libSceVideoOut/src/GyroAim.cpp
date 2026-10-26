#include "prx/libSceVideoOut/include/GyroAim.hpp"
#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace GyroAim {

namespace {

constexpr double Pi = 3.14159265358979323846;
constexpr std::uint32_t L2Bit = 0x0100;
constexpr int L2Held = 30;

std::runtime_error bad(std::string_view what) {
    return std::runtime_error("ANYPS5_GYRO_AIM: " + std::string(what));
}

std::string_view trim(std::string_view text) {
    while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) text.remove_prefix(1);
    while (!text.empty() && (text.back() == ' ' || text.back() == '\t')) text.remove_suffix(1);
    return text;
}

double number(std::string_view key, std::string_view value, double least, double most) {
    double parsed = 0.0;
    const auto end = value.data() + value.size();
    const auto result = std::from_chars(value.data(), end, parsed);
    if (value.empty() || result.ec != std::errc{} || result.ptr != end || !std::isfinite(parsed) || parsed < least || parsed > most) {
        throw bad(std::string(key) + " must be a number from " + std::to_string(least).substr(0, 4) + " to " + std::to_string(most).substr(0, 4) +
                  ", not \"" + std::string(value) + "\"");
    }
    return parsed;
}

double axis(std::uint8_t value) {
    return std::clamp((static_cast<int>(value) - 128) / 127.0, -1.0, 1.0);
}

std::uint8_t byte(double value) {
    return static_cast<std::uint8_t>(std::clamp(std::lround(128.0 + std::clamp(value, -1.0, 1.0) * 127.0), 0L, 255L));
}

bool active(const PadInputState& state, Activation activation) {
    switch (activation) {
        case Activation::Always: return true;
        case Activation::WhileL2: return state.analogButtonsL2 >= L2Held || (state.analogButtonsL2 == 0 && (state.buttons & L2Bit) != 0);
        case Activation::WhileTouching: return state.touch[0].active || state.touch[1].active;
    }
    return false;
}

}

std::optional<Settings> Parse(std::string_view text) {
    text = trim(text);
    if (text.empty()) return std::nullopt;
    Settings settings;
    while (!text.empty()) {
        const auto comma = text.find(',');
        const auto entry = trim(text.substr(0, comma));
        text = comma == std::string_view::npos ? std::string_view{} : text.substr(comma + 1);
        if (entry.empty()) continue;
        if (entry == "on" || entry == "1") continue;
        const auto equals = entry.find('=');
        if (equals == std::string_view::npos) throw bad("expected key=value, not \"" + std::string(entry) + "\"");
        const auto key = trim(entry.substr(0, equals));
        const auto value = trim(entry.substr(equals + 1));
        if (key == "sensitivity") {
            settings.sensitivity = number(key, value, LeastSensitivity, MostSensitivity);
        } else if (key == "deadzone") {
            settings.deadzone = number(key, value, 0.0, MostDeadzone);
        } else if (key == "invert") {
            if (value == "none") settings.invertX = settings.invertY = false;
            else if (value == "x") { settings.invertX = true; settings.invertY = false; }
            else if (value == "y") { settings.invertX = false; settings.invertY = true; }
            else if (value == "xy") settings.invertX = settings.invertY = true;
            else throw bad("invert must be none, x, y or xy, not \"" + std::string(value) + "\"");
        } else if (key == "activate") {
            if (value == "always") settings.activation = Activation::Always;
            else if (value == "l2") settings.activation = Activation::WhileL2;
            else if (value == "touch") settings.activation = Activation::WhileTouching;
            else throw bad("activate must be always, l2 or touch, not \"" + std::string(value) + "\"");
        } else {
            throw bad("unknown setting \"" + std::string(key) + "\"");
        }
    }
    return settings;
}

std::optional<Settings> FromEnvironment() {
    const char* text = std::getenv("ANYPS5_GYRO_AIM");
    return text == nullptr ? std::nullopt : Parse(text);
}

Aim::Aim(Settings settings) : settings(settings) {}

PadInputState Aim::Apply(const PadInputState& state, double seconds) {
    if (!state.hasMotion) return state;
    // Gravity, smoothed: the accelerometer at rest points up (y out of the pad's face when flat).
    const double length = std::hypot(state.accel[0], state.accel[1], state.accel[2]);
    if (length > 1.0) {
        const std::array<double, 3> now{state.accel[0] / length, state.accel[1] / length, state.accel[2] / length};
        if (!up) {
            up = now;
        } else {
            const double keep = std::exp(-std::max(seconds, 0.0) / GravitySeconds);
            auto& kept = *up;
            for (std::size_t index = 0; index < 3; ++index) kept[index] = kept[index] * keep + now[index] * (1.0 - keep);
            const double norm = std::hypot(kept[0], kept[1], kept[2]);
            if (norm > 1e-6) for (auto& value : kept) value /= norm;
        }
    }
    if (!active(state, settings.activation)) return state;
    const auto& gravity = up.value_or(std::array<double, 3>{0.0, 1.0, 0.0});
    const double degrees = 180.0 / Pi;
    // Turning left is positive about the vertical; tilting the far end up is positive about x.
    const double yaw = (state.gyro[0] * gravity[0] + state.gyro[1] * gravity[1] + state.gyro[2] * gravity[2]) * degrees;
    const double pitch = state.gyro[0] * degrees;
    const double turn = std::hypot(yaw, pitch);
    if (turn <= settings.deadzone || turn <= 0.0) return state;
    const double kept = (turn - settings.deadzone) / turn;
    const double scale = settings.sensitivity / FullTurnDegrees * kept;
    // Right on the stick is positive x, up is negative y.
    const double x = -yaw * scale * (settings.invertX ? -1.0 : 1.0);
    const double y = -pitch * scale * (settings.invertY ? -1.0 : 1.0);
    auto aimed = state;
    aimed.sticks[2] = byte(axis(state.sticks[2]) + x);
    aimed.sticks[3] = byte(axis(state.sticks[3]) + y);
    return aimed;
}

}
