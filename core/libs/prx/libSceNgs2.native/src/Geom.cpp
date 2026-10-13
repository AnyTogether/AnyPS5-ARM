#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iterator>
#include <numbers>
#include <stdexcept>

#include "prx/libc/include/General.hpp"
#include "Ngs2Internal.hpp"

static constexpr float DEFAULT_SOUND_SPEED = 343.0f;

namespace {

constexpr std::uint32_t APPLY_SOURCE_ANGLE = 1u << 0;
constexpr std::uint32_t APPLY_SOURCE_DOPPLER = 1u << 1;
constexpr std::uint32_t APPLY_VOLUME_MATRIX = 1u << 2;
constexpr std::uint32_t APPLY_A3D_ATTRIBUTE = 1u << 3;
constexpr std::uint32_t APPLY_A3D_AMBISONICS = 1u << 4;
constexpr std::uint32_t ROLLOFF_CLAMPED_INVERSE = 3;
constexpr std::uint32_t ROLLOFF_MODELS = 6;

struct Vec {
    float x;
    float y;
    float z;
};

Vec Of(const Ngs2GeomVector& v) {
    return {v.x, v.y, v.z};
}

float Dot(const Vec& a, const Vec& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

float Length(const Vec& v) {
    return std::sqrt(Dot(v, v));
}

Vec Scale(const Vec& v, float factor) {
    return {v.x * factor, v.y * factor, v.z * factor};
}

bool Finite(const Vec& v) {
    return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

// The listener matrix maps the scene into the listener's frame: x to its right, y up and z ahead.
Vec Rotate(const Ngs2GeomListenerWork& work, const Vec& v) {
    const auto& m = work.matrix;
    return {m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z, m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z, m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z};
}

Vec Transform(const Ngs2GeomListenerWork& work, const Vec& v) {
    const Vec rotated = Rotate(work, v);
    return {rotated.x + work.matrix[0][3], rotated.y + work.matrix[1][3], rotated.z + work.matrix[2][3]};
}

// Distance attenuation with the OpenAL distance models: the inverse, linear and exponential curves
// start at the reference distance, and the clamped ones hold their level past the maximum distance.
float Rolloff(const Ngs2GeomRolloff& rolloff, float distance) {
    const float reference = rolloff.reference_distance;
    const float maximum = rolloff.max_distance;
    const float factor = rolloff.rolloff_factor;
    float d = std::max(distance, reference);
    if (rolloff.model >= ROLLOFF_CLAMPED_INVERSE) d = std::min(d, maximum);
    switch (rolloff.model % ROLLOFF_CLAMPED_INVERSE) {
        case 0: return reference / (reference + factor * (d - reference));
        case 1: return maximum > reference ? std::clamp(1.0f - factor * (d - reference) / (maximum - reference), 0.0f, 1.0f) : 1.0f;
        default: return std::pow(d / reference, -factor);
    }
}

// The cone angles are whole apertures in degrees around the source's direction; between them the
// level moves linearly from the inner to the outer level.
float ConeLevel(const Ngs2GeomCone& cone, const Vec& direction, const Vec& toListener) {
    const float directionLength = Length(direction);
    const float listenerLength = Length(toListener);
    if (directionLength == 0.0f || listenerLength == 0.0f) return cone.inner_level;
    const float cosine = std::clamp(Dot(direction, toListener) / (directionLength * listenerLength), -1.0f, 1.0f);
    const float angle = std::acos(cosine) * 180.0f / std::numbers::pi_v<float>;
    const float inner = cone.inner_angle * 0.5f;
    const float outer = cone.outer_angle * 0.5f;
    if (angle <= inner) return cone.inner_level;
    if (angle >= outer || outer <= inner) return cone.outer_level;
    return cone.inner_level + (cone.outer_level - cone.inner_level) * (angle - inner) / (outer - inner);
}

// The OpenAL Doppler shift, with both velocities projected on the line from the source to the listener.
float DopplerRatio(const Ngs2GeomListenerWork& listener, const Ngs2GeomSourceParam& source, const Vec& position) {
    const float distance = Length(position);
    const float factor = source.doppler_factor;
    const float speed = listener.sound_speed;
    if (distance == 0.0f || factor == 0.0f) return 1.0f;
    const Vec toListener = Scale(position, -1.0f / distance);
    const float limit = speed / factor * 0.999f;
    const float listenerSpeed = std::min(Dot(Rotate(listener, Of(listener.velocity)), toListener), limit);
    const float sourceSpeed = std::min(Dot(Rotate(listener, Of(source.velocity)), toListener), limit);
    return (speed - factor * listenerSpeed) / (speed - factor * sourceSpeed);
}

void ValidateSource(const Ngs2GeomSourceParam& source) {
    const auto& rolloff = source.rolloff;
    const auto& cone = source.cone;
    if (!Finite(Of(source.position)) || !Finite(Of(source.velocity)) || !Finite(Of(source.direction)) || rolloff.model >= ROLLOFF_MODELS ||
        !(rolloff.reference_distance > 0.0f) || !(rolloff.max_distance >= rolloff.reference_distance) || !(rolloff.rolloff_factor >= 0.0f) ||
        !(cone.inner_angle >= 0.0f && cone.inner_angle <= 360.0f) || !(cone.outer_angle >= 0.0f && cone.outer_angle <= 360.0f) ||
        !(source.min_level <= source.max_level) || !(source.radius >= 0.0f) || !(source.doppler_factor >= 0.0f)) {
        APS5_INVALID_ARG_EX;
    }
}

}

int Ngs2GeomCalcListener(const Ngs2GeomListenerParam* param, Ngs2GeomListenerWork* outWork, std::uint32_t flags) {
    if (param == nullptr) APS5_INVALID_ARG_EX;
    if (outWork == nullptr) return SCE_NGS2_ERROR_INVALID_OUT_ADDRESS;
    if (flags != 0) throw std::runtime_error("NGS2: listener coordinate flags are unsupported");
    if (param->position.x != 0.0f || param->position.y != 0.0f || param->position.z != 0.0f)
        throw std::runtime_error("NGS2: listener translation is unsupported");
    if (param->orient_front.x != 0.0f || param->orient_front.y != 0.0f || param->orient_front.z != 1.0f ||
        param->orient_up.x != 0.0f || param->orient_up.y != 1.0f || param->orient_up.z != 0.0f)
        throw std::runtime_error("NGS2: non-default listener orientation is unsupported");
    if (!std::isfinite(param->velocity.x) || !std::isfinite(param->velocity.y) || !std::isfinite(param->velocity.z)) APS5_INVALID_ARG_EX;
    if (!std::isfinite(param->sound_speed) || param->sound_speed <= 0.0f) APS5_INVALID_ARG_EX;
    Ngs2GeomListenerWork work{};
    for (std::size_t i = 0; i < 4; i++) work.matrix[i][i] = 1.0f;
    work.velocity = param->velocity;
    work.sound_speed = param->sound_speed;
    *outWork = work;
    return SCE_NGS2_OK;
}

int Ngs2GeomResetListenerParam(Ngs2GeomListenerParam* out_listener_param) {
    if (out_listener_param == nullptr) return SCE_NGS2_ERROR_INVALID_OUT_ADDRESS;
    *out_listener_param = {};
    out_listener_param->orient_front.z = 1.0f;
    out_listener_param->orient_up.y = 1.0f;
    out_listener_param->sound_speed = DEFAULT_SOUND_SPEED;
    return SCE_NGS2_OK;
}

int Ngs2GeomResetSourceParam(Ngs2GeomSourceParam* out_source_param) {
    if (out_source_param == nullptr) return SCE_NGS2_ERROR_INVALID_OUT_ADDRESS;
    *out_source_param = {};
    out_source_param->direction.z = 1.0f;
    out_source_param->cone.inner_level = 1.0f;
    out_source_param->cone.inner_angle = 360.0f;
    out_source_param->cone.outer_level = 1.0f;
    out_source_param->cone.outer_angle = 360.0f;
    out_source_param->rolloff.max_distance = 1000000.0f;
    out_source_param->rolloff.rolloff_factor = 1.0f;
    out_source_param->rolloff.reference_distance = 1.0f;
    out_source_param->doppler_factor = 1.0f;
    out_source_param->fbw_level = 1.0f;
    out_source_param->lfe_level = 1.0f;
    out_source_param->max_level = 1.0f;
    out_source_param->num_speakers = 2;
    out_source_param->matrix_format = 2;
    return SCE_NGS2_OK;
}

#pragma GCC visibility push(default)

extern "C" {

// Fills only what the flags ask for. The volume matrix is the one of a point (mono) source, levels
// [0, matrix_format), panned by sceNgs2PanGetVolumeMatrix over num_speakers; without the source angle
// the source is panned straight ahead, and inside the radius it spreads towards every speaker.
int APS5_VABI sceNgs2GeomApply(const Ngs2GeomListenerWork* listener, const Ngs2GeomSourceParam* source, Ngs2GeomAttribute* out_attrib, uint32_t flags) {
    constexpr std::uint32_t known = APPLY_SOURCE_ANGLE | APPLY_SOURCE_DOPPLER | APPLY_VOLUME_MATRIX | APPLY_A3D_ATTRIBUTE | APPLY_A3D_AMBISONICS;
    if (listener == nullptr || source == nullptr || (flags & ~known) != 0 || !(listener->sound_speed > 0.0f)) APS5_INVALID_ARG_EX;
    if (out_attrib == nullptr) return SCE_NGS2_ERROR_INVALID_OUT_ADDRESS;
    ValidateSource(*source);
    if ((flags & APPLY_A3D_AMBISONICS) != 0) throw std::runtime_error("NGS2: the ambisonic geometry attribute is not implemented");
    const Vec position = Transform(*listener, Of(source->position));
    const float distance = Length(position);
    const float attenuation = Rolloff(source->rolloff, distance) * ConeLevel(source->cone, Rotate(*listener, Of(source->direction)), Scale(position, -1.0f));
    const float level = std::clamp(attenuation, source->min_level, source->max_level);
    if ((flags & APPLY_SOURCE_DOPPLER) != 0) out_attrib->pitch_ratio = DopplerRatio(*listener, *source, position);
    if ((flags & APPLY_VOLUME_MATRIX) != 0) {
        Ngs2PanWork work{};
        Ngs2PanInit(&work, nullptr, 360.0f, source->num_speakers);
        float angle = 0.0f;
        if ((flags & APPLY_SOURCE_ANGLE) != 0 && distance > 0.0f) {
            angle = std::atan2(position.x, position.z) * 180.0f / std::numbers::pi_v<float>;
            if (angle < 0.0f) angle += 360.0f;
            if (angle >= 360.0f) angle -= 360.0f;
        }
        float focus = 1.0f;
        if (source->radius > 0.0f && distance < source->radius) focus = distance / source->radius;
        else if (distance == 0.0f) focus = 0.0f;
        const Ngs2PanParam pan{angle, focus, source->fbw_level * level, source->lfe_level * level};
        std::fill(std::begin(out_attrib->level), std::end(out_attrib->level), 0.0f);
        Ngs2PanGetVolumeMatrix(&work, &pan, 1, source->matrix_format, out_attrib->level);
    }
    if ((flags & APPLY_A3D_ATTRIBUTE) != 0) {
        out_attrib->a3d_attrib.position = {position.x, position.y, position.z};
        out_attrib->a3d_attrib.volume = level;
    }
    return SCE_NGS2_OK;
}

}

#pragma GCC visibility pop
