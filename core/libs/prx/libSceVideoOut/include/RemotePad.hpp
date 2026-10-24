#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <vector>
#include "prx/libScePad/include/Pad.hpp"
#include "prx/libScePad/include/PadState.hpp"

namespace RemotePad {

constexpr std::uint32_t InputMagic = 0x49525041u;
constexpr std::uint32_t OutputMagic = 0x4F525041u;
constexpr std::uint32_t HelloMagic = 0x48525041u;
constexpr std::uint16_t Version = 1;
constexpr std::size_t InputSize = 80;
constexpr std::size_t OutputSize = 32;
constexpr std::size_t HelloSize = 16;
constexpr auto Silence = std::chrono::milliseconds(500);
// A phone silent this long has left: its player is free for another device.
constexpr auto Gone = std::chrono::seconds(5);

struct Input {
    std::uint32_t sequence = 0;
    std::uint64_t sentMicros = 0;
    std::uint32_t waitMicros = 0;
    std::uint64_t session = 0;
    PadInputState state{};
};

std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes);
std::array<std::uint8_t, OutputSize> EncodeOutput(const Input& last, const PadOutputState& output);
// player is the channel's player counting from 1, or 0 while its phone is none.
std::array<std::uint8_t, HelloSize> EncodeHello(std::uint8_t player = 0);
bool IsNewer(std::uint32_t sequence, std::uint32_t than);
PadInputState Merge(const PadInputState& controller, const PadInputState& remote);
PadInputState Current(const std::optional<Input>& last, std::chrono::steady_clock::time_point seen, std::chrono::steady_clock::time_point now);

class Channel {
public:
    explicit Channel(std::uint16_t launcherPort);
    ~Channel();
    Channel(const Channel&) = delete;
    Channel& operator=(const Channel&) = delete;

    std::optional<Input> Poll(std::chrono::steady_clock::time_point now);
    void Answer(const Input& last, const PadOutputState& output);
    void Greet(std::chrono::steady_clock::time_point now);
    // Which player the phone is, from 1, or 0; a change is said in the next hello at once.
    void SetPlayer(std::uint8_t number);
    std::uint16_t Port() const { return port; }

private:
    void send(const std::uint8_t* bytes, std::size_t size);

    int socket = -1;
    std::uint16_t port = 0;
    std::uint16_t launcherPort = 0;
    std::optional<std::uint32_t> newest;
    std::optional<std::uint64_t> session;
    std::optional<std::chrono::steady_clock::time_point> greeted;
    std::uint8_t player = 0;
};

std::unique_ptr<Channel> OpenFromEnvironment();
// The channel of ANYPS5_REMOTE_PAD, then one for each of ANYPS5_REMOTE_PAD_2 to _4 up to the
// first that is unset: one per phone the launcher can bring.
std::vector<std::unique_ptr<Channel>> OpenAllFromEnvironment();

// Whether a device's input asks for a player: a button, a trigger, a touch or a stick pushed
// well off centre. Moving the device does not, so a controller lying on the desk takes no one's
// place.
bool Wants(const PadInputState& state);

// The players' seats: each device that asks takes the lowest free player and keeps it until it
// leaves. Devices are named by number: a controller by its SDL instance id, a phone by
// RemoteDevice(its channel).
class Seats {
public:
    int Seat(std::uint32_t device, bool wants);
    int Leave(std::uint32_t device);
    int Of(std::uint32_t device) const;
    bool Held(int player) const;

private:
    std::array<std::optional<std::uint32_t>, PAD_MAX_CONTROLLERS> holders;
};

constexpr std::uint32_t RemoteDevice(std::size_t channel) { return 0x80000000u | static_cast<std::uint32_t>(channel); }

// The light a player's pad shows when the game sets none, as on the console: blue, red, green, pink.
std::array<std::uint8_t, 3> PlayerColor(int player);

}

#endif
