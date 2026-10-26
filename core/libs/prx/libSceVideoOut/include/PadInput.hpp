#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_PADINPUT_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_PADINPUT_HPP

#include "SDL_events.h"
#include "SDL_gamecontroller.h"
#include "prx/libScePad/include/KeyboardMouse.hpp"
#include "prx/libScePad/include/PadState.hpp"
#include "prx/libScePad/include/Pad.hpp"
#include "prx/libSceVideoOut/include/PadOutputPacing.hpp"
#include "prx/libSceVideoOut/include/RemotePad.hpp"
#include <array>
#include <chrono>
#include <memory>
#include <optional>
#include <vector>
#include "prx/libSceVideoOut/include/Telemetry.hpp"

class DisplayWindow;

// The players' pads, fed by the keyboard and mouse, the Mac's game controllers and the phones the
// launcher brings. A controller or phone becomes a player the first time it is used (RemotePad::Seats);
// the keyboard and mouse always drive the first player. A press the launcher sends (RemotePad::Press)
// holds buttons on the first player's pad, whoever drives it, and takes no seat.
class PadInput {
public:
    PadInput();
    ~PadInput();
    void HandleEvent(const SDL_Event& event, DisplayWindow& window);
    void Update(const DisplayWindow& window);
    bool MouseModeEnabled() const { return keyboardMouse.MouseMode(); }
    bool SlotOccupied(int slot) const { return seats.Held(slot); }

private:
    struct Controller {
        SDL_GameController* handle = nullptr;
        SDL_JoystickID id = -1;
        PadInputState state{};
        bool outputPending = true;
        bool sensors = true;
        std::chrono::steady_clock::time_point nextRumbleRefresh{};
        LightBarPacer lightBar;
        TriggerEffectCache triggerEffect;
    };
    struct Remote {
        std::unique_ptr<RemotePad::Channel> channel;
        std::optional<RemotePad::Input> last;
        std::chrono::steady_clock::time_point seen{};
        PadInputState state{};
    };
    struct Output {
        std::uint32_t sequence = 0;
        PadOutputState state{};
    };

    explicit PadInput(Pad::InputConfiguration configuration);
    void publish(std::uint64_t frame);
    void setMouseMode(bool enabled);
    void openAvailableControllers();
    void openController(int deviceIndex);
    void closeController(SDL_JoystickID id);
    void sampleControllers();
    PadInputState sampleController(SDL_GameController* controller) const;
    void applyOutput();
    void applyOutput(Controller& controller, const PadOutputState& output, int player);
    void enableSensors(Controller& controller, bool wanted);
    void updateRemotes();
    void answer(Remote& remote, int player);
    void leave(std::uint32_t device);

    Pad::KeyboardMouse keyboardMouse;
    std::vector<Controller> controllers;
    std::vector<Remote> remotes;
    RemotePad::Seats seats;
    RemotePad::Presses playerOnePresses;
    std::uint32_t playerOnePressed = 0;
    std::array<Output, PAD_MAX_CONTROLLERS> outputs{};
    std::array<bool, PAD_MAX_CONTROLLERS> published{};
    VideoOutTelemetry::PadChangeFilter telemetryFilter;
};

#endif
