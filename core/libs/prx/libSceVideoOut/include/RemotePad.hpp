#ifndef CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP
#define CORE_LIBS_PRX_LIBSCEVIDEOOUT_REMOTEPAD_HPP

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
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

struct Input {
    std::uint32_t sequence = 0;
    std::uint64_t sentMicros = 0;
    PadInputState state{};
};

std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes);
std::array<std::uint8_t, OutputSize> EncodeOutput(const Input& last, const PadOutputState& output);
std::array<std::uint8_t, HelloSize> EncodeHello();
bool IsNewer(std::uint32_t sequence, std::uint32_t than);
PadInputState Merge(const PadInputState& controller, const PadInputState& remote);

class Channel {
public:
    explicit Channel(std::uint16_t launcherPort);
    ~Channel();
    Channel(const Channel&) = delete;
    Channel& operator=(const Channel&) = delete;

    std::optional<Input> Poll(std::chrono::steady_clock::time_point now);
    void Answer(const Input& last, const PadOutputState& output);
    void Greet(std::chrono::steady_clock::time_point now);
    std::uint16_t Port() const { return port; }

private:
    void send(const std::uint8_t* bytes, std::size_t size);

    int socket = -1;
    std::uint16_t port = 0;
    std::uint16_t launcherPort = 0;
    std::optional<std::uint32_t> newest;
    std::optional<std::chrono::steady_clock::time_point> greeted;
};

std::unique_ptr<Channel> OpenFromEnvironment();

}

#endif
