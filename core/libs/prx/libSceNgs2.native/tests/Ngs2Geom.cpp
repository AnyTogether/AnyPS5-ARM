#include "prx/libSceNgs2.native/tests/Ngs2Test.hpp"
#include "Ngs2Test.hpp"

#include <cstdint>
#include <cstring>
#include <cmath>
#include <limits>
#include <stdexcept>

extern "C" int APS5_VABI sceNgs2GeomApply(const Ngs2GeomListenerWork*, const Ngs2GeomSourceParam*, Ngs2GeomAttribute*, std::uint32_t);

static constexpr float SoundSpeed = 343.0f;
static constexpr std::uint32_t ApplyAngle = 1;
static constexpr std::uint32_t ApplyDoppler = 2;
static constexpr std::uint32_t ApplyMatrix = 4;
static constexpr std::uint32_t ApplyA3d = 8;

static void TestLayouts() {
    Require(sizeof(Ngs2GeomVector) == 12);
    Require(sizeof(Ngs2GeomCone) == 16);
    Require(sizeof(Ngs2GeomRolloff) == 16);
    Require(sizeof(Ngs2GeomListenerParam) == 60);
    Require(sizeof(Ngs2GeomListenerWork) == 96);
    Require(sizeof(Ngs2GeomSourceParam) == 108);
    Require(sizeof(Ngs2GeomA3dAttribute) == 32);
    Require(sizeof(Ngs2GeomAttribute) == 308);
}

static void TestResetListenerParam() {
    Ngs2GeomListenerParam param;
    std::memset(&param, 0x5a, sizeof(param));
    Require(sceNgs2GeomResetListenerParam(&param) == SCE_NGS2_OK);
    Require(param.position.x == 0.0f && param.position.y == 0.0f && param.position.z == 0.0f);
    Require(param.velocity.x == 0.0f && param.velocity.y == 0.0f && param.velocity.z == 0.0f);
    Require(param.orient_front.x == 0.0f && param.orient_front.y == 0.0f && param.orient_front.z == 1.0f);
    Require(param.orient_up.x == 0.0f && param.orient_up.y == 1.0f && param.orient_up.z == 0.0f);
    Require(param.sound_speed == SoundSpeed);
    Require(param.reserved[0] == 0u && param.reserved[1] == 0u);
    Require(sceNgs2GeomResetListenerParam(nullptr) == SCE_NGS2_ERROR_INVALID_OUT_ADDRESS);
}

static void TestResetSourceParam() {
    Ngs2GeomSourceParam param;
    std::memset(&param, 0x5a, sizeof(param));
    Require(sceNgs2GeomResetSourceParam(&param) == SCE_NGS2_OK);
    Require(param.position.x == 0.0f && param.position.y == 0.0f && param.position.z == 0.0f);
    Require(param.velocity.x == 0.0f && param.velocity.y == 0.0f && param.velocity.z == 0.0f);
    Require(param.direction.x == 0.0f && param.direction.y == 0.0f && param.direction.z == 1.0f);
    Require(param.cone.inner_level == 1.0f && param.cone.inner_angle == 360.0f);
    Require(param.cone.outer_level == 1.0f && param.cone.outer_angle == 360.0f);
    Require(param.rolloff.model == 0u);
    Require(param.rolloff.max_distance == 1000000.0f);
    Require(param.rolloff.rolloff_factor == 1.0f);
    Require(param.rolloff.reference_distance == 1.0f);
    Require(param.doppler_factor == 1.0f && param.fbw_level == 1.0f && param.lfe_level == 1.0f);
    Require(param.max_level == 1.0f && param.min_level == 0.0f && param.radius == 0.0f);
    Require(param.num_speakers == 2u && param.matrix_format == 2u);
    Require(param.reserved[0] == 0u && param.reserved[1] == 0u);
    Require(sceNgs2GeomResetSourceParam(nullptr) == SCE_NGS2_ERROR_INVALID_OUT_ADDRESS);
}

static Ngs2GeomListenerParam Listener() {
    Ngs2GeomListenerParam param{};
    Require(sceNgs2GeomResetListenerParam(&param) == SCE_NGS2_OK);
    return param;
}

static void RequireMatrix(const Ngs2GeomListenerWork& work, const float (&expected)[4][4]) {
    for (std::size_t row = 0; row < 4; row++) {
        for (std::size_t column = 0; column < 4; column++) Require(std::abs(work.matrix[row][column] - expected[row][column]) < 0.00001f);
    }
}

static void TestListenerTransform() {
    auto param = Listener();
    param.velocity = {2.0f, -3.0f, 4.0f};
    param.sound_speed = 1500.0f;
    Ngs2GeomListenerWork work;
    std::memset(&work, 0x5a, sizeof(work));
    Require(sceNgs2GeomCalcListener(&param, &work, 0) == SCE_NGS2_OK);
    RequireMatrix(work, {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}});
    Require(work.velocity.x == 2.0f && work.velocity.y == -3.0f && work.velocity.z == 4.0f);
    Require(work.sound_speed == 1500.0f && work.coordinate == 0);
    Require(work.reserved[0] == 0 && work.reserved[1] == 0 && work.reserved[2] == 0);

    param.position = {3.0f, 4.0f, 5.0f};
    Require(sceNgs2GeomCalcListener(&param, &work, 0) == SCE_NGS2_OK);
    RequireMatrix(work, {{1, 0, 0, -3}, {0, 1, 0, -4}, {0, 0, 1, -5}, {0, 0, 0, 1}});

    param.orient_front = {2.0f, 0.0f, 0.0f};
    param.orient_up = {1.0f, 3.0f, 0.0f};
    Require(sceNgs2GeomCalcListener(&param, &work, 0) == SCE_NGS2_OK);
    RequireMatrix(work, {{0, 0, -1, 5}, {0, 1, 0, -4}, {1, 0, 0, -3}, {0, 0, 0, 1}});

    param.orient_front = {0.0f, 0.0f, -2.0f};
    param.orient_up = {0.0f, 3.0f, 0.0f};
    Require(sceNgs2GeomCalcListener(&param, &work, 1) == SCE_NGS2_OK);
    RequireMatrix(work, {{1, 0, 0, -3}, {0, 1, 0, -4}, {0, 0, -1, 5}, {0, 0, 0, 1}});
    Require(work.coordinate == 1);

    param.orient_front = {0.0f, 0.0f, std::numeric_limits<float>::max()};
    param.orient_up = {0.0f, std::numeric_limits<float>::min(), 0.0f};
    Require(sceNgs2GeomCalcListener(&param, &work, 0) == SCE_NGS2_OK);
    RequireMatrix(work, {{1, 0, 0, -3}, {0, 1, 0, -4}, {0, 0, 1, -5}, {0, 0, 0, 1}});
}

static void RejectListener(const Ngs2GeomListenerParam* param, std::uint32_t flags) {
    Ngs2GeomListenerWork work;
    std::memset(&work, 0x5a, sizeof(work));
    unsigned char before[sizeof(work)];
    std::memcpy(before, &work, sizeof(work));
    bool rejected = false;
    try {
        sceNgs2GeomCalcListener(param, &work, flags);

    } catch (const std::exception&) {
        rejected = true;
    }
    Require(rejected);
    Require(std::memcmp(before, &work, sizeof(work)) == 0);
}

static void TestInvalidListener() {
    auto param = Listener();
    Require(sceNgs2GeomCalcListener(&param, nullptr, 0) == SCE_NGS2_ERROR_INVALID_OUT_ADDRESS);
    Ngs2GeomListenerWork work;
    std::memset(&work, 0x5a, sizeof(work));
    unsigned char before[sizeof(work)];
    std::memcpy(before, &work, sizeof(work));
    Require(sceNgs2GeomCalcListener(nullptr, &work, 0) == static_cast<int>(0x804A8461));
    Require(sceNgs2GeomCalcListener(nullptr, &work, 2) == static_cast<int>(0x804A8461));
    Require(sceNgs2GeomCalcListener(nullptr, nullptr, 0) == static_cast<int>(0x804A8461));
    Require(sceNgs2GeomCalcListener(&param, &work, 2) == static_cast<int>(0x804A8463));
    Require(sceNgs2GeomCalcListener(&param, &work, 0x80000000u) == static_cast<int>(0x804A8463));
    Require(sceNgs2GeomCalcListener(&param, &work, 0xffffffffu) == static_cast<int>(0x804A8463));
    Require(sceNgs2GeomCalcListener(&param, nullptr, 2) == static_cast<int>(0x804A8010));
    Require(std::memcmp(before, &work, sizeof(work)) == 0);
    for (const float value : {0.0f, -1.0f, std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()}) {
        param.sound_speed = value;
        RejectListener(&param, 0);
    }
    param = Listener();
    param.orient_front = {};
    RejectListener(&param, 0);
    param = Listener();
    param.orient_up = {};
    RejectListener(&param, 0);
    param = Listener();
    param.orient_up = param.orient_front;
    Ngs2GeomListenerWork parallelWork{};
    Require(sceNgs2GeomCalcListener(&param, &parallelWork, 0) == SCE_NGS2_OK);
    RequireMatrix(parallelWork, {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}});
    param = Listener();
    param.position.x = std::numeric_limits<float>::infinity();
    RejectListener(&param, 0);
    param = Listener();
    param.velocity.z = std::numeric_limits<float>::quiet_NaN();
    RejectListener(&param, 0);
    param = Listener();
    param.orient_front.y = std::numeric_limits<float>::quiet_NaN();
    RejectListener(&param, 0);
}

static bool Near(float value, float expected) {
    return std::abs(value - expected) < 1e-4f;
}

template<typename TFunction>
static bool ThrowsInvalidArgument(TFunction function) {
    try {
        function();
    } catch (const std::invalid_argument&) {
        return true;
    }
    return false;
}

static void TestApply() {
    const auto param = Listener();
    Ngs2GeomListenerWork listener{};
    Require(sceNgs2GeomCalcListener(&param, &listener, 0) == SCE_NGS2_OK);
    Ngs2GeomSourceParam source{};
    Require(sceNgs2GeomResetSourceParam(&source) == SCE_NGS2_OK);

    // A source straight ahead, 10 away.
    source.position = {0.0f, 0.0f, 10.0f};
    Ngs2GeomAttribute attribute{};
    attribute.pitch_ratio = -1.0f;
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK);
    Require(Near(attribute.a3d_attrib.position.x, 0.0f) && Near(attribute.a3d_attrib.position.z, 10.0f) && Near(attribute.a3d_attrib.volume, 0.1f));
    Require(attribute.pitch_ratio == -1.0f);

    // A source at the listener's right pans to the right speaker; without the angle it pans straight ahead.
    source.position = {3.0f, 0.0f, 0.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d | ApplyAngle | ApplyMatrix) == SCE_NGS2_OK);
    Require(Near(attribute.a3d_attrib.position.x, 3.0f) && Near(attribute.a3d_attrib.position.z, 0.0f));
    Require(Near(attribute.level[0], 0.0f) && Near(attribute.level[1], 1.0f / 3.0f) && attribute.level[2] == 0.0f);
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyMatrix) == SCE_NGS2_OK);
    Require(Near(attribute.level[0], attribute.level[1]) && Near(attribute.level[0] * attribute.level[0] * 2.0f, 1.0f / 9.0f));

    // Linear rolloff, clamped, and the level limits.
    source.position = {0.0f, 0.0f, 10.0f};
    source.rolloff = {1, 20.0f, 1.0f, 2.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 1.0f - 8.0f / 18.0f));
    source.rolloff = {4, 5.0f, 1.0f, 1.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 0.0f));
    source.min_level = 0.25f;
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 0.25f));
    source.min_level = 0.0f;
    source.rolloff = {2, 1000.0f, 2.0f, 1.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 0.01f));

    // A cone pointing away from the listener leaves the outer level.
    source.rolloff = {3, 1000.0f, 0.0f, 1.0f};
    source.direction = {0.0f, 0.0f, 1.0f};
    source.cone = {1.0f, 60.0f, 0.5f, 120.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 0.5f));
    source.direction = {0.0f, 0.0f, -1.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyA3d) == SCE_NGS2_OK && Near(attribute.a3d_attrib.volume, 1.0f));

    // A source moving towards the listener sounds higher, one moving away lower.
    source.velocity = {0.0f, 0.0f, -34.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyDoppler) == SCE_NGS2_OK && Near(attribute.pitch_ratio, SoundSpeed / (SoundSpeed - 34.0f)));
    source.velocity = {0.0f, 0.0f, 34.0f};
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyDoppler) == SCE_NGS2_OK && Near(attribute.pitch_ratio, SoundSpeed / (SoundSpeed + 34.0f)));
    source.doppler_factor = 0.0f;
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyDoppler) == SCE_NGS2_OK && attribute.pitch_ratio == 1.0f);

    // Inside its radius a source spreads over every speaker; surround layouts feed the LFE.
    Require(sceNgs2GeomResetSourceParam(&source) == SCE_NGS2_OK);
    source.position = {0.5f, 0.0f, 0.0f};
    source.radius = 1.0f;
    source.lfe_level = 0.5f;
    source.num_speakers = 5;
    source.matrix_format = 6;
    Require(sceNgs2GeomApply(&listener, &source, &attribute, ApplyAngle | ApplyMatrix) == SCE_NGS2_OK);
    Require(attribute.level[0] > 0.0f && attribute.level[1] > attribute.level[0] && Near(attribute.level[3], 0.5f) && attribute.level[6] == 0.0f);

    Require(sceNgs2GeomApply(&listener, &source, nullptr, ApplyMatrix) == SCE_NGS2_ERROR_INVALID_OUT_ADDRESS);
    Require(ThrowsInvalidArgument([&] { sceNgs2GeomApply(nullptr, &source, &attribute, ApplyMatrix); }));
    Require(ThrowsInvalidArgument([&] { sceNgs2GeomApply(&listener, &source, &attribute, 0x20); }));
    source.rolloff.model = 6;
    Require(ThrowsInvalidArgument([&] { sceNgs2GeomApply(&listener, &source, &attribute, ApplyMatrix); }));
}

int main() {
    TestLayouts();
    TestResetListenerParam();
    TestResetSourceParam();
    TestListenerTransform();
    TestInvalidListener();
    TestApply();
    return 0;
}
