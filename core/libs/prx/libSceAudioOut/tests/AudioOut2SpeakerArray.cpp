#include "prx/libSceAudioOut/include/AudioOut2.hpp"
#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <vector>

static void Require(bool value, const char* message) {
    if (value) return;
    std::fprintf(stderr, "%s\n", message);
    std::abort();
}

template<typename TFunction>
static bool RejectsArgument(TFunction&& function) {
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

struct VbapParams {
    const AudioOut2Position* positions;
    std::uint32_t numSpeakers;
    std::uint8_t is3d;
    void* memory;
    std::size_t memorySize;
    std::uint32_t reserved;
};

static bool Near(float value, float expected) {
    return std::fabs(value - expected) < 1e-5f;
}

static void TestCreateAndAmbisonics() {
    const AudioOut2Position square[4] = {{1, 0, 0}, {0, 1, 0}, {-1, 0, 0}, {0, -1, 0}};
    alignas(16) unsigned char memory[512] = {};
    VbapParams params{square, 4, 0, memory, sizeof(memory), 0};
    AudioOut2SpeakerArrayHandle array = nullptr;
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(nullptr, &params, nullptr); }), "a null handle output was accepted");
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(&array, nullptr, nullptr); }), "null parameters were accepted");
    VbapParams none = params;
    none.numSpeakers = 0;
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(&array, &none, nullptr); }), "an array without speakers was accepted");
    VbapParams tooMany = params;
    tooMany.numSpeakers = 33;
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(&array, &tooMany, nullptr); }), "33 speakers were accepted");
    VbapParams small = params;
    small.memorySize = 16;
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(&array, &small, nullptr); }), "memory too small for the array was accepted");
    VbapParams misaligned = params;
    misaligned.memory = memory + 1;
    Require(RejectsArgument([&] { sceAudioOut2SpeakerArrayCreate(&array, &misaligned, nullptr); }), "misaligned memory was accepted");
    Require(array == nullptr, "a rejected creation wrote the handle");
    Require(sceAudioOut2SpeakerArrayCreate(&array, &params, nullptr) == 0 && array == memory, "the array was not placed in the given memory");

    constexpr std::uint32_t ambisonics = 0x40;
    float coefficients[4] = {};
    Require(sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics | 0, coefficients, 4) == 0, "W channel coefficients failed");
    for (const float coefficient : coefficients) Require(Near(coefficient, 0.25f), "the W channel is not split evenly over four speakers");
    Require(sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics | 1, coefficients, 4) == 0, "Y channel coefficients failed");
    Require(Near(coefficients[0], 0.0f) && Near(coefficients[1], 0.25f) && Near(coefficients[2], 0.0f) && Near(coefficients[3], -0.25f), "the Y channel does not follow the sine of each azimuth");
    Require(sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics | 3, coefficients, 4) == 0, "X channel coefficients failed");
    Require(Near(coefficients[0], 0.25f) && Near(coefficients[1], 0.0f) && Near(coefficients[2], -0.25f) && Near(coefficients[3], 0.0f), "the X channel does not follow the cosine of each azimuth");
    Require(sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics | 4, coefficients, 4) == 0, "second-order coefficients failed");
    for (const float coefficient : coefficients) Require(coefficient == 0.0f, "four speakers decoded a second-order channel");
    Require(RejectsArgument([&] { sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, 0, coefficients, 4); }), "a channel without the ambisonics flag was accepted");
    Require(RejectsArgument([&] { sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics | 36, coefficients, 4); }), "a sixth-order channel was accepted");
    Require(RejectsArgument([&] { sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics, coefficients, 3); }), "a coefficient count other than the speaker count was accepted");
    Require(RejectsArgument([&] { sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(array, ambisonics, nullptr, 4); }), "null coefficients were accepted");
    alignas(16) unsigned char notArray[512] = {};
    Require(RejectsArgument([&] { sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(notArray, ambisonics, coefficients, 4); }), "memory that holds no array was accepted");
}

static void Check(bool value, int line) {
    if (value) return;
    std::fprintf(stderr, "Speaker array check failed at line %d\n", line);
    std::abort();
}
#define Expect(value) Check((value), __LINE__)

namespace {

bool NearGain(float value, float expected) {
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
    Expect(sceAudioOut2SpeakerArrayCreate(&handle, &vbap, ambisonics) == 0 && handle != nullptr);
    return handle;
}

void TestStereo() {
    std::vector<std::uint64_t> memory;
    const AudioOut2SpeakerArrayHandle stereo = Create({{-1.0f, 1.0f, 0.0f}, {1.0f, 1.0f, 0.0f}}, memory);
    float gains[2]{};
    const float half = std::sqrt(0.5f);
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 4.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Expect(NearGain(gains[0], half) && NearGain(gains[1], half));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {3.0f, 3.0f, 2.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Expect(NearGain(gains[0], 0.0f) && NearGain(gains[1], 1.0f));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {-1.0f, 0.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Expect(NearGain(gains[0], 1.0f) && NearGain(gains[1], 0.0f));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {1.0f, 1.0f, 0.0f}, 1.0f, gains, 2, 0, 0.0f) == 0);
    Expect(NearGain(gains[0], half) && NearGain(gains[1], half));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 0.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f) == 0);
    Expect(NearGain(gains[0], half) && NearGain(gains[1], half));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.05f, 0.05f, 0.0f}, 0.0f, gains, 2, 0, 1.0f) == 0);
    Expect(gains[0] > 0.1f && gains[1] > gains[0] && NearGain(gains[0] * gains[0] + gains[1] * gains[1], 1.0f));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(stereo, {5.0f, 5.0f, 0.0f}, 0.0f, gains, 2, 0, 1.0f) == 0);
    Expect(NearGain(gains[0], 0.0f) && NearGain(gains[1], 1.0f));

    Expect(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, gains, 3, 0, 0.0f); }));
    Expect(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, nullptr, 2, 0, 0.0f); }));
    Expect(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 1.5f, gains, 2, 0, 0.0f); }));
    Expect(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {NAN, 1.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f); }));
    Expect(sceAudioOut2SpeakerArrayDestroy(stereo) == 0);
    Expect(ThrowsInvalidArgument([&] { sceAudioOut2GetSpeakerArrayCoefficients(stereo, {0.0f, 1.0f, 0.0f}, 0.0f, gains, 2, 0, 0.0f); }));
}

void TestHeight() {
    std::vector<std::uint64_t> memory;
    const AudioOut2SpeakerArrayHandle array = Create({{1.0f, 0.0f, 0.0f}, {0.0f, 1.0f, 0.0f}, {-1.0f, 0.0f, 0.0f}, {0.0f, -1.0f, 0.0f}, {0.0f, 0.0f, 1.0f}}, memory);
    float gains[5]{};
    const float third = std::sqrt(1.0f / 3.0f);
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(array, {2.0f, 2.0f, 2.0f}, 0.0f, gains, 5, 1, 0.0f) == 0);
    Expect(NearGain(gains[0], third) && NearGain(gains[1], third) && NearGain(gains[4], third) && NearGain(gains[2], 0.0f) && NearGain(gains[3], 0.0f));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(array, {2.0f, 2.0f, 2.0f}, 0.0f, gains, 5, 0, 0.0f) == 0);
    const float half = std::sqrt(0.5f);
    Expect(NearGain(gains[0], half) && NearGain(gains[1], half) && NearGain(gains[4], 0.0f));
    Expect(sceAudioOut2GetSpeakerArrayCoefficients(array, {0.0f, 0.0f, 3.0f}, 0.0f, gains, 5, 1, 0.0f) == 0);
    Expect(NearGain(gains[4], 1.0f) && NearGain(gains[0], 0.0f));
    Expect(sceAudioOut2SpeakerArrayDestroy(array) == 0);
}

}

int main() {
    TestCreateAndAmbisonics();
    TestStereo();
    TestHeight();
    std::puts("AudioOut2 speaker array tests passed");
    return 0;
}
