#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>
#include <stdexcept>
#include <string>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

struct GuestVbapParams {
    const AudioOut2Position* positions;
    std::uint32_t numSpeakers;
    std::uint8_t is3d;
    void* memory;
    std::size_t memorySize;
    std::uint32_t reserved;
};

constexpr std::uint32_t MaxSpeakers = 32;
constexpr std::uint32_t AmbisonicsChannelFlag = 0x40;
constexpr std::uint32_t MaxAmbisonicsOrder = 5;

struct SpeakerArray {
    std::uint32_t magic;
    std::uint32_t numSpeakers;
    AudioOut2Position directions[MaxSpeakers];
};
constexpr std::uint32_t SpeakerArrayMagic = 0x53504b41;

SpeakerArray& Array(AudioOut2SpeakerArrayHandle handle) {
    auto* array = static_cast<SpeakerArray*>(handle);
    if (array == nullptr || array->magic != SpeakerArrayMagic) throw std::invalid_argument("invalid speaker array handle");
    return *array;
}

float Sn3d(std::uint32_t acn, const AudioOut2Position& direction) {
    const int n = static_cast<int>(std::sqrt(static_cast<double>(acn)));
    const int m = static_cast<int>(acn) - n * n - n;
    const int am = std::abs(m);
    const double length = std::sqrt(double(direction.x) * direction.x + double(direction.y) * direction.y + double(direction.z) * direction.z);
    const double sinEl = length > 0 ? direction.z / length : 0;
    const double cosEl = std::sqrt(std::max(0.0, 1 - sinEl * sinEl));
    const double azimuth = std::atan2(direction.y, direction.x);
    double legendre = 1;
    for (int i = 1; i <= am; ++i) legendre *= (2 * i - 1) * cosEl;
    if (n > am) {
        double previous = legendre;
        double current = sinEl * (2 * am + 1) * legendre;
        for (int l = am + 2; l <= n; ++l) {
            const double next = (sinEl * (2 * l - 1) * current - (l + am - 1) * previous) / (l - am);
            previous = current;
            current = next;
        }
        legendre = current;
    }
    double ratio = 1;
    for (int i = n - am + 1; i <= n + am; ++i) ratio /= i;
    const double norm = std::sqrt((m == 0 ? 1.0 : 2.0) * ratio);
    return static_cast<float>(norm * legendre * (m < 0 ? std::sin(am * azimuth) : std::cos(am * azimuth)));
}

struct Vector {
    double x;
    double y;
    double z;
};

double Length(const Vector& v) {
    return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

Vector Direction(const AudioOut2Position& position, bool height) {
    return {position.x, position.y, height ? position.z : 0.0f};
}

double Determinant(const Vector& a, const Vector& b, const Vector& c) {
    return a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x);
}

// Picks the triplet whose gains towards the source are all non-negative, the most evenly spread one
// when several enclose it (Cramer's rule on the speaker direction matrix).
bool PanTriplet(const SpeakerArray& array, const Vector& source, std::vector<double>& gains) {
    double best = -1.0;
    for (std::uint32_t i = 0; i < array.numSpeakers; ++i) {
        for (std::uint32_t j = i + 1; j < array.numSpeakers; ++j) {
            for (std::uint32_t k = j + 1; k < array.numSpeakers; ++k) {
                const Vector a = Direction(array.directions[i], true);
                const Vector b = Direction(array.directions[j], true);
                const Vector c = Direction(array.directions[k], true);
                const double det = Determinant(a, b, c);
                if (std::abs(det) <= 1e-9 * Length(a) * Length(b) * Length(c)) continue;
                const double gi = Determinant(source, b, c) / det;
                const double gj = Determinant(a, source, c) / det;
                const double gk = Determinant(a, b, source) / det;
                const double least = std::min({gi, gj, gk});
                if (least < -1e-6 || least <= best) continue;
                best = least;
                std::fill(gains.begin(), gains.end(), 0.0);
                gains[i] = std::max(gi, 0.0);
                gains[j] = std::max(gj, 0.0);
                gains[k] = std::max(gk, 0.0);
            }
        }
    }
    return best > -1.0;
}

// The same on the horizontal plane with the pairs of speakers less than half a turn apart.
bool PanPair(const SpeakerArray& array, const Vector& source, std::vector<double>& gains) {
    double best = -1.0;
    for (std::uint32_t i = 0; i < array.numSpeakers; ++i) {
        for (std::uint32_t j = i + 1; j < array.numSpeakers; ++j) {
            const Vector a = Direction(array.directions[i], false);
            const Vector b = Direction(array.directions[j], false);
            const double det = a.x * b.y - a.y * b.x;
            if (std::abs(det) <= 1e-9 * Length(a) * Length(b)) continue;
            const double gi = (source.x * b.y - source.y * b.x) / det;
            const double gj = (a.x * source.y - a.y * source.x) / det;
            const double least = std::min(gi, gj);
            if (least < -1e-6 || least <= best) continue;
            best = least;
            std::fill(gains.begin(), gains.end(), 0.0);
            gains[i] = std::max(gi, 0.0);
            gains[j] = std::max(gj, 0.0);
        }
    }
    return best > -1.0;
}

std::uint32_t NearestSpeaker(const SpeakerArray& array, const Vector& source) {
    std::uint32_t nearest = 0;
    double closest = -2.0;
    const double sourceLength = Length(source);
    for (std::uint32_t speaker = 0; speaker < array.numSpeakers; ++speaker) {
        const Vector d = Direction(array.directions[speaker], true);
        const double length = Length(d) * sourceLength;
        const double cosine = length > 0.0 ? (d.x * source.x + d.y * source.y + d.z * source.z) / length : -1.0;
        if (cosine > closest) {
            closest = cosine;
            nearest = speaker;
        }
    }
    return nearest;
}

}

extern "C" {

int APS5_VABI sceAudioOut2SpeakerArrayCreate(AudioOut2SpeakerArrayHandle* handle, const void* vbap_params, const void* ambi_params) {
    const auto* params = static_cast<const GuestVbapParams*>(vbap_params);
    if (handle == nullptr || params == nullptr || ambi_params == nullptr || params->positions == nullptr ||
        params->numSpeakers == 0 || params->numSpeakers > MaxSpeakers || params->memory == nullptr ||
        params->memorySize < sizeof(SpeakerArray) || reinterpret_cast<std::uintptr_t>(params->memory) % alignof(SpeakerArray) != 0) {
        APS5_INVALID_ARG_EX;
    }
    auto* array = new (params->memory) SpeakerArray{SpeakerArrayMagic, params->numSpeakers, {}};
    std::copy_n(params->positions, params->numSpeakers, array->directions);
    *handle = array;
    return 0;
}

int APS5_VABI sceAudioOut2SpeakerArrayDestroy(AudioOut2SpeakerArrayHandle handle) {
    Array(handle).magic = 0;
    return 0;
}

int APS5_VABI sceAudioOut2GetSpeakerArrayAmbisonicsCoefficients(AudioOut2SpeakerArrayHandle handle, uint32_t ambisonics_channel, float* coefficients, uint32_t num_coefficients) {
    const auto& array = Array(handle);
    if (coefficients == nullptr || num_coefficients != array.numSpeakers) APS5_INVALID_ARG_EX;
    const std::uint32_t acn = ambisonics_channel & ~AmbisonicsChannelFlag;
    if ((ambisonics_channel & AmbisonicsChannelFlag) == 0 || acn >= (MaxAmbisonicsOrder + 1) * (MaxAmbisonicsOrder + 1)) {
        throw std::invalid_argument("unsupported ambisonics channel " + std::to_string(ambisonics_channel));
    }
    const auto order = static_cast<std::uint32_t>(std::sqrt(static_cast<double>(acn)));
    const std::uint32_t decodable = std::max<std::uint32_t>(1, (array.numSpeakers - 1) / 2);
    for (std::uint32_t speaker = 0; speaker < array.numSpeakers; ++speaker) {
        coefficients[speaker] = order > decodable ? 0.0f : Sn3d(acn, array.directions[speaker]) / static_cast<float>(array.numSpeakers);
    }
    return 0;
}

// Vector base amplitude panning: the source direction is reached with non-negative gains on the pair
// of speakers around it (on the horizontal plane) or, height aware, the triplet around it, the gains
// normalized to unit power. The spread, raised inside the downmix spread radius as the source nears
// the listener, blends towards an equal-power feed of every speaker.
int APS5_VABI sceAudioOut2GetSpeakerArrayCoefficients(AudioOut2SpeakerArrayHandle handle, AudioOut2Position pos, float spread, float* coefficients, uint32_t num_coefficients, uint8_t height_aware, float downmix_spread_radius) {
    const auto& array = Array(handle);
    if (coefficients == nullptr || num_coefficients != array.numSpeakers || !std::isfinite(pos.x) || !std::isfinite(pos.y) || !std::isfinite(pos.z) ||
        !std::isfinite(spread) || spread < 0.0f || spread > 1.0f || !std::isfinite(downmix_spread_radius) || downmix_spread_radius < 0.0f) {
        APS5_INVALID_ARG_EX;
    }
    const std::uint32_t count = array.numSpeakers;
    const Vector source{pos.x, pos.y, height_aware ? pos.z : 0.0f};
    const double distance = Length(source);
    double blend = spread;
    if (downmix_spread_radius > 0.0f && distance < downmix_spread_radius) blend = std::max(blend, 1.0 - distance / downmix_spread_radius);
    std::vector<double> gains(count, 0.0);
    if (distance == 0.0) {
        blend = 1.0;
    } else if (!(height_aware && PanTriplet(array, source, gains)) && !PanPair(array, source, gains)) {
        gains[NearestSpeaker(array, source)] = 1.0;
    }
    const double uniform = 1.0 / std::sqrt(static_cast<double>(count));
    double power = 0.0;
    for (double& gain : gains) {
        gain = (1.0 - blend) * gain + blend * uniform;
        power += gain * gain;
    }
    const double scale = power > 0.0 ? 1.0 / std::sqrt(power) : 0.0;
    for (std::uint32_t speaker = 0; speaker < count; ++speaker) coefficients[speaker] = static_cast<float>(gains[speaker] * scale);
    return 0;
}

size_t APS5_VABI sceAudioOut2GetSpeakerArrayMemorySize(uint32_t num_speakers, uint8_t is_3d, uint8_t is_ambisonics) {
    (void)is_3d;
    (void)is_ambisonics;
    if (num_speakers == 0 || num_speakers > MaxSpeakers) APS5_INVALID_ARG_EX;
    return sizeof(SpeakerArray);
}

int APS5_VABI sceAudioOut2GetSpeakerInfo(AudioOut2SpeakerInfo* info, uint32_t flags) {
    (void)flags;
    if (!info) return static_cast<int>(0x80260502);
    constexpr std::uint8_t SpeakerTypeStereo = 0;
    constexpr std::uint32_t FrontLeftAndRight = 0x3;
    *info = AudioOut2SpeakerInfo{};
    info->type = SpeakerTypeStereo;
    info->available_bits = FrontLeftAndRight;
    info->speaker_angle[0] = {-30, 0};
    info->speaker_angle[1] = {30, 0};
    return 0;
}

}
