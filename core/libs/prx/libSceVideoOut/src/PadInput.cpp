#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <memory>
#include <string>
#include <utility>

#include "SDL.h"
#include "prx/libSceVideoOut/include/PadInput.hpp"
#include "prx/libSceMouse/include/MouseState.hpp"
#include "prx/libSceVideoOut/include/DisplayWindow.hpp"
#include "prx/libSceAgcDriver/Execution/include/Presentation.hpp"
#include "prx/libSceAgcDriver/Execution/include/Driver.hpp"
#include "prx/libScePad/include/PadState.hpp"
#include "prx/libScePad/include/PadInputTypes.hpp"
#include "prx/libSceUserService/UserService.hpp"
#include "prx/libc/include/General.hpp"
#include <chrono>
#include <vector>

namespace {

// Debug aid for unattended runs: APS5_PAD_SCRIPT="<seconds>:<button>[+<button>...][~<ms>],..." holds the
// buttons from that many seconds after the first input update, for <ms> (200 by default). Buttons:
// cross circle square triangle up down left right options l1 r1 l2 r2 l3 r3 touchpad.
struct ScriptedPress {
    double at;
    double hold;
    std::uint32_t buttons;
};

std::vector<ScriptedPress> LoadPadScript() {
    std::vector<ScriptedPress> presses;
    const char* text = std::getenv("APS5_PAD_SCRIPT");
    if (text == nullptr) return presses;
    static constexpr std::pair<const char*, Pad::PadButton> names[] = {
        {"cross", Pad::PadButton::Cross}, {"circle", Pad::PadButton::Circle}, {"square", Pad::PadButton::Square}, {"triangle", Pad::PadButton::Triangle},
        {"up", Pad::PadButton::Up}, {"down", Pad::PadButton::Down}, {"left", Pad::PadButton::Left}, {"right", Pad::PadButton::Right},
        {"options", Pad::PadButton::Options}, {"l1", Pad::PadButton::L1}, {"r1", Pad::PadButton::R1}, {"l2", Pad::PadButton::L2},
        {"r2", Pad::PadButton::R2}, {"l3", Pad::PadButton::L3}, {"r3", Pad::PadButton::R3}, {"touchpad", Pad::PadButton::TouchPad}};
    const std::string script(text);
    std::size_t start = 0;
    while (start < script.size()) {
        const auto end = std::min(script.find(',', start), script.size());
        const std::string entry = script.substr(start, end - start);
        start = end + 1;
        const auto colon = entry.find(':');
        if (colon == std::string::npos) throw std::runtime_error("APS5_PAD_SCRIPT entry without a time: " + entry);
        ScriptedPress press{std::stod(entry.substr(0, colon)), 0.2, 0};
        std::string rest = entry.substr(colon + 1);
        if (const auto tilde = rest.find('~'); tilde != std::string::npos) {
            press.hold = std::stod(rest.substr(tilde + 1)) / 1000.0;
            rest.resize(tilde);
        }
        std::size_t from = 0;
        while (from <= rest.size()) {
            const auto plus = std::min(rest.find('+', from), rest.size());
            const std::string name = rest.substr(from, plus - from);
            from = plus + 1;
            const auto found = std::find_if(std::begin(names), std::end(names), [&](const auto& item) { return name == item.first; });
            if (found == std::end(names)) throw std::runtime_error("APS5_PAD_SCRIPT has an unknown button: " + name);
            press.buttons |= static_cast<std::uint32_t>(found->second);
        }
        presses.push_back(press);
    }
    return presses;
}

std::uint32_t ScriptedButtons() {
    static const auto presses = LoadPadScript();
    if (presses.empty()) return 0;
    static const auto origin = std::chrono::steady_clock::now();
    const double now = std::chrono::duration<double>(std::chrono::steady_clock::now() - origin).count();
    std::uint32_t buttons = 0;
    for (const auto& press : presses) {
        if (now >= press.at && now < press.at + press.hold) buttons |= press.buttons;
    }
    return buttons;
}

}
#include "prx/libSceIme/include/ImeInput.hpp"

PadInput::PadInput() : PadInput(Pad::LoadInputMapping()) {
}

PadInput::PadInput(Pad::InputConfiguration configuration) : keyboardMouse(std::move(configuration)), gyro(GyroAim::FromEnvironment()) {
    if (gyro) {
        APS5_LOG_OUT("Pad: gyro aiming on (sensitivity %.1f, deadzone %.0f deg/s, %s)", gyro->sensitivity, gyro->deadzone,
            gyro->activation == GyroAim::Activation::Always ? "always" : gyro->activation == GyroAim::Activation::WhileL2 ? "while L2 is held" : "while touching");
    }
    for (auto& channel : RemotePad::OpenAllFromEnvironment()) remotes.push_back(Remote{std::move(channel)});
    openAvailableControllers();
}

PadInput::~PadInput() {
    for (auto& controller : controllers) SDL_GameControllerClose(controller.handle);
}

void PadInput::openAvailableControllers() {
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_PS5_RUMBLE, "1");
    if ((SDL_WasInit(SDL_INIT_GAMECONTROLLER) & SDL_INIT_GAMECONTROLLER) == 0) {
        if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) {
            APS5_LOG_ERR("Pad: SDL game controller init failed: %s", SDL_GetError());
            return;
        }
    }
    for (int deviceIndex = 0; deviceIndex < SDL_NumJoysticks(); ++deviceIndex) openController(deviceIndex);
}

void PadInput::openController(int deviceIndex) {
    if (!SDL_IsGameController(deviceIndex)) return;
    const SDL_JoystickID id = SDL_JoystickGetDeviceInstanceID(deviceIndex);
    if (std::any_of(controllers.begin(), controllers.end(), [id](const Controller& controller) { return controller.id == id; })) return;
    SDL_GameController* handle = SDL_GameControllerOpen(deviceIndex);
    if (handle == nullptr) {
        APS5_LOG_ERR("Pad: could not open game controller %d: %s", deviceIndex, SDL_GetError());
        return;
    }
    const char* name = SDL_GameControllerName(handle);
    APS5_LOG_OUT("Pad: connected game controller: %s (type %d, sensors accel=%d gyro=%d, touchpads=%d, led=%d, trigger rumble=%d)",
        name != nullptr ? name : "unknown", static_cast<int>(SDL_GameControllerGetType(handle)),
        SDL_GameControllerHasSensor(handle, SDL_SENSOR_ACCEL) == SDL_TRUE, SDL_GameControllerHasSensor(handle, SDL_SENSOR_GYRO) == SDL_TRUE,
        SDL_GameControllerGetNumTouchpads(handle), SDL_GameControllerHasLED(handle) == SDL_TRUE, SDL_GameControllerHasRumbleTriggers(handle) == SDL_TRUE);
    Controller controller;
    controller.handle = handle;
    controller.id = SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(handle));
    controllers.push_back(std::move(controller));
    enableSensors(controllers.back(), true);
}

void PadInput::enableSensors(Controller& controller, bool wanted) {
    controller.sensors = wanted;
    const SDL_bool on = wanted ? SDL_TRUE : SDL_FALSE;
    if (SDL_GameControllerHasSensor(controller.handle, SDL_SENSOR_ACCEL) == SDL_TRUE) SDL_GameControllerSetSensorEnabled(controller.handle, SDL_SENSOR_ACCEL, on);
    if (SDL_GameControllerHasSensor(controller.handle, SDL_SENSOR_GYRO) == SDL_TRUE) SDL_GameControllerSetSensorEnabled(controller.handle, SDL_SENSOR_GYRO, on);
}

void PadInput::closeController(SDL_JoystickID id) {
    const auto found = std::find_if(controllers.begin(), controllers.end(), [id](const Controller& controller) { return controller.id == id; });
    if (found == controllers.end()) return;
    SDL_GameControllerClose(found->handle);
    controllers.erase(found);
    leave(static_cast<std::uint32_t>(id));
}

// A device gives its player back; another player's pad disconnects, the first player's stays.
void PadInput::leave(std::uint32_t device) {
    const int player = seats.Leave(device);
    if (player <= 0) return;
    PadSetPortConnected_nid_postfix(player, false);
    published[static_cast<std::size_t>(player)] = false;
    APS5_LOG_OUT("Pad: player %d left", player + 1);
}

// Gyro aiming: the device's turn on its right stick, each device with its own gravity.
PadInputState PadInput::aimed(std::optional<GyroAim::Aim>& aim, std::chrono::steady_clock::time_point& at, const PadInputState& state) {
    if (!gyro) return state;
    if (!aim) aim.emplace(*gyro);
    const auto now = std::chrono::steady_clock::now();
    const double seconds = at == std::chrono::steady_clock::time_point{} ? 0.0 : std::chrono::duration<double>(now - at).count();
    at = now;
    return aim->Apply(state, std::min(seconds, 0.25));
}

void PadInput::sampleControllers() {
    for (auto& controller : controllers) {
        controller.state = sampleController(controller.handle);
        controller.aimed = aimed(controller.aim, controller.aimedAt, controller.state);
        if (controller.helping) continue;
        const auto id = static_cast<std::uint32_t>(controller.id);
        const bool seated = seats.Of(id) >= 0;
        if (!seated && RemotePad::Wants(controller.state) && RemotePad::Helps(controllersHelp, seats.Held(0))) {
            controller.helping = true;
            controller.outputPending = true;
            controller.lightBar.Reset();
            controller.triggerEffect.Reset();
            APS5_LOG_OUT("Pad: game controller helps player %d", 1);
            continue;
        }
        const int player = seats.Seat(id, RemotePad::Wants(controller.state));
        if (!seated && player >= 0) {
            controller.outputPending = true;
            controller.lightBar.Reset();
            controller.triggerEffect.Reset();
            APS5_LOG_OUT("Pad: game controller is player %d", player + 1);
        }
    }
}

// The player whose pad a controller feeds: its seat, or the first player's while it helps.
int PadInput::playerOf(const Controller& controller) const {
    return controller.helping ? 0 : seats.Of(static_cast<std::uint32_t>(controller.id));
}

// Controllers help the first player (AssistControllers) or are players of their own again: one
// that holds player 2 to 4 gives it up to help, and helpers take a seat on their next press.
void PadInput::setControllersHelp(bool help) {
    if (help == controllersHelp) return;
    controllersHelp = help;
    APS5_LOG_OUT("Pad: the launcher says other controllers %s player 1", help ? "help" : "no longer help");
    for (auto& controller : controllers) {
        const auto id = static_cast<std::uint32_t>(controller.id);
        if (help && seats.Of(id) > 0) {
            leave(id);
            controller.helping = true;
        } else if (!help) {
            controller.helping = false;
        }
        controller.outputPending = true;
        controller.lightBar.Reset();
        controller.triggerEffect.Reset();
    }
}

void PadInput::answer(Remote& remote, int player) {
    if (!remote.last) return;
    auto output = player >= 0 ? outputs[static_cast<std::size_t>(player)].state : PadOutputState{};
    if (player > 0 && !output.lightBarValid) {
        const auto color = RemotePad::PlayerColor(player);
        output.lightBarValid = true;
        std::copy(color.begin(), color.end(), output.lightBar);
    }
    remote.channel->Answer(*remote.last, output);
}

void PadInput::applyOutput() {
    for (int player = 0; player < PAD_MAX_CONTROLLERS; ++player) {
        auto& output = outputs[static_cast<std::size_t>(player)];
        PadOutputState fetched;
        if (!PadFetchOutputForPort_nid_postfix(player, &output.sequence, &fetched)) continue;
        const bool motionChanged = fetched.motionEnabled != output.state.motionEnabled;
        output.state = fetched;
        for (auto& controller : controllers) {
            if (playerOf(controller) != player) continue;
            controller.outputPending = true;
            if (motionChanged) enableSensors(controller, sensorsWanted(fetched.motionEnabled));
        }
        for (std::size_t channel = 0; channel < remotes.size(); ++channel) {
            const bool helps = player == 0 && remotes[channel].helping;
            if (helps || seats.Of(RemotePad::RemoteDevice(channel)) == player) answer(remotes[channel], player);
        }
    }
    for (auto& controller : controllers) {
        const int player = playerOf(controller);
        if (player >= 0 && controller.sensors != sensorsWanted(outputs[static_cast<std::size_t>(player)].state.motionEnabled)) {
            enableSensors(controller, sensorsWanted(outputs[static_cast<std::size_t>(player)].state.motionEnabled));
        }
        applyOutput(controller, player >= 0 ? outputs[static_cast<std::size_t>(player)].state : PadOutputState{}, player);
    }
}

void PadInput::applyOutput(Controller& pad, const PadOutputState& outputState, int player) {
    SDL_GameController* controller = pad.handle;
    const auto now = std::chrono::steady_clock::now();
    const bool isPs5 = SDL_GameControllerGetType(controller) == SDL_CONTROLLER_TYPE_PS5;
    const auto large = std::max(outputState.vibrationLarge, outputState.audioVibrationLarge);
    const auto small = std::max(outputState.vibrationSmall, outputState.audioVibrationSmall);
    const bool rumbling = large != 0 || small != 0;
    const bool triggerRumble = outputState.trigger[0].fallback != 0 || outputState.trigger[1].fallback != 0;
    if (SDL_GameControllerHasLED(controller) == SDL_TRUE) {
        const LightBarPacer::Color color = outputState.lightBarValid
            ? LightBarPacer::Color{outputState.lightBar[0], outputState.lightBar[1], outputState.lightBar[2]}
            : RemotePad::PlayerColor(std::max(player, 0));
        if (pad.lightBar.Due(color, now)) pad.lightBar.Result(color, now, SDL_GameControllerSetLED(controller, color[0], color[1], color[2]) == 0);
    }
    if (!pad.outputPending) {
        if ((rumbling || (triggerRumble && !isPs5)) && now >= pad.nextRumbleRefresh) pad.outputPending = true;
        else return;
    }
    pad.outputPending = false;
    pad.nextRumbleRefresh = now + std::chrono::milliseconds(700);
    constexpr Uint32 rumbleMs = 2000;
    SDL_GameControllerRumble(controller, static_cast<Uint16>(large * 257), static_cast<Uint16>(small * 257), rumbling ? rumbleMs : 0);
    if (outputState.triggerTouched) {
        if (isPs5) {
            TriggerEffectCache::Effect effect{};
            effect[0] = 0x04 | 0x08;
            std::memcpy(effect.data() + 10, outputState.trigger[1].effect, 11);
            std::memcpy(effect.data() + 21, outputState.trigger[0].effect, 11);
            if (pad.triggerEffect.NeedsSend(effect)) {
                pad.triggerEffect.Result(effect, SDL_GameControllerSendEffect(controller, effect.data(), static_cast<int>(effect.size())) == 0);
            }
        } else if (SDL_GameControllerHasRumbleTriggers(controller) == SDL_TRUE) {
            SDL_GameControllerRumbleTriggers(controller, static_cast<Uint16>(outputState.trigger[0].fallback * 257), static_cast<Uint16>(outputState.trigger[1].fallback * 257), triggerRumble ? rumbleMs : 0);
        }
    }
}

void PadInput::setMouseMode(bool enabled) {
    SDL_SetHint(SDL_HINT_MOUSE_RELATIVE_MODE_WARP, "0");
    SDL_SetHint(SDL_HINT_MOUSE_RELATIVE_SYSTEM_SCALE, "0");
    if (SDL_SetRelativeMouseMode(enabled ? SDL_TRUE : SDL_FALSE) != 0) throw std::runtime_error(std::string("Pad: relative mouse mode failed: ") + SDL_GetError());
    keyboardMouse.SetMouseMode(enabled);
}

PadInputState PadInput::sampleController(SDL_GameController* controller) const {
    PadInputState result;
    if (controller == nullptr) return result;
    const auto readButton = [controller](SDL_GameControllerButton button) {
        return SDL_GameControllerGetButton(controller, button) != 0;
    };
    const auto addButton = [&result, &readButton](SDL_GameControllerButton source, Pad::PadButton button) {
        if (readButton(source)) result.buttons |= static_cast<std::uint32_t>(button);
    };
    addButton(SDL_CONTROLLER_BUTTON_A, Pad::PadButton::Cross);
    addButton(SDL_CONTROLLER_BUTTON_B, Pad::PadButton::Circle);
    addButton(SDL_CONTROLLER_BUTTON_X, Pad::PadButton::Square);
    addButton(SDL_CONTROLLER_BUTTON_Y, Pad::PadButton::Triangle);
    addButton(SDL_CONTROLLER_BUTTON_LEFTSHOULDER, Pad::PadButton::L1);
    addButton(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER, Pad::PadButton::R1);
    const auto type = SDL_GameControllerGetType(controller);
    const bool viewPressed = type != SDL_CONTROLLER_TYPE_PS4 && type != SDL_CONTROLLER_TYPE_PS5 && readButton(SDL_CONTROLLER_BUTTON_BACK);
    if (viewPressed) result.buttons |= static_cast<std::uint32_t>(Pad::PadButton::TouchPad);
    addButton(SDL_CONTROLLER_BUTTON_START, Pad::PadButton::Options);
    addButton(SDL_CONTROLLER_BUTTON_LEFTSTICK, Pad::PadButton::L3);
    addButton(SDL_CONTROLLER_BUTTON_RIGHTSTICK, Pad::PadButton::R3);
    addButton(SDL_CONTROLLER_BUTTON_DPAD_UP, Pad::PadButton::Up);
    addButton(SDL_CONTROLLER_BUTTON_DPAD_RIGHT, Pad::PadButton::Right);
    addButton(SDL_CONTROLLER_BUTTON_DPAD_DOWN, Pad::PadButton::Down);
    addButton(SDL_CONTROLLER_BUTTON_DPAD_LEFT, Pad::PadButton::Left);
    addButton(SDL_CONTROLLER_BUTTON_TOUCHPAD, Pad::PadButton::TouchPad);

    const auto triggerValue = [controller](SDL_GameControllerAxis axis) {
        const auto value = std::clamp<int>(SDL_GameControllerGetAxis(controller, axis), 0, 32767);
        return static_cast<std::uint8_t>((value * 255 + 16383) / 32767);
    };
    result.analogButtonsL2 = triggerValue(SDL_CONTROLLER_AXIS_TRIGGERLEFT);
    result.analogButtonsR2 = triggerValue(SDL_CONTROLLER_AXIS_TRIGGERRIGHT);
    if (result.analogButtonsL2 != 0) result.buttons |= static_cast<std::uint32_t>(Pad::PadButton::L2);
    if (result.analogButtonsR2 != 0) result.buttons |= static_cast<std::uint32_t>(Pad::PadButton::R2);

    const auto stick = [controller](SDL_GameControllerAxis xAxis, SDL_GameControllerAxis yAxis, int deadzonePercent) {
        return Pad::StickWithDeadzone(SDL_GameControllerGetAxis(controller, xAxis), SDL_GameControllerGetAxis(controller, yAxis), deadzonePercent);
    };
    const auto left = stick(SDL_CONTROLLER_AXIS_LEFTX, SDL_CONTROLLER_AXIS_LEFTY, keyboardMouse.Configuration().settings.leftStickDeadzonePercent);
    const auto right = stick(SDL_CONTROLLER_AXIS_RIGHTX, SDL_CONTROLLER_AXIS_RIGHTY, keyboardMouse.Configuration().settings.rightStickDeadzonePercent);
    result.sticks = {left[0], left[1], right[0], right[1]};
    switch (SDL_GameControllerGetType(controller)) {
        case SDL_CONTROLLER_TYPE_PS5: result.deviceKind = 1; break;
        case SDL_CONTROLLER_TYPE_PS4: result.deviceKind = 2; break;
        default: result.deviceKind = 3; break;
    }
    if (SDL_GameControllerIsSensorEnabled(controller, SDL_SENSOR_ACCEL) == SDL_TRUE && SDL_GameControllerIsSensorEnabled(controller, SDL_SENSOR_GYRO) == SDL_TRUE) {
        float accel[3];
        float gyro[3];
        if (SDL_GameControllerGetSensorData(controller, SDL_SENSOR_ACCEL, accel, 3) == 0 && SDL_GameControllerGetSensorData(controller, SDL_SENSOR_GYRO, gyro, 3) == 0) {
            result.hasMotion = true;
            for (int i = 0; i < 3; ++i) { result.accel[i] = accel[i]; result.gyro[i] = gyro[i]; }
        }
    }
    if (SDL_GameControllerGetNumTouchpads(controller) > 0) {
        for (int finger = 0; finger < 2; ++finger) {
            Uint8 down = 0;
            float x = 0.0f;
            float y = 0.0f;
            float pressure = 0.0f;
            if (SDL_GameControllerGetTouchpadFinger(controller, 0, finger, &down, &x, &y, &pressure) != 0 || down == 0) continue;
            result.touch[finger].active = true;
            result.touch[finger].x = static_cast<std::uint16_t>(std::clamp(x, 0.0f, 1.0f) * (kTouchPadWidth - 1));
            result.touch[finger].y = static_cast<std::uint16_t>(std::clamp(y, 0.0f, 1.0f) * (kTouchPadHeight - 1));
        }
    }
    if (viewPressed && !result.touch[0].active && !result.touch[1].active) {
        result.touch[0] = {true, kTouchPadWidth / 2, kTouchPadHeight / 2, 0};
    }
    return result;
}

void PadInput::HandleEvent(const SDL_Event& event, DisplayWindow& window) {
    if (event.type == SDL_CONTROLLERDEVICEADDED) {
        openController(event.cdevice.which);
        return;
    }
    if (event.type == SDL_CONTROLLERDEVICEREMOVED) {
        closeController(event.cdevice.which);
        publish(window.FrameNumber());
        return;
    }
    if (event.type == SDL_CONTROLLERBUTTONDOWN || event.type == SDL_CONTROLLERBUTTONUP ||
        event.type == SDL_CONTROLLERAXISMOTION || event.type == SDL_CONTROLLERDEVICEREMAPPED) {
        sampleControllers();
        publish(window.FrameNumber());
        return;
    }
    if (event.type == SDL_WINDOWEVENT) {
        if (keyboardMouse.HandleEvent(event, std::chrono::steady_clock::now()).releaseMouse) setMouseMode(false);
        publish(window.FrameNumber());
        return;
    }
    // APS5_NO_PAD_INPUT=1 keeps a measurement run from reacting to keys or mouse buttons that reach
    // its window (a stray press advances the title into another stage).
    static const bool ignoreInput = std::getenv("APS5_NO_PAD_INPUT") != nullptr;
    const bool input = event.type == SDL_MOUSEWHEEL || event.type == SDL_MOUSEMOTION || event.type == SDL_KEYDOWN || event.type == SDL_KEYUP ||
        event.type == SDL_MOUSEBUTTONDOWN || event.type == SDL_MOUSEBUTTONUP;
    if (!input || ignoreInput) return;
    if (event.type == SDL_KEYDOWN && ImeCapturesKeyboard_nid_postfix()) return;
    keyboardMouse.SetTitleReadsMouse(MouseIsOpen_nid_no_patch());
    const auto requests = keyboardMouse.HandleEvent(event, std::chrono::steady_clock::now());
    if (requests.toggleFullscreen && window.Handle() != nullptr && event.key.windowID == SDL_GetWindowID(window.Handle())) window.ToggleFullscreen();
    if (requests.togglePerformanceOverlay && window.Handle() != nullptr && event.key.windowID == SDL_GetWindowID(window.Handle())) AgcDriverTogglePerformanceOverlay_nid_postfix();
    if (requests.screenshot && window.Handle() != nullptr && event.key.windowID == SDL_GetWindowID(window.Handle())) AgcDriverRequestScreenshot_nid_postfix();
    if (requests.toggleMouse) setMouseMode(!keyboardMouse.MouseMode());
    if (event.type != SDL_MOUSEMOTION) publish(window.FrameNumber());
}

// Each phone's newest input; a phone that starts pressing takes a player, one silent for
// RemotePad::Gone gives it back. Returns whether any phone's input changed.
void PadInput::updateRemotes() {
    const auto now = std::chrono::steady_clock::now();
    for (std::size_t channel = 0; channel < remotes.size(); ++channel) {
        auto& remote = remotes[channel];
        const auto device = RemotePad::RemoteDevice(channel);
        remote.channel->Greet(now);
        if (auto input = remote.channel->Poll(now)) {
            remote.last = std::move(input);
            remote.seen = now;
            if (remote.last->seat == RemotePad::AssistSeat) {
                // Helps the first player: it gives up a seat it held and takes none.
                if (!remote.helping) {
                    leave(device);
                    remote.helping = true;
                    APS5_LOG_OUT("Pad: phone %zu helps player 1", channel + 1);
                }
                remote.channel->SetPlayer(1);
                answer(remote, 0);
            } else {
                if (remote.helping) {
                    remote.helping = false;
                    APS5_LOG_OUT("Pad: phone %zu no longer helps player 1", channel + 1);
                }
                const bool seated = seats.Of(device) >= 0;
                const int player = seats.Seat(device, RemotePad::Wants(remote.last->state), remote.last->seat);
                if (!seated && player >= 0) APS5_LOG_OUT("Pad: phone %zu is player %d", channel + 1, player + 1);
                remote.channel->SetPlayer(static_cast<std::uint8_t>(player + 1));
                answer(remote, player);
            }
        }
        if (const auto flags = remote.channel->TakeAssist()) setControllersHelp((*flags & RemotePad::AssistControllers) != 0);
        for (const auto& text : remote.channel->TakeTexts()) type(text);
        for (const auto& press : remote.channel->TakePresses()) {
            playerOnePresses.Add(press, now);
            APS5_LOG_OUT("Pad: channel %zu presses 0x%x on player 1 for %lld ms", channel + 1, press.buttons, static_cast<long long>(press.hold.count()));
        }
        if (remote.last && now - remote.seen >= RemotePad::Gone) {
            remote.last.reset();
            remote.helping = false;
            leave(device);
            remote.channel->SetPlayer(0);
        }
        remote.state = RemotePad::Current(remote.last, remote.seen, now);
        remote.aimed = aimed(remote.aim, remote.aimedAt, remote.state);
    }
}

// What the game asks for goes to the launcher at once and again every second while it is open,
// so a launcher that starts again or a phone that joins late still sees it.
void PadInput::updatePrompt(std::chrono::steady_clock::time_point now) {
    if (remotes.empty()) return;
    const auto revision = ImeHostPromptRevision_nid_postfix();
    const bool changed = revision != promptRevision;
    if (!changed && (prompt.id == 0 || now - promptSent < std::chrono::seconds(1))) return;
    if (changed) {
        auto asked = std::make_unique<ImeHostPrompt>();
        promptRevision = ImeGetHostPrompt_nid_postfix(asked.get());
        prompt = RemotePad::Prompt{};
        if (asked->id != 0) {
            prompt.id = asked->id;
            prompt.kind = asked->kind == 2 ? RemotePad::Prompt::Kind::Dialog : RemotePad::Prompt::Kind::Keyboard;
            prompt.type = static_cast<std::uint8_t>(std::min<std::uint32_t>(asked->type, 255));
            prompt.enterLabel = static_cast<std::uint8_t>(std::min<std::uint32_t>(asked->enterLabel, 255));
            prompt.multiline = asked->multiline;
            prompt.maxLength = static_cast<std::uint16_t>(std::min<std::uint32_t>(asked->maxLength, 0xffff));
            prompt.title = RemotePad::Utf8(asked->title);
            prompt.placeholder = RemotePad::Utf8(asked->placeholder);
            prompt.text = RemotePad::Utf8(asked->text);
            APS5_LOG_OUT("Pad: the game asks for text (prompt %u), told to the launcher", prompt.id);
        }
    }
    promptSent = now;
    for (auto& remote : remotes) remote.channel->SendPrompt(prompt);
}

// A phone's text for the prompt open now replaces the game's text: Clear, the text in pieces
// that each fit an ImeHostInput, then Enter or Escape.
void PadInput::type(const RemotePad::TypedText& text) {
    if (prompt.id == 0 || text.prompt != prompt.id) return;
    ImeHostInput clear{};
    clear.kind = ImeHostInputKind::Clear;
    ImePublishInput_nid_postfix(clear);
    for (const auto& piece : RemotePad::TextPieces(text.text, sizeof(ImeHostInput{}.text) - 1)) {
        ImeHostInput input{};
        input.kind = ImeHostInputKind::Text;
        std::memcpy(input.text, piece.data(), piece.size());
        ImePublishInput_nid_postfix(input);
    }
    if (text.action == RemotePad::TypedText::Action::Update) return;
    ImeHostInput finish{};
    finish.kind = text.action == RemotePad::TypedText::Action::Submit ? ImeHostInputKind::Enter : ImeHostInputKind::Escape;
    ImePublishInput_nid_postfix(finish);
    APS5_LOG_OUT("Pad: a phone %s the text for prompt %u", text.action == RemotePad::TypedText::Action::Submit ? "entered" : "cancelled", prompt.id);
}

void PadInput::Update(const DisplayWindow& window) {
    if (!controllers.empty()) SDL_GameControllerUpdate();
    applyOutput();
    updatePrompt(std::chrono::steady_clock::now());
    std::vector<PadInputState> remotesBefore;
    for (const auto& remote : remotes) remotesBefore.push_back(remote.state);
    updateRemotes();
    for (std::size_t channel = 0; channel < remotes.size(); ++channel) {
        const auto& before = remotesBefore[channel];
        const auto& now = remotes[channel].state;
        if (now.buttons != before.buttons || now.sticks != before.sticks || now.analogButtonsL2 != before.analogButtonsL2 ||
            now.analogButtonsR2 != before.analogButtonsR2 || now.touch != before.touch || now.hasMotion) {
            publish(window.FrameNumber());
            break;
        }
    }
    if (const auto buttons = playerOnePresses.Buttons(std::chrono::steady_clock::now()); buttons != playerOnePressed) {
        playerOnePressed = buttons;
        publish(window.FrameNumber());
    }
    static std::uint32_t scripted = 0;
    if (const auto buttons = ScriptedButtons(); buttons != scripted) {
        scripted = buttons;
        publish(window.FrameNumber());
    }
    sampleControllers();
    if (keyboardMouse.MouseMode() && SDL_GetKeyboardFocus() == nullptr) {
        keyboardMouse.Release();
        setMouseMode(false);
        publish(window.FrameNumber());
        return;
    }
    const bool changed = keyboardMouse.Advance(std::chrono::steady_clock::now());
    if (!controllers.empty() || keyboardMouse.MouseMode() || changed) publish(window.FrameNumber());
}

// While the on-screen keyboard reads the pad (ImeCapturesPad), the game sees a neutral pad; buttons
// held through the capture stay released for the game until they are let go.
PadInputState PadInput::handOff(int slot, PadInputState state) {
    auto& held = outputs[static_cast<std::size_t>(slot)].heldThroughCapture;
    if (ImeCapturesPad_nid_postfix()) {
        if (slot == 0) ImePublishPad_nid_postfix({state.buttons, state.sticks[0], state.sticks[1], state.analogButtonsL2});
        held = state.buttons;
        PadInputState neutral;
        neutral.hasMotion = false;
        neutral.deviceKind = state.deviceKind;
        neutral.intercepted = true;
        return neutral;
    }
    held &= state.buttons;
    state.buttons &= ~held;
    if ((held & static_cast<std::uint32_t>(Pad::PadButton::L2)) != 0) state.analogButtonsL2 = 0;
    if ((held & static_cast<std::uint32_t>(Pad::PadButton::R2)) != 0) state.analogButtonsR2 = 0;
    return state;
}

// Every player's pad from the device seated there; the first player's also from the keyboard,
// the mouse, the launcher's presses and APS5_PAD_SCRIPT, and published even with no device.
void PadInput::publish(std::uint64_t frame) {
    for (int player = 0; player < PAD_MAX_CONTROLLERS; ++player) {
        std::optional<PadInputState> device;
        for (const auto& controller : controllers) {
            if (!controller.helping && seats.Of(static_cast<std::uint32_t>(controller.id)) == player) device = controller.aimed;
        }
        for (std::size_t channel = 0; channel < remotes.size(); ++channel) {
            if (!remotes[channel].helping && seats.Of(RemotePad::RemoteDevice(channel)) == player) device = RemotePad::Merge(device.value_or(PadInputState{}), remotes[channel].aimed);
        }
        if (player == 0) {
            // Assist: every helper's input joins the first player's.
            for (const auto& controller : controllers) {
                if (controller.helping) device = RemotePad::Assisted(device.value_or(PadInputState{}), controller.aimed);
            }
            for (const auto& remote : remotes) {
                if (remote.helping) device = RemotePad::Assisted(device.value_or(PadInputState{}), remote.aimed);
            }
        }
        if (player != 0) {
            if (!device) continue;
            if (!published[static_cast<std::size_t>(player)]) {
                PadSetPortConnected_nid_postfix(player, true);
                UserServiceSetUserConnected_nid_postfix(player, true);
                APS5_LOG_OUT("Pad: player %d joined", player + 1);
            }
            published[static_cast<std::size_t>(player)] = true;
            PadPublishInputForPort_nid_postfix(player, handOff(player, *device));
            continue;
        }
        auto state = keyboardMouse.Compose(device.value_or(PadInputState{}));
        state.buttons |= ScriptedButtons() | playerOnePressed;
        state = handOff(0, state);
        PadPublishInput_nid_postfix(state);
        if (auto* telemetry = VideoOutTelemetry::Instance(); telemetry != nullptr) VideoOutTelemetry::EmitPadIfChanged(*telemetry, telemetryFilter, frame, state);
    }
}
