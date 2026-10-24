#include "prx/libSceVideoOut/include/RemotePad.hpp"
#include "prx/libSceVideoOut/src/RemotePadSocket.hpp"
#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>

namespace RemotePad {

namespace {

constexpr std::uint32_t KnownButtons = 0x0002u | 0x0004u | 0x0008u | 0x0010u | 0x0020u | 0x0040u | 0x0080u | 0x0100u | 0x0200u | 0x0400u |
    0x0800u | 0x1000u | 0x2000u | 0x4000u | 0x8000u | 0x100000u;

template <typename T>
T read(std::span<const std::uint8_t> bytes, std::size_t offset) {
    T value;
    std::memcpy(&value, bytes.data() + offset, sizeof(T));
    return value;
}

template <typename T>
void write(std::uint8_t* bytes, std::size_t offset, T value) {
    std::memcpy(bytes + offset, &value, sizeof(T));
}

std::uint8_t stronger(std::uint8_t controller, std::uint8_t remote) {
    const auto distance = [](std::uint8_t value) { return std::abs(static_cast<int>(value) - 128); };
    return distance(remote) > distance(controller) ? remote : controller;
}

std::runtime_error badAddress(std::string_view name, std::string_view value) {
    return std::runtime_error(std::string(name) + " must be 127.0.0.1:<port from 1 to 65535>, not \"" + std::string(value) + "\"");
}

std::unique_ptr<Channel> OpenNamed(const char* name) {
    const char* raw = std::getenv(name);
    if (raw == nullptr || *raw == '\0') return nullptr;
    const std::string_view value(raw);
    constexpr std::string_view host = "127.0.0.1:";
    if (!value.starts_with(host)) throw badAddress(name, value);
    const auto digits = value.substr(host.size());
    unsigned port = 0;
    const auto [end, error] = std::from_chars(digits.data(), digits.data() + digits.size(), port);
    if (error != std::errc{} || end != digits.data() + digits.size() || port == 0 || port > 65535) throw badAddress(name, value);
    return std::make_unique<Channel>(static_cast<std::uint16_t>(port));
}

}

std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes) {
    if (bytes.size() != InputSize) return std::nullopt;
    if (read<std::uint32_t>(bytes, 0) != InputMagic || read<std::uint16_t>(bytes, 4) != Version || read<std::uint16_t>(bytes, 6) != InputSize) return std::nullopt;
    Input input;
    input.sequence = read<std::uint32_t>(bytes, 8);
    input.sentMicros = read<std::uint64_t>(bytes, 16);
    input.session = read<std::uint64_t>(bytes, 24);
    if (const auto seat = bytes[13]; seat >= 2 && seat <= kPadPlayers) input.seat = seat;
    auto& state = input.state;
    state.buttons = read<std::uint32_t>(bytes, 32) & KnownButtons;
    for (std::size_t axis = 0; axis < 4; ++axis) state.sticks[axis] = bytes[36 + axis];
    state.analogButtonsL2 = bytes[40];
    state.analogButtonsR2 = bytes[41];
    for (std::size_t point = 0; point < 2; ++point) {
        const auto offset = 44 + point * 6;
        auto& touch = state.touch[point];
        touch.active = bytes[offset] != 0;
        touch.id = bytes[offset + 1];
        touch.x = read<std::uint16_t>(bytes, offset + 2);
        touch.y = read<std::uint16_t>(bytes, offset + 4);
        if (touch.x >= kTouchPadWidth || touch.y >= kTouchPadHeight) return std::nullopt;
        if (!touch.active) touch = PadTouchPoint{};
    }
    for (std::size_t axis = 0; axis < 3; ++axis) {
        state.accel[axis] = read<float>(bytes, 56 + axis * 4);
        state.gyro[axis] = read<float>(bytes, 68 + axis * 4);
        if (!std::isfinite(state.accel[axis]) || !std::isfinite(state.gyro[axis])) return std::nullopt;
    }
    state.hasMotion = (read<std::uint32_t>(bytes, 12) & 1u) != 0;
    if (!state.hasMotion) {
        state.accel = PadInputState{}.accel;
        state.gyro = PadInputState{}.gyro;
    }
    return input;
}

std::array<std::uint8_t, OutputSize> EncodeOutput(const Input& last, const PadOutputState& output) {
    std::array<std::uint8_t, OutputSize> bytes{};
    write<std::uint32_t>(bytes.data(), 0, OutputMagic);
    write<std::uint16_t>(bytes.data(), 4, Version);
    write<std::uint16_t>(bytes.data(), 6, static_cast<std::uint16_t>(OutputSize));
    write<std::uint32_t>(bytes.data(), 8, last.sequence);
    write<std::uint32_t>(bytes.data(), 12, last.waitMicros);
    write<std::uint64_t>(bytes.data(), 16, last.sentMicros);
    bytes[24] = std::max(output.vibrationLarge, output.audioVibrationLarge);
    bytes[25] = std::max(output.vibrationSmall, output.audioVibrationSmall);
    bytes[26] = output.lightBarValid ? 1 : 0;
    bytes[27] = output.lightBar[0];
    bytes[28] = output.lightBar[1];
    bytes[29] = output.lightBar[2];
    bytes[30] = output.trigger[0].fallback;
    bytes[31] = output.trigger[1].fallback;
    return bytes;
}

std::array<std::uint8_t, HelloSize> EncodeHello(std::uint8_t player) {
    std::array<std::uint8_t, HelloSize> bytes{};
    write<std::uint32_t>(bytes.data(), 0, HelloMagic);
    write<std::uint16_t>(bytes.data(), 4, Version);
    write<std::uint16_t>(bytes.data(), 6, static_cast<std::uint16_t>(HelloSize));
    bytes[8] = player;
    return bytes;
}

bool IsNewer(std::uint32_t sequence, std::uint32_t than) {
    const auto difference = sequence - than;
    return difference != 0 && difference < 0x80000000u;
}

PadInputState Merge(const PadInputState& controller, const PadInputState& remote) {
    auto merged = controller;
    merged.buttons |= remote.buttons;
    for (std::size_t axis = 0; axis < 4; ++axis) merged.sticks[axis] = stronger(controller.sticks[axis], remote.sticks[axis]);
    merged.analogButtonsL2 = std::max(controller.analogButtonsL2, remote.analogButtonsL2);
    merged.analogButtonsR2 = std::max(controller.analogButtonsR2, remote.analogButtonsR2);
    merged.touchLeft = controller.touchLeft || remote.touchLeft;
    merged.touchRight = controller.touchRight || remote.touchRight;
    for (std::size_t point = 0; point < 2; ++point) {
        if (remote.touch[point].active) merged.touch[point] = remote.touch[point];
    }
    if (remote.hasMotion) {
        merged.hasMotion = true;
        merged.accel = remote.accel;
        merged.gyro = remote.gyro;
    }
    return merged;
}

PadInputState Current(const std::optional<Input>& last, std::chrono::steady_clock::time_point seen, std::chrono::steady_clock::time_point now) {
    if (!last || now - seen >= Silence) return PadInputState{};
    return last->state;
}

Channel::Channel(std::uint16_t launcherPort) : launcherPort(launcherPort) {
    socket = Net::OpenUdp();
    if (socket == Net::None) throw std::runtime_error("remote pad: cannot open a socket: " + Net::LastError());
    std::optional<std::uint16_t> bound;
    if (!Net::StampArrivals(socket) || !(bound = Net::BindLoopback(socket)) || !Net::MakeNonBlocking(socket)) {
        const auto error = Net::LastError();
        Net::Close(socket);
        throw std::runtime_error("remote pad: cannot bind 127.0.0.1: " + error);
    }
    port = *bound;
}

Channel::~Channel() {
    if (socket != Net::None) Net::Close(socket);
}

std::optional<Input> Channel::Poll(std::chrono::steady_clock::time_point) {
    std::optional<Input> result;
    std::array<std::uint8_t, InputSize + 1> buffer{};
    std::optional<std::int64_t> arrived;
    while (true) {
        const auto got = Net::Receive(socket, buffer.data(), buffer.size(), arrived);
        if (!got) break;
        auto input = DecodeInput(std::span<const std::uint8_t>(buffer.data(), *got));
        if (!input) continue;
        if (session != input->session) {
            session = input->session;
            newest.reset();
        }
        if (newest && !IsNewer(input->sequence, *newest)) continue;
        if (arrived) {
            const auto waited = Net::WallMicros() - *arrived;
            input->waitMicros = static_cast<std::uint32_t>(std::clamp<std::int64_t>(waited, 0, 0xFFFFFFFF));
        }
        newest = input->sequence;
        result = input;
    }
    return result;
}

void Channel::Answer(const Input& last, const PadOutputState& output) {
    const auto bytes = EncodeOutput(last, output);
    send(bytes.data(), bytes.size());
}

void Channel::Greet(std::chrono::steady_clock::time_point now) {
    if (greeted && now - *greeted < std::chrono::seconds(1)) return;
    greeted = now;
    const auto bytes = EncodeHello(player);
    send(bytes.data(), bytes.size());
}

void Channel::SetPlayer(std::uint8_t number) {
    if (number == player) return;
    player = number;
    greeted.reset();
}

void Channel::send(const std::uint8_t* bytes, std::size_t size) {
    Net::SendTo(socket, bytes, size, launcherPort);
}

std::unique_ptr<Channel> OpenFromEnvironment() {
    return OpenNamed("ANYPS5_REMOTE_PAD");
}

std::vector<std::unique_ptr<Channel>> OpenAllFromEnvironment() {
    std::vector<std::unique_ptr<Channel>> channels;
    auto first = OpenNamed("ANYPS5_REMOTE_PAD");
    if (!first) return channels;
    channels.push_back(std::move(first));
    for (int player = 2; player <= kPadPlayers; ++player) {
        const auto name = "ANYPS5_REMOTE_PAD_" + std::to_string(player);
        auto channel = OpenNamed(name.c_str());
        if (!channel) break;
        channels.push_back(std::move(channel));
    }
    return channels;
}

bool Wants(const PadInputState& state) {
    constexpr int pushed = 48;
    const bool stick = std::any_of(state.sticks.begin(), state.sticks.end(), [](std::uint8_t axis) { return std::abs(static_cast<int>(axis) - 128) > pushed; });
    return state.buttons != 0 || state.analogButtonsL2 != 0 || state.analogButtonsR2 != 0 || state.touchLeft || state.touchRight ||
        state.touch[0].active || state.touch[1].active || stick;
}

int Seats::Seat(std::uint32_t device, bool wants, std::uint8_t guest) {
    if (const int held = Of(device); held >= 0 || !wants) return held;
    if (guest >= 2 && guest <= holders.size() && !holders[guest - 1u]) {
        holders[guest - 1u] = device;
        return guest - 1;
    }
    for (std::size_t player = guest >= 2 ? 1 : 0; player < holders.size(); ++player) {
        if (holders[player]) continue;
        holders[player] = device;
        return static_cast<int>(player);
    }
    return -1;
}

int Seats::Leave(std::uint32_t device) {
    const int held = Of(device);
    if (held >= 0) holders[static_cast<std::size_t>(held)].reset();
    return held;
}

int Seats::Of(std::uint32_t device) const {
    for (std::size_t player = 0; player < holders.size(); ++player) {
        if (holders[player] == device) return static_cast<int>(player);
    }
    return -1;
}

bool Seats::Held(int player) const {
    return player >= 0 && player < kPadPlayers && holders[static_cast<std::size_t>(player)].has_value();
}

std::array<std::uint8_t, 3> PlayerColor(int player) {
    static constexpr std::array<std::array<std::uint8_t, 3>, kPadPlayers> colors{{{0, 64, 255}, {255, 24, 32}, {32, 220, 64}, {255, 64, 200}}};
    return colors[static_cast<std::size_t>(std::clamp(player, 0, kPadPlayers - 1))];
}

}
