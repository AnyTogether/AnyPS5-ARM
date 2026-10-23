#include "prx/libScePad/include/PadState.hpp"
#include "prx/libScePad/include/PadAudioHapticQueue.hpp"
#include "prx/libScePad/include/Pad.hpp"
#include "prx/libScePad/include/InputCommandFile.hpp"
#include "prx/libkernel/Time/include/Time.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <deque>
#include <mutex>
#include <stdexcept>

namespace {
    std::mutex stateMutex;
    std::chrono::steady_clock::time_point audioHapticEnd;
    std::array<std::uint8_t, 2> audioHapticRumble{};
    PadAudioHapticQueue legacyHaptics;
    constexpr std::uint64_t kLatchExpiry = 100000;
    constexpr std::size_t kQueueCapacity = 64;
    std::exception_ptr failure;
    bool initialized = false;

    struct QueuedInput {
        PadInputState input;
        std::uint64_t timestamp = 0;
    };
    struct Quat { float w = 1.0f, x = 0.0f, y = 0.0f, z = 0.0f; };

    // One DualSense: what it reports and what the game asks of it. Player 0 is the first user's
    // pad, connected from the start; the others connect when a device is given to them.
    struct Player {
        PadInputState state;
        bool connected = false;
        std::uint32_t pressedSinceRead = 0;
        std::uint8_t pressedAnalogL2 = 0;
        std::uint8_t pressedAnalogR2 = 0;
        std::uint64_t pressedAt = 0;
        PadOutputState output;
        std::uint64_t timestamp = 0;
        std::deque<QueuedInput> queue;
        Quat orientation;
        std::uint64_t lastFuseTime = 0;
        float biasIntegral[3] = {0.0f, 0.0f, 0.0f};
        bool tiltCorrection = true;
        bool angularVelocityDeadband = false;
        bool angularBiasCorrection = false;
        std::array<float, 3> gyroBias{0.0f, 0.0f, 0.0f};
        std::uint8_t nextTouchId = 0;
        bool prevTouchActive[2] = {false, false};
        std::uint8_t touchIds[2] = {0, 0};
    };
    std::array<Player, kPadPlayers> players = [] {
        std::array<Player, kPadPlayers> made{};
        made[0].connected = true;
        return made;
    }();
    std::uint32_t joined = 1;
    constexpr float kAngularVelocityDeadband = 0.017453292f;

    Player& PlayerAt(int player) {
        if (player < 0 || player >= kPadPlayers) throw std::invalid_argument("Pad: no such player");
        return players[static_cast<std::size_t>(player)];
    }

    bool RefreshAudioHaptics() {
        if (std::chrono::steady_clock::now() >= audioHapticEnd) audioHapticRumble = {};
        const auto legacy = legacyHaptics.Read(sceKernelGetProcessTime());
        const auto large = std::max(audioHapticRumble[0], legacy[0]);
        const auto small = std::max(audioHapticRumble[1], legacy[1]);
        auto& output = players[0].output;
        if (output.audioVibrationLarge == large && output.audioVibrationSmall == small) return false;
        output.audioVibrationLarge = large;
        output.audioVibrationSmall = small;
        return true;
    }

    void normalize(Quat& q) {
        const float n = std::sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
        if (n < 1e-6f) { q = Quat{}; return; }
        q.w /= n; q.x /= n; q.y /= n; q.z /= n;
    }

    void fuse(Player& p, float dt, const std::array<float, 3>& accel, const std::array<float, 3>& gyro) {
        auto& orientation = p.orientation;
        auto& biasIntegral = p.biasIntegral;
        float gx = gyro[0], gy = gyro[1], gz = gyro[2];
        const float an = std::sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
        if (p.tiltCorrection && an > 1.0f) {
            const float ax = accel[0] / an, ay = accel[1] / an, az = accel[2] / an;
            const float vx = 2.0f * (orientation.x * orientation.y + orientation.w * orientation.z);
            const float vy = orientation.w * orientation.w - orientation.x * orientation.x + orientation.y * orientation.y - orientation.z * orientation.z;
            const float vz = 2.0f * (orientation.y * orientation.z - orientation.w * orientation.x);
            const float ex = ay * vz - az * vy;
            const float ey = az * vx - ax * vz;
            const float ez = ax * vy - ay * vx;
            constexpr float kp = 1.5f;
            constexpr float ki = 0.02f;
            biasIntegral[0] += ki * ex * dt;
            biasIntegral[1] += ki * ey * dt;
            biasIntegral[2] += ki * ez * dt;
            gx += kp * ex + biasIntegral[0];
            gy += kp * ey + biasIntegral[1];
            gz += kp * ez + biasIntegral[2];
        }
        const float hx = 0.5f * gx * dt, hy = 0.5f * gy * dt, hz = 0.5f * gz * dt;
        const Quat q = orientation;
        orientation.w = q.w - q.x * hx - q.y * hy - q.z * hz;
        orientation.x = q.x + q.w * hx + q.y * hz - q.z * hy;
        orientation.y = q.y + q.w * hy - q.x * hz + q.z * hx;
        orientation.z = q.z + q.w * hz + q.x * hy - q.y * hx;
        normalize(orientation);
    }

    constexpr float kStationaryRadians = 0.05f;
    constexpr float kBiasLearnRate = 0.02f;

    std::array<float, 3> correctAngularVelocityBias(Player& p, std::array<float, 3> gyro, const std::array<float, 3>& accel) {
        if (!p.angularBiasCorrection) return gyro;
        auto& gyroBias = p.gyroBias;
        constexpr float kGravity = 9.80665f;
        const float an = std::sqrt(accel[0] * accel[0] + accel[1] * accel[1] + accel[2] * accel[2]);
        bool stationary = std::fabs(an - kGravity) < 0.5f;
        for (int axis = 0; axis < 3; ++axis) stationary = stationary && std::fabs(gyro[axis] - gyroBias[axis]) < kStationaryRadians;
        for (int axis = 0; axis < 3; ++axis) {
            if (stationary) gyroBias[axis] += kBiasLearnRate * (gyro[axis] - gyroBias[axis]);
            gyro[axis] -= gyroBias[axis];
        }
        return gyro;
    }

    void encodeZones(std::uint8_t* dst, std::uint8_t mode, const std::uint8_t* strengths, int count, std::uint8_t frequency) {
        std::uint16_t zones = 0;
        std::uint32_t packed = 0;
        for (int i = 0; i < count && i < 10; ++i) {
            const std::uint8_t s = strengths[i];
            if (s == 0 || s > 8) continue;
            zones |= static_cast<std::uint16_t>(1u << i);
            packed |= static_cast<std::uint32_t>(s - 1) << (i * 3);
        }
        if (zones == 0 || (mode == 0x26 && frequency == 0)) { dst[0] = 0x05; return; }
        dst[0] = mode;
        dst[1] = static_cast<std::uint8_t>(zones & 0xFF);
        dst[2] = static_cast<std::uint8_t>(zones >> 8);
        std::memcpy(dst + 3, &packed, 4);
        dst[9] = frequency;
    }

    std::uint8_t maxOf(const std::uint8_t* v, int n) {
        std::uint8_t m = 0;
        for (int i = 0; i < n; ++i) m = std::max(m, v[i]);
        return m;
    }

    std::uint8_t scaleStrength(std::uint8_t s) {
        return s == 0 ? 0 : static_cast<std::uint8_t>(std::min(255, 32 * std::min<int>(s, 8)));
    }
}

void Pad::Initialize() {
    std::lock_guard lock(stateMutex);
    if (failure) std::rethrow_exception(failure);
    if (!initialized) {
        for (auto& p : players) {
            p.timestamp = sceKernelGetProcessTime();
            p.lastFuseTime = p.timestamp;
            p.queue.clear();
            p.pressedSinceRead = 0;
        }
    }
    initialized = true;
}

bool Pad::IsInitialized() {
    std::lock_guard lock(stateMutex);
    return initialized;
}

bool Pad::IsConnected(int player) {
    std::lock_guard lock(stateMutex);
    return PlayerAt(player).connected;
}

std::uint32_t Pad::JoinedPlayers() {
    std::lock_guard lock(stateMutex);
    return joined;
}

namespace {
PadData BuildData(Player& p, const PadInputState& state, std::uint64_t changeTime, std::uint64_t now, const Pad::InputCommandFile::Input& injected) {
    PadData data{};
    data.buttons = state.buttons | injected.buttons;
    const auto& sticks = injected.hasSticks ? injected.sticks : state.sticks;
    data.left_stick_x = sticks[0];
    data.left_stick_y = sticks[1];
    data.right_stick_x = sticks[2];
    data.right_stick_y = sticks[3];
    const auto trigger = [&](std::uint8_t analog, std::uint32_t bit) -> std::uint8_t {
        return (injected.buttons & bit) != 0 || (analog == 0 && (state.buttons & bit) != 0) ? 255 : analog;
    };
    data.analog_buttons_l2 = trigger(state.analogButtonsL2, 0x100);
    data.analog_buttons_r2 = trigger(state.analogButtonsR2, 0x200);

    const bool live = state.hasMotion && p.output.motionEnabled;
    const std::array<float, 3> rest{0.0f, 9.80665f, 0.0f};
    const std::array<float, 3>& accel = live ? state.accel : rest;
    std::array<float, 3> gyro = live ? correctAngularVelocityBias(p, state.gyro, accel) : std::array<float, 3>{0.0f, 0.0f, 0.0f};
    if (p.angularVelocityDeadband) {
        for (float& axis : gyro) {
            if (axis < kAngularVelocityDeadband && axis > -kAngularVelocityDeadband) axis = 0.0f;
        }
    }
    if (live) {
        float dt = p.lastFuseTime != 0 && now > p.lastFuseTime ? static_cast<float>(now - p.lastFuseTime) * 1e-6f : 0.0f;
        dt = std::min(dt, 0.1f);
        fuse(p, dt, accel, gyro);
    } else {
        p.orientation = Quat{};
        p.biasIntegral[0] = p.biasIntegral[1] = p.biasIntegral[2] = 0.0f;
    }
    p.lastFuseTime = now;
    data.orientation_x = p.orientation.x;
    data.orientation_y = p.orientation.y;
    data.orientation_z = p.orientation.z;
    data.orientation_w = p.orientation.w;
    constexpr float kGravity = 9.80665f;
    data.acceleration_x = accel[0] / kGravity;
    data.acceleration_y = accel[1] / kGravity;
    data.acceleration_z = accel[2] / kGravity;
    data.angular_velocity_x = gyro[0];
    data.angular_velocity_y = gyro[1];
    data.angular_velocity_z = gyro[2];

    data.connected = p.connected;
    data.connected_count = p.connected ? 1 : 0;
    data.timestamp = changeTime;

    std::uint8_t touchNum = 0;
    for (int i = 0; i < 2; ++i) {
        const PadTouchPoint& tp = state.touch[i];
        if (!tp.active) { p.prevTouchActive[i] = false; continue; }
        if (!p.prevTouchActive[i]) p.touchIds[i] = static_cast<std::uint8_t>(p.nextTouchId++ & 0x7F);
        p.prevTouchActive[i] = true;
        if (touchNum == 0) {
            data.touch_data_touch0_x = tp.x; data.touch_data_touch0_y = tp.y; data.touch_data_touch0_id = p.touchIds[i];
        } else {
            data.touch_data_touch1_x = tp.x; data.touch_data_touch1_y = tp.y; data.touch_data_touch1_id = p.touchIds[i];
        }
        ++touchNum;
    }
    if (touchNum == 0 && (state.touchLeft || state.touchRight || injected.touchLeft || injected.touchRight)) {
        data.buttons |= 0x100000;
        touchNum = 1;
        data.touch_data_touch0_x = state.touchRight || injected.touchRight ? kTouchPadWidth * 3 / 4 : kTouchPadWidth / 4;
        data.touch_data_touch0_y = kTouchPadHeight / 2;
        data.touch_data_touch0_id = 0;
    }
    data.touch_data_touch_num = touchNum;
    return data;
}

// APS5_PAD_INPUT_FILE drives the first player's pad only.
Pad::InputCommandFile::Input InjectedInput(int player, std::uint64_t now) {
    if (player != 0) return {};
    static Pad::InputCommandFile commands([] {
#ifdef _WIN32
        const auto* path = _wgetenv(L"APS5_PAD_INPUT_FILE");
#else
        const auto* path = std::getenv("APS5_PAD_INPUT_FILE");
#endif
        return path ? std::filesystem::path(path) : std::filesystem::path{};
    }());
    static Pad::InputCommandFile::Input lastInjected;
    const auto injected = commands.Poll(now);
    if (injected != lastInjected) {
        lastInjected = injected;
        players[0].timestamp = now;
    }
    return injected;
}
}

PadData Pad::ReadState(int player) {
    std::lock_guard lock(stateMutex);
    if (failure) std::rethrow_exception(failure);
    if (!initialized) throw std::runtime_error("Pad: read before initialization");
    auto& p = PlayerAt(player);
    const std::uint64_t now = sceKernelGetProcessTime();
    const auto injected = InjectedInput(player, now);
    PadData data = BuildData(p, p.state, p.timestamp, now, injected);
    if (p.pressedSinceRead != 0 && now - p.pressedAt <= kLatchExpiry) {
        data.buttons |= p.pressedSinceRead;
        if (p.pressedSinceRead & 0x100u) data.analog_buttons_l2 = std::max(data.analog_buttons_l2, p.pressedAnalogL2);
        if (p.pressedSinceRead & 0x200u) data.analog_buttons_r2 = std::max(data.analog_buttons_r2, p.pressedAnalogR2);
    }
    p.pressedSinceRead = 0;
    return data;
}

int Pad::Read(PadData* data, int num, int player) {
    if (data == nullptr || num <= 0) throw std::invalid_argument("Pad: invalid read buffer");
    std::lock_guard lock(stateMutex);
    if (failure) std::rethrow_exception(failure);
    if (!initialized) throw std::runtime_error("Pad: read before initialization");
    auto& p = PlayerAt(player);
    p.pressedSinceRead = 0;
    const std::uint64_t now = sceKernelGetProcessTime();
    const auto injected = InjectedInput(player, now);
    if (p.queue.empty()) {
        data[0] = BuildData(p, p.state, p.timestamp, now, injected);
        return 1;
    }
    int count = 0;
    while (count < num && !p.queue.empty()) {
        const QueuedInput& entry = p.queue.front();
        data[count++] = BuildData(p, entry.input, entry.timestamp, now, injected);
        p.queue.pop_front();
    }
    return count;
}

void Pad::SetVibration(std::uint8_t large, std::uint8_t small, int player) {
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    if (output.vibrationLarge == large && output.vibrationSmall == small) return;
    output.vibrationLarge = large;
    output.vibrationSmall = small;
    ++output.sequence;
}

void Pad::SetVibrationMode(int mode, int player) {
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    if (output.vibrationMode == mode) return;
    output.vibrationMode = mode;
    ++output.sequence;
}

void Pad::SetLightBar(bool valid, std::uint8_t r, std::uint8_t g, std::uint8_t b, int player) {
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    output.lightBarValid = valid;
    output.lightBar[0] = r;
    output.lightBar[1] = g;
    output.lightBar[2] = b;
    ++output.sequence;
}

void Pad::SetTriggerCommand(int trigger, const std::uint8_t* command, int player) {
    if (trigger < 0 || trigger > 1 || command == nullptr) return;
    std::uint32_t mode = 0;
    std::memcpy(&mode, command, 4);
    const std::uint8_t* p = command + 8;
    PadTriggerRequest req;
    req.mode = mode;
    req.effect[0] = 0x05;
    switch (mode) {
        case 1: {
            std::uint8_t strengths[10] = {};
            if (p[0] <= 9 && p[1] >= 1 && p[1] <= 8) for (int i = p[0]; i < 10; ++i) strengths[i] = p[1];
            encodeZones(req.effect, 0x21, strengths, 10, 0);
            req.fallback = scaleStrength(p[1]);
            break;
        }
        case 2: {
            if (p[0] >= 2 && p[0] <= 7 && p[1] > p[0] && p[1] <= 8 && p[2] >= 1 && p[2] <= 8) {
                const std::uint16_t zones = static_cast<std::uint16_t>((1u << p[0]) | (1u << p[1]));
                req.effect[0] = 0x25;
                req.effect[1] = static_cast<std::uint8_t>(zones & 0xFF);
                req.effect[2] = static_cast<std::uint8_t>(zones >> 8);
                req.effect[3] = static_cast<std::uint8_t>(p[2] - 1);
            }
            req.fallback = scaleStrength(p[2]);
            break;
        }
        case 3: {
            std::uint8_t strengths[10] = {};
            if (p[0] <= 9 && p[1] >= 1 && p[1] <= 8) for (int i = p[0]; i < 10; ++i) strengths[i] = p[1];
            encodeZones(req.effect, 0x26, strengths, 10, p[2]);
            req.fallback = scaleStrength(p[1]);
            break;
        }
        case 4:
            encodeZones(req.effect, 0x21, p, 10, 0);
            req.fallback = scaleStrength(maxOf(p, 10));
            break;
        case 5: {
            std::uint8_t strengths[10] = {};
            if (p[0] <= 8 && p[1] > p[0] && p[1] <= 9 && p[2] >= 1 && p[2] <= 8 && p[3] >= 1 && p[3] <= 8) {
                const int dist = p[1] - p[0];
                for (int i = p[0]; i < 10; ++i)
                    strengths[i] = i <= p[1] ? static_cast<std::uint8_t>(std::lround(p[2] + (p[3] - p[2]) * (i - p[0]) / static_cast<double>(dist))) : p[3];
            }
            encodeZones(req.effect, 0x21, strengths, 10, 0);
            req.fallback = scaleStrength(std::max(p[2], p[3]));
            break;
        }
        case 6:
            encodeZones(req.effect, 0x26, p + 1, 10, p[0]);
            req.fallback = p[0] == 0 ? 0 : scaleStrength(maxOf(p + 1, 10));
            break;
        default: break;
    }
    req.valid = req.effect[0] != 0x05;
    if (!req.valid) req.fallback = 0;
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    output.trigger[trigger] = req;
    output.triggerTouched = true;
    ++output.sequence;
}

void Pad::ResetOrientation(int player) {
    std::lock_guard lock(stateMutex);
    auto& p = PlayerAt(player);
    p.orientation = Quat{};
    p.biasIntegral[0] = p.biasIntegral[1] = p.biasIntegral[2] = 0.0f;
}

void Pad::SetTiltCorrection(bool enabled, int player) {
    std::lock_guard lock(stateMutex);
    auto& p = PlayerAt(player);
    p.tiltCorrection = enabled;
    p.biasIntegral[0] = p.biasIntegral[1] = p.biasIntegral[2] = 0.0f;
}

void Pad::SetAngularVelocityDeadband(bool enabled, int player) {
    std::lock_guard lock(stateMutex);
    PlayerAt(player).angularVelocityDeadband = enabled;
}

void Pad::SetAngularVelocityBiasCorrection(bool enabled, int player) {
    std::lock_guard lock(stateMutex);
    auto& p = PlayerAt(player);
    p.angularBiasCorrection = enabled;
    p.gyroBias = {0.0f, 0.0f, 0.0f};
}

void Pad::SetMotionEnabled(bool enabled, int player) {
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    if (output.motionEnabled == enabled) return;
    output.motionEnabled = enabled;
    ++output.sequence;
}

extern "C" void PadPublishPlayerInput_nid_postfix(int player, const PadInputState& input) {
    std::lock_guard lock(stateMutex);
    if (failure) std::rethrow_exception(failure);
    auto& p = PlayerAt(player);
    const bool connecting = !p.connected;
    if (connecting) {
        p.connected = true;
        joined |= 1u << player;
    }
    auto& state = p.state;
    if (!connecting && state.buttons == input.buttons && state.sticks == input.sticks &&
        state.analogButtonsL2 == input.analogButtonsL2 && state.analogButtonsR2 == input.analogButtonsR2 &&
        state.touchLeft == input.touchLeft && state.touchRight == input.touchRight &&
        state.hasMotion == input.hasMotion && state.accel == input.accel && state.gyro == input.gyro &&
        state.touch == input.touch && state.deviceKind == input.deviceKind) return;
    const std::uint32_t pressed = input.buttons & ~state.buttons;
    p.timestamp = sceKernelGetProcessTime();
    if (pressed != 0) {
        if (p.pressedSinceRead != 0 && p.timestamp - p.pressedAt > kLatchExpiry) p.pressedSinceRead = 0;
        p.pressedSinceRead |= pressed;
        p.pressedAt = p.timestamp;
        if (pressed & 0x100u) p.pressedAnalogL2 = input.analogButtonsL2;
        if (pressed & 0x200u) p.pressedAnalogR2 = input.analogButtonsR2;
    }
    state = input;
    if (p.queue.size() == kQueueCapacity) p.queue.pop_front();
    p.queue.push_back({input, p.timestamp});
}

extern "C" void PadPublishInput_nid_postfix(const PadInputState& input) {
    PadPublishPlayerInput_nid_postfix(0, input);
}

// The first player's pad stays connected; another player's goes when its device does, and its
// user stays logged in, as a console user does when the controller is turned off.
extern "C" void PadDisconnectPlayer_nid_postfix(int player) {
    std::lock_guard lock(stateMutex);
    auto& p = PlayerAt(player);
    if (player == 0 || !p.connected) return;
    p.connected = false;
    p.state = PadInputState{};
    p.pressedSinceRead = 0;
    p.queue.clear();
    p.timestamp = sceKernelGetProcessTime();
}

extern "C" void PadReportInputFailure_nid_postfix(std::exception_ptr error) {
    if (!error) throw std::invalid_argument("Pad: missing input failure");
    std::lock_guard lock(stateMutex);
    if (!failure) failure = error;
}

extern "C" bool PadFetchPlayerOutput_nid_postfix(int player, std::uint32_t* seenSequence, PadOutputState* out) {
    std::lock_guard lock(stateMutex);
    auto& output = PlayerAt(player).output;
    if (player == 0 && RefreshAudioHaptics()) ++output.sequence;
    if (seenSequence == nullptr || out == nullptr || *seenSequence == output.sequence) return false;
    *seenSequence = output.sequence;
    *out = output;
    return true;
}

extern "C" bool PadFetchOutput_nid_postfix(std::uint32_t* seenSequence, PadOutputState* out) {
    return PadFetchPlayerOutput_nid_postfix(0, seenSequence, out);
}

extern "C" void PadSubmitAudioHaptics_nid_postfix(std::uint8_t large, std::uint8_t small) {
    std::lock_guard lock(stateMutex);
    if (large == 0 && small == 0) return;
    const auto now = std::chrono::steady_clock::now();
    if (now >= audioHapticEnd) audioHapticRumble = {};
    audioHapticRumble[0] = std::max(audioHapticRumble[0], large);
    audioHapticRumble[1] = std::max(audioHapticRumble[1], small);
    audioHapticEnd = now + std::chrono::milliseconds(80);
    static_cast<void>(RefreshAudioHaptics());
    ++players[0].output.sequence;
}

extern "C" void PadQueueLegacyAudioHaptics_nid_postfix(int source, std::uint64_t begin, std::uint64_t end, std::uint8_t large, std::uint8_t small) {
    std::lock_guard lock(stateMutex);
    legacyHaptics.Queue(source, begin, end, large, small);
    if (RefreshAudioHaptics()) ++players[0].output.sequence;
}

extern "C" void PadClearLegacyAudioHaptics_nid_postfix(int source) {
    std::lock_guard lock(stateMutex);
    legacyHaptics.Clear(source);
    if (RefreshAudioHaptics()) ++players[0].output.sequence;
}
extern "C" std::uint32_t PadJoinedPlayers_nid_postfix() {
    return Pad::JoinedPlayers();
}
