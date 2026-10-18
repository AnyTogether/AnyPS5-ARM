#include "SceTypes.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <vector>

extern "C" {
int APS5_VABI sceAudioOut2SpeakerArrayCreate(AudioOut2SpeakerArrayHandle*, const void*, const void*);
int APS5_VABI sceAudioOut2SpeakerArrayDestroy(AudioOut2SpeakerArrayHandle);
std::size_t APS5_VABI sceAudioOut2GetSpeakerArrayMemorySize(std::uint32_t, std::uint8_t, std::uint8_t);
int APS5_VABI sceAudioOut2GetSpeakerArrayCoefficients(AudioOut2SpeakerArrayHandle, AudioOut2Position, float, float*, std::uint32_t, std::uint8_t, float);
}

static void Check(bool value, int line) {
    if (value) return;
    std::fprintf(stderr, "Speaker array check failed at line %d\n", line);
    std::abort();
}
#define Require(value) Check((value), __LINE__)

namespace {

struct VbapParams {
    const AudioOut2Position* positions;
    std::uint32_t numSpeakers;
    std::uint8_t is3d;
    void* memory;
    std::size_t memorySize;
    std::uint32_t reserved;
};

bool Near(float value, float expected) {
    return std::abs(value - expected) < 1e-4f;
}

template<typename TFunction>
bool ThrowsInvalidArgument(TFunction function) {
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

AudioOut2SpeakerArrayHandle Create(const std::vector<AudioOut2Position>& positions, std::vector<std::uint64_t>& memory) {
    const std::size_t size = sceAudioOut2GetSpeakerArrayMemorySize(static_cast<std::uint32_t>(positions.size()), 1, 0);
    memory.assign((size + 7) / 8, 0);
    const VbapParams vbap{positions.data(), static_cast<std::uint32_t>(positions.size()), 1, memory.data(), size, 0};
    const std::uint32_t ambisonics[8]{};
    AudioOut2SpeakerArrayHandle handle = nullptr;
    Require(sceAudioOut2SpeakerArrayCreate(&handle, &vbap, ambisonics) == 0 && handle != nullptr);
    return handle;
}

void TestStereo() {
    std::vector<std::uint64_t> memory;
    const AudioOut2SpeakerArrayHandle stereo = Create({{-1.0f, 1.0f, 0.0f}, {1.0f, 1.0f, 0.0f}}, memory);
    float gains[2]{};
    const float half = std::sqrt(0.5f);
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 4.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Require(Near(gains[0], half) && Near(gains[1], half));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {3.0f, 3.0f, 2.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Require(Near(gains[0], 0.0f) && Near(gains[1], 1.0f));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {-1.0f, 0.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Require(Near(gains[0], 1.0f) && Near(gains[1], 0.0f));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {1.0f, 1.0f, 0.0f}, 1.0f, gains, 2, 0, 0.0f) == 0);
    Require(Near(gains[0], half) && Near(gains[1], half));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 0.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Require(Near(gains[0], half) && Near(gains[1], half));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.05f, 0.05f, 0.0f}, 0.0f, gains, 2, 0, 1.0f) == 0);
    Require(gains[0] > 0.1f && gains[1] > gains[0] && Near(gains[0] * gains[0] + gains[1] * gains[1], 1.0f));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {5.0f, 5.0f, 0.0f}, 0.0f, gains, 2, 0, 1.0f) == 0);
    Require(Near(gains[0], 0.0f) && Near(gains[1], 1.0f));

    Require(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, gains, 3, 0, 0.0f); }));
    Require(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, nullptr, 2, 0, 0.0f); }));
    Require(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 1.5f, gains, 2, 0, 0.0f); }));
    Require(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {NAN, 1.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f); }));
    Require(sceAudioOut2SpeakerArrayDestroy(stereo) == 0);
    Require(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f); }));
}

void TestHeight() {
    std::vector<std::uint64_t> memory;
    const AudioOut2SpeakerArrayHandle array = Create({{1.0f, 0.0f, 0.0f}, {0.0f, 1.0f, 0.0f}, {-1.0f, 0.0f, 0.0f}, {0.0f, -1.0f, 0.0f}, {0.0f, 0.0f, 1.0f}}, memory);
    float gains[5]{};
    const float third = std::sqrt(1.0f / 3.0f);
    Require(sceAudioOut2GetSpeakerArrayCoefficients(array, {2.0f, 2.0f, 2.0f}, 0.0f, gains, 5, 1, 0.0f) == 0);
    Require(Near(gains[0], third) && Near(gains[1], third) && Near(gains[4], third) && Near(gains[2], 0.0f) && Near(gains[3], 0.0f));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(array, {2.0f, 2.0f, 2.0f}, 0.0f, gains, 5, 0, 0.0f) == 0);
    const float half = std::sqrt(0.5f);
    Require(Near(gains[0], half) && Near(gains[1], half) && Near(gains[4], 0.0f));
    Require(sceAudioOut2GetSpeakerArrayCoefficients(array, {0.0f, 0.0f, 3.0f}, 0.0f, gains, 5, 1, 0.0f) == 0);
    Require(Near(gains[4], 1.0f) && Near(gains[0], 0.0f));
    Require(sceAudioOut2SpeakerArrayDestroy(array) == 0);
}

}

int main() {
    TestStereo();
    TestHeight();
    std::puts("Speaker array tests passed");
    return 0;
}
