#include "prx/libc/include/general/VabiMacros.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

extern "C" {
int APS5_VABI sceAudioOutExGetMonitorInfo(int, int, void*, std::uint32_t);
}

static void Require(bool value, const char* message) {
    if (value) return;
    std::fprintf(stderr, "%s\n", message);
    std::abort();
}

namespace {

constexpr std::uint32_t titleSize = 0x400;
constexpr std::uint32_t minimumSize = 0xA0;
constexpr std::size_t descriptorCountOffset = 0x98;
constexpr std::size_t guardSize = 16;
constexpr std::uint8_t untouched = 0xA5;
constexpr int invalidPointer = static_cast<int>(0x80260004);

bool Throws(int type, int index, std::uint32_t size, const std::string& expected) {
    std::array<std::uint8_t, titleSize> info{};
    try {
        sceAudioOutExGetMonitorInfo(type, index, info.data(), size);
    } catch (const std::runtime_error& error) {
        if (std::string(error.what()) == expected) return true;
        std::fprintf(stderr, "threw: %s\n", error.what());
        return false;
    }
    return false;
}

void CheckEmpty(std::uint32_t size) {
    std::array<std::uint8_t, titleSize + guardSize> buffer{};
    buffer.fill(untouched);
    Require(sceAudioOutExGetMonitorInfo(0, 0, buffer.data(), size) == 0, "the monitor query must succeed");
    for (std::uint32_t i = 0; i < size; i++) {
        Require(buffer[i] == 0, "the monitor info must describe a sink without audio descriptors");
    }
    std::uint32_t descriptors = 0xFFFFFFFFu;
    std::memcpy(&descriptors, buffer.data() + descriptorCountOffset, sizeof(descriptors));
    Require(descriptors == 0, "the audio descriptor count must be 0");
    for (std::size_t i = size; i < buffer.size(); i++) {
        Require(buffer[i] == untouched, "nothing past the declared size may be written");
    }
}

}

int main() {
    CheckEmpty(titleSize);
    CheckEmpty(minimumSize);
    Require(sceAudioOutExGetMonitorInfo(0, 0, nullptr, titleSize) == invalidPointer,
        "a null buffer must report an invalid pointer");
    Require(Throws(0, 0, minimumSize - 1, "sceAudioOutExGetMonitorInfo: size 159 not supported"),
        "a buffer without room for the descriptor count must throw");
    Require(Throws(1, 0, titleSize, "sceAudioOutExGetMonitorInfo: monitor 1, 0 not supported"),
        "a nonzero first argument must throw");
    Require(Throws(0, 1, titleSize, "sceAudioOutExGetMonitorInfo: monitor 0, 1 not supported"),
        "a nonzero second argument must throw");
    return 0;
}
