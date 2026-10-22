#include "prx/libSceVideoOut/include/RemotePad.hpp"
#include <algorithm>
#include <arpa/inet.h>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

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

std::runtime_error badAddress(std::string_view value) {
    return std::runtime_error("ANYPS5_REMOTE_PAD must be 127.0.0.1:<port from 1 to 65535>, not \"" + std::string(value) + "\"");
}

}

std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes) {
    if (bytes.size() != InputSize) return std::nullopt;
    if (read<std::uint32_t>(bytes, 0) != InputMagic || read<std::uint16_t>(bytes, 4) != Version || read<std::uint16_t>(bytes, 6) != InputSize) return std::nullopt;
    Input input;
    input.sequence = read<std::uint32_t>(bytes, 8);
    input.sentMicros = read<std::uint64_t>(bytes, 16);
    input.session = read<std::uint64_t>(bytes, 24);
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

std::array<std::uint8_t, HelloSize> EncodeHello() {
    std::array<std::uint8_t, HelloSize> bytes{};
    write<std::uint32_t>(bytes.data(), 0, HelloMagic);
    write<std::uint16_t>(bytes.data(), 4, Version);
    write<std::uint16_t>(bytes.data(), 6, static_cast<std::uint16_t>(HelloSize));
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
    socket = ::socket(AF_INET, SOCK_DGRAM, 0);
    if (socket < 0) throw std::runtime_error(std::string("remote pad: cannot open a socket: ") + std::strerror(errno));
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t length = sizeof(address);
    const int stamped = 1;
    if (::setsockopt(socket, SOL_SOCKET, SO_TIMESTAMP, &stamped, sizeof(stamped)) != 0 ||
        ::bind(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        ::getsockname(socket, reinterpret_cast<sockaddr*>(&address), &length) != 0 ||
        ::fcntl(socket, F_SETFL, ::fcntl(socket, F_GETFL) | O_NONBLOCK) != 0) {
        const auto error = std::string(std::strerror(errno));
        ::close(socket);
        throw std::runtime_error("remote pad: cannot bind 127.0.0.1: " + error);
    }
    port = ntohs(address.sin_port);
}

Channel::~Channel() {
    if (socket >= 0) ::close(socket);
}

std::optional<Input> Channel::Poll(std::chrono::steady_clock::time_point) {
    std::optional<Input> result;
    std::array<std::uint8_t, InputSize + 1> buffer{};
    alignas(cmsghdr) std::array<std::uint8_t, CMSG_SPACE(sizeof(timeval))> control{};
    while (true) {
        iovec vector{buffer.data(), buffer.size()};
        msghdr message{};
        message.msg_iov = &vector;
        message.msg_iovlen = 1;
        message.msg_control = control.data();
        message.msg_controllen = static_cast<socklen_t>(control.size());
        const auto got = ::recvmsg(socket, &message, 0);
        if (got < 0) break;
        auto input = DecodeInput(std::span<const std::uint8_t>(buffer.data(), static_cast<std::size_t>(got)));
        if (!input) continue;
        if (session != input->session) {
            session = input->session;
            newest.reset();
        }
        if (newest && !IsNewer(input->sequence, *newest)) continue;
        for (auto* header = CMSG_FIRSTHDR(&message); header != nullptr; header = CMSG_NXTHDR(&message, header)) {
            if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_TIMESTAMP) continue;
            timeval arrived{};
            std::memcpy(&arrived, CMSG_DATA(header), sizeof(arrived));
            timeval current{};
            ::gettimeofday(&current, nullptr);
            const auto waited = (static_cast<std::int64_t>(current.tv_sec) - arrived.tv_sec) * 1000000 + (static_cast<std::int64_t>(current.tv_usec) - arrived.tv_usec);
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
    const auto bytes = EncodeHello();
    send(bytes.data(), bytes.size());
}

void Channel::send(const std::uint8_t* bytes, std::size_t size) {
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(launcherPort);
    ::sendto(socket, bytes, size, 0, reinterpret_cast<sockaddr*>(&address), sizeof(address));
}

std::unique_ptr<Channel> OpenFromEnvironment() {
    const char* raw = std::getenv("ANYPS5_REMOTE_PAD");
    if (raw == nullptr || *raw == '\0') return nullptr;
    const std::string_view value(raw);
    constexpr std::string_view host = "127.0.0.1:";
    if (!value.starts_with(host)) throw badAddress(value);
    const auto digits = value.substr(host.size());
    unsigned port = 0;
    const auto [end, error] = std::from_chars(digits.data(), digits.data() + digits.size(), port);
    if (error != std::errc{} || end != digits.data() + digits.size() || port == 0 || port > 65535) throw badAddress(value);
    return std::make_unique<Channel>(static_cast<std::uint16_t>(port));
}

}
