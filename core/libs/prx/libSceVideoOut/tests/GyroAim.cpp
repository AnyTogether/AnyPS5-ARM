#include "prx/libSceVideoOut/include/GyroAim.hpp"
#include <cmath>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

constexpr float Degree = 3.14159265358979323846f / 180.0f;

// A pad lying flat (gravity along y), turning at the given degrees per second about its own axes.
PadInputState flat(float pitch, float yaw, float roll = 0.0f) {
    PadInputState state;
    state.hasMotion = true;
    state.accel = {0.0f, 9.80665f, 0.0f};
    state.gyro = {pitch * Degree, yaw * Degree, roll * Degree};
    return state;
}

int stickX(const PadInputState& state) { return static_cast<int>(state.sticks[2]) - 128; }
int stickY(const PadInputState& state) { return static_cast<int>(state.sticks[3]) - 128; }

void parsesTheSettings() {
    require(!GyroAim::Parse(""), "empty is off");
    require(!GyroAim::Parse("  "), "blank is off");
    const auto defaults = GyroAim::Parse("on");
    require(defaults && *defaults == GyroAim::Settings{}, "on takes the defaults");
    const auto all = GyroAim::Parse("sensitivity=2.5, invert=xy, activate=l2, deadzone=4");
    require(all && all->sensitivity == 2.5 && all->invertX && all->invertY && all->activation == GyroAim::Activation::WhileL2 && all->deadzone == 4.0,
            "every setting is read");
    require(GyroAim::Parse("invert=y")->invertY && !GyroAim::Parse("invert=y")->invertX, "invert y only");
    require(GyroAim::Parse("activate=touch")->activation == GyroAim::Activation::WhileTouching, "touch to aim");
    for (const char* wrong : {"sensitivity=0", "sensitivity=11", "sensitivity=x", "deadzone=-1", "deadzone=50", "invert=z", "activate=r2", "speed=2", "sensitivity"}) {
        bool threw = false;
        try {
            GyroAim::Parse(wrong);
        } catch (const std::runtime_error& error) {
            threw = std::string(error.what()).find("ANYPS5_GYRO_AIM") != std::string::npos;
        }
        require(threw, "a malformed setting stops with an error naming the variable");
    }
}

void turningMovesTheRightStick() {
    GyroAim::Aim aim(GyroAim::Settings{1.0, false, false, GyroAim::Activation::Always, 0.0});
    const auto left = aim.Apply(flat(0.0f, 45.0f), 0.01);
    require(stickX(left) < -60 && stickX(left) > -66, "turning left at half the full turn pushes the stick half left");
    require(stickY(left) == 0, "and not up or down");
    const auto up = aim.Apply(flat(45.0f, 0.0f), 0.01);
    require(stickY(up) < -60 && stickX(up) == 0, "tilting the far end up looks up");
    const auto fast = aim.Apply(flat(0.0f, -400.0f), 0.01);
    require(fast.sticks[2] == 255, "a fast turn is a full stick, no further");
    const auto still = aim.Apply(flat(0.0f, 0.0f), 0.01);
    require(still.sticks[2] == 128 && still.sticks[3] == 128, "a pad held still moves nothing");
    const auto roll = aim.Apply(flat(0.0f, 0.0f, 60.0f), 0.01);
    require(roll.sticks[2] == 128, "rolling a flat pad is no turn");
}

void theStickStillCounts() {
    GyroAim::Aim aim(GyroAim::Settings{1.0, false, false, GyroAim::Activation::Always, 0.0});
    auto state = flat(0.0f, -45.0f);
    state.sticks[2] = 191;
    const auto both = aim.Apply(state, 0.01);
    require(both.sticks[2] > 250, "the turn adds to the stick");
    state.sticks[2] = 65;
    require(std::abs(stickX(aim.Apply(state, 0.01))) <= 1, "and can cancel it");
    state.sticks[0] = 7;
    require(aim.Apply(state, 0.01).sticks[0] == 7, "the left stick is not touched");
}

void sensitivityDeadzoneAndInvert() {
    GyroAim::Aim gentle(GyroAim::Settings{0.5, false, false, GyroAim::Activation::Always, 0.0});
    GyroAim::Aim keen(GyroAim::Settings{2.0, false, false, GyroAim::Activation::Always, 0.0});
    const int half = stickX(gentle.Apply(flat(0.0f, 45.0f), 0.01));
    const int twice = stickX(keen.Apply(flat(0.0f, 45.0f), 0.01));
    require(half < -29 && half > -34, "half the sensitivity, a quarter of the stick");
    require(twice == -127 || twice == -128, "twice, the whole stick");
    GyroAim::Aim dead(GyroAim::Settings{1.0, false, false, GyroAim::Activation::Always, 5.0});
    require(dead.Apply(flat(0.0f, 4.0f), 0.01).sticks[2] == 128, "a turn inside the deadzone moves nothing");
    const int past = stickX(dead.Apply(flat(0.0f, 50.0f), 0.01));
    require(past < -60 && past > -66, "a turn past it moves by what is past it, with no jump");
    GyroAim::Aim inverted(GyroAim::Settings{1.0, true, true, GyroAim::Activation::Always, 0.0});
    const auto flipped = inverted.Apply(flat(45.0f, 45.0f), 0.01);
    require(stickX(flipped) > 0 && stickY(flipped) > 0, "inverted, left turns right and up looks down");
}

void activation() {
    GyroAim::Aim l2(GyroAim::Settings{1.0, false, false, GyroAim::Activation::WhileL2, 0.0});
    auto state = flat(0.0f, 45.0f);
    require(l2.Apply(state, 0.01).sticks[2] == 128, "without L2, nothing");
    state.analogButtonsL2 = 200;
    require(stickX(l2.Apply(state, 0.01)) < -60, "with L2 held, the turn aims");
    state.analogButtonsL2 = 10;
    require(l2.Apply(state, 0.01).sticks[2] == 128, "a trigger barely touched is not held");
    state.analogButtonsL2 = 0;
    state.buttons = 0x0100;
    require(stickX(l2.Apply(state, 0.01)) < -60, "a digital L2 counts");
    GyroAim::Aim touch(GyroAim::Settings{1.0, false, false, GyroAim::Activation::WhileTouching, 0.0});
    auto touched = flat(0.0f, 45.0f);
    require(touch.Apply(touched, 0.01).sticks[2] == 128, "without a finger, nothing");
    touched.touch[1] = {true, 900, 500, 1};
    require(stickX(touch.Apply(touched, 0.01)) < -60, "a finger on the touchpad aims");
    PadInputState none;
    none.gyro = {1.0f, 1.0f, 1.0f};
    GyroAim::Aim always(GyroAim::Settings{});
    require(always.Apply(none, 0.01).sticks[2] == 128, "no motion, nothing");
}

// A phone held upright as a pad (its face toward the player): gravity runs along -z, and turning
// left is a turn about z. Player space reads it as a turn left all the same.
void playerSpaceForAnUprightPad() {
    GyroAim::Aim aim(GyroAim::Settings{1.0, false, false, GyroAim::Activation::Always, 0.0});
    PadInputState upright;
    upright.hasMotion = true;
    upright.accel = {0.0f, 0.0f, -9.80665f};
    upright.gyro = {0.0f, 0.0f, -45.0f * Degree};
    const auto turned = aim.Apply(upright, 0.01);
    require(stickX(turned) < -60, "an upright pad turned left looks left");
    upright.gyro = {0.0f, 45.0f * Degree, 0.0f};
    require(std::abs(stickX(aim.Apply(upright, 0.01))) <= 1, "and its roll is no turn");
}

void gravityFollowsSmoothly() {
    GyroAim::Aim aim(GyroAim::Settings{1.0, false, false, GyroAim::Activation::Always, 0.0});
    aim.Apply(flat(0.0f, 0.0f), 0.01);
    PadInputState jolt = flat(0.0f, 45.0f);
    jolt.accel = {0.0f, 0.0f, -9.80665f};
    const int first = stickX(aim.Apply(jolt, 0.01));
    require(first < -55, "one jolt barely moves the gravity the turn is read against");
    for (int step = 0; step < 200; ++step) aim.Apply(jolt, 0.01);
    require(std::abs(stickX(aim.Apply(jolt, 0.01))) <= 2, "held there, the gravity follows");
}

}

int main() try {
    parsesTheSettings();
    turningMovesTheRightStick();
    theStickStillCounts();
    sensitivityDeadzoneAndInvert();
    activation();
    playerSpaceForAnUprightPad();
    gravityFollowsSmoothly();
    std::cout << "gyro aim tests passed\n";
    return 0;
} catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
}
