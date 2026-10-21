#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
#include "prx/libc/include/General.hpp"
#include "H264Fixture.hpp"

struct ConfigInfo {
    std::uint64_t thisSize;
    std::uint32_t codecType;
    std::uint32_t profile;
    std::uint32_t maxLevel;
    std::int32_t maxFrameWidth;
    std::int32_t maxFrameHeight;
    std::int32_t maxDpbFrameCount;
    std::uint64_t videodecFlags;
};

struct ResourceInfo {
    std::uint64_t thisSize;
    std::uint64_t cpuMemorySize;
    void* cpuMemory;
    std::uint64_t cpuGpuMemorySize;
    void* cpuGpuMemory;
    std::uint64_t maxFrameBufferSize;
    std::uint32_t frameBufferAlignment;
};

struct Ctrl {
    std::uint64_t thisSize;
    void* handle;
    std::uint64_t version;
};

struct FrameBuffer {
    std::uint64_t thisSize;
    void* frameBuffer;
    std::uint64_t frameBufferSize;
};

struct AvcInfo {
    std::uint32_t numUnitsInTick;
    std::uint32_t timeScale;
    std::uint8_t fixedFrameRateFlag;
    std::uint8_t aspectRatioIdc;
    std::uint16_t sarWidth;
    std::uint16_t sarHeight;
    std::uint8_t colourPrimaries;
    std::uint8_t transferCharacteristics;
    std::uint8_t matrixCoefficients;
    std::uint8_t videoFullRangeFlag;
    std::uint32_t frameCropLeftOffset;
    std::uint32_t frameCropRightOffset;
    std::uint32_t frameCropTopOffset;
    std::uint32_t frameCropBottomOffset;
};

union CodecInfo {
    std::uint8_t reserved[64];
    AvcInfo avc;
};

struct PictureInfo {
    std::uint64_t thisSize;
    std::uint32_t isValid;
    std::uint32_t codecType;
    std::uint32_t frameWidth;
    std::uint32_t framePitch;
    std::uint32_t frameHeight;
    std::uint32_t isErrorPic;
    std::uint64_t ptsData;
    std::uint64_t attachedData;
    CodecInfo codec;
};

struct InputData {
    std::uint64_t thisSize;
    const std::uint8_t* auData;
    std::uint64_t auSize;
    std::uint64_t ptsData;
    std::uint64_t dtsData;
    std::uint64_t attachedData;
};

static_assert(sizeof(PictureInfo) == 112 && sizeof(AvcInfo) == 36);
static_assert(sizeof(ConfigInfo) == 40 && sizeof(ResourceInfo) == 56 && sizeof(Ctrl) == 24);

extern "C" {
int APS5_VABI sceVideodecCreateDecoder(const ConfigInfo*, const ResourceInfo*, Ctrl*);
int APS5_VABI sceVideodecDecode(Ctrl*, const InputData*, FrameBuffer*, PictureInfo*);
int APS5_VABI sceVideodecDeleteDecoder(Ctrl*);
int APS5_VABI sceVideodecFlush(Ctrl*, FrameBuffer*, PictureInfo*);
int APS5_VABI sceVideodecReset(Ctrl*);
}

namespace {

using namespace H264Fixture;

constexpr int ErrorApiFail = static_cast<int>(0x80C10000);
constexpr int ErrorStructSize = static_cast<int>(0x80C10002);
constexpr int ErrorHandle = static_cast<int>(0x80C10003);
constexpr int ErrorAuSize = static_cast<int>(0x80C10009);
constexpr int ErrorAuPointer = static_cast<int>(0x80C1000A);
constexpr int ErrorFrameBufferSize = static_cast<int>(0x80C1000B);
constexpr int ErrorFrameBufferPointer = static_cast<int>(0x80C1000C);
constexpr int ErrorArgumentPointer = static_cast<int>(0x80C1000F);

constexpr std::uint32_t Pitch = 64;
constexpr std::uint32_t PictureHeight = 48;
constexpr std::size_t FrameBytes = static_cast<std::size_t>(Pitch) * PictureHeight * 3 / 2;

void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

struct Session {
    Ctrl ctrl{sizeof(Ctrl)};
    std::vector<std::uint8_t> buffer;

    Session() : buffer(FrameBytes) {
        const ConfigInfo config{sizeof(ConfigInfo), 1, 100, 42, static_cast<std::int32_t>(Width),
                                static_cast<std::int32_t>(CodedHeight), 4, 0};
        const ResourceInfo resource{sizeof(ResourceInfo), 16u << 20u, nullptr, 16u << 20u, nullptr,
                                    FrameBytes, 256};
        check(sceVideodecCreateDecoder(&config, &resource, &ctrl) == 0, "decoder creation failed");
        check(ctrl.handle != nullptr && ctrl.version == 1, "the control block was not filled");
    }

    ~Session() { sceVideodecDeleteDecoder(&ctrl); }

    FrameBuffer MakeTarget() { return FrameBuffer{sizeof(FrameBuffer), buffer.data(), buffer.size()}; }
};

void testDecode(const std::vector<std::vector<std::uint8_t>>& units, std::uint32_t cropTop, std::uint32_t cropBottom) {
    Session session;
    check(units.size() == PictureHashes.size(), "unexpected access unit count");
    std::vector<std::uint64_t> hashes;
    std::vector<std::uint64_t> timestamps;
    const auto collect = [&](PictureInfo& picture) {
        if (!picture.isValid) return;
        check(picture.framePitch == Pitch && picture.frameHeight == PictureHeight, "unexpected picture geometry");
        check(picture.frameWidth == Width, "unexpected picture width");
        check(picture.codecType == 0 && !picture.isErrorPic, "unexpected picture flags");
        check(picture.codec.avc.frameCropTopOffset == cropTop && picture.codec.avc.frameCropBottomOffset == cropBottom, "unexpected crop");
        hashes.push_back(hashNv12(session.buffer.data(), Pitch, PictureHeight));
        timestamps.push_back(picture.ptsData);
    };
    for (std::size_t unit = 0; unit < units.size(); ++unit) {
        const InputData input{sizeof(InputData), units[unit].data(), units[unit].size(), 1000 + unit, unit, 0xa0 + unit};
        auto target = session.MakeTarget();
        PictureInfo picture{sizeof(PictureInfo)};
        const auto status = sceVideodecDecode(&session.ctrl, &input, &target, &picture);
        check(status == 0, "decode of unit " + std::to_string(unit) + " failed with " + std::to_string(status));
        collect(picture);
    }
    for (;;) {
        auto target = session.MakeTarget();
        PictureInfo picture{sizeof(PictureInfo)};
        check(sceVideodecFlush(&session.ctrl, &target, &picture) == 0, "flush failed");
        if (!picture.isValid) break;
        collect(picture);
    }
    check(hashes.size() == PictureHashes.size(), "missing pictures");
    for (std::size_t index = 0; index < hashes.size(); ++index) {
        check(hashes[index] == PictureHashes[index], "picture " + std::to_string(index) + " differs from the reference");
        const auto unit = DisplayOrderUnits[index];
        check(timestamps[index] == 1000 + unit, "pictures out of display order");
    }
}

void testDecode() {
    testDecode(accessUnits(false), 0, (CodedHeight - Height) / 2);
}

void testDecodeCropped() {
    const auto stream = croppedStream();
    testDecode(accessUnits(stream.data(), stream.size(), false), 4, 4);
}

void testErrors() {
    const ConfigInfo config{sizeof(ConfigInfo), 1, 100, 42, static_cast<std::int32_t>(Width),
                            static_cast<std::int32_t>(CodedHeight), 4, 0};
    const ResourceInfo resource{sizeof(ResourceInfo), 16u << 20u, nullptr, 16u << 20u, nullptr, FrameBytes, 256};
    Ctrl ctrl{sizeof(Ctrl)};
    check(sceVideodecCreateDecoder(nullptr, &resource, &ctrl) == ErrorArgumentPointer, "a null configuration was accepted");
    check(sceVideodecCreateDecoder(&config, &resource, nullptr) == ErrorArgumentPointer, "a null control block was accepted");
    const ConfigInfo shortConfig{sizeof(ConfigInfo) - 8};
    check(sceVideodecCreateDecoder(&shortConfig, &resource, &ctrl) == ErrorStructSize, "a short configuration was accepted");
    check(sceVideodecCreateDecoder(&config, &resource, &ctrl) == 0, "decoder creation failed");
    Ctrl foreign{sizeof(Ctrl)};
    foreign.handle = reinterpret_cast<void*>(static_cast<std::uintptr_t>(0x1234));
    check(sceVideodecDeleteDecoder(&foreign) == ErrorHandle, "an unknown decoder was deleted");
    check(sceVideodecReset(&foreign) == ErrorHandle, "an unknown decoder was reset");
    const InputData empty{sizeof(InputData), nullptr, 0, 0, 0, 0};
    FrameBuffer frame{sizeof(FrameBuffer), nullptr, 0};
    PictureInfo picture{sizeof(PictureInfo)};
    check(sceVideodecDecode(nullptr, &empty, &frame, &picture) == ErrorArgumentPointer, "a null control block was accepted");
    check(sceVideodecDecode(&ctrl, &empty, &frame, &picture) == ErrorAuPointer, "a null access unit was accepted");
    const InputData sized{sizeof(InputData), reinterpret_cast<const std::uint8_t*>(&config), 0, 0, 0, 0};
    check(sceVideodecDecode(&ctrl, &sized, &frame, &picture) == ErrorAuSize, "an empty access unit was accepted");
    FrameBuffer missing{sizeof(FrameBuffer), nullptr, FrameBytes};
    const auto units = accessUnits(false);
    const InputData input{sizeof(InputData), units[0].data(), units[0].size(), 0, 0, 0};
    check(sceVideodecDecode(&ctrl, &input, &missing, &picture) == ErrorFrameBufferPointer, "a null frame buffer was accepted");
    std::vector<std::uint8_t> storage(static_cast<std::size_t>(FrameBytes));
    FrameBuffer shortBuffer{sizeof(FrameBuffer), storage.data(), FrameBytes - 1};
    int refusals = 0;
    for (std::size_t unit = 0; unit < units.size(); ++unit) {
        const InputData unit0{sizeof(InputData), units[unit].data(), units[unit].size(), 1000 + unit, unit, 0xa0 + unit};
        const auto status = sceVideodecDecode(&ctrl, &unit0, &shortBuffer, &picture);
        check(status == 0 || status == ErrorFrameBufferSize, "a decode failed");
        if (status == ErrorFrameBufferSize) ++refusals;
    }
    check(refusals > 0, "no picture was refused for the short frame buffer");
    check(sceVideodecDeleteDecoder(&ctrl) == 0, "the decoder was not deleted");
    check(sceVideodecDeleteDecoder(&ctrl) == ErrorHandle, "the decoder was deleted twice");
}

void testReset() {
    Session session;
    const auto units = accessUnits(false);
    const InputData input{sizeof(InputData), units[0].data(), units[0].size(), 1000, 0, 0xa0};
    auto target = session.MakeTarget();
    PictureInfo picture{sizeof(PictureInfo)};
    check(sceVideodecDecode(&session.ctrl, &input, &target, &picture) == 0, "decode failed");
    check(sceVideodecReset(&session.ctrl) == 0, "reset failed");
    check(sceVideodecFlush(&session.ctrl, &target, &picture) == 0, "flush failed");
    check(!picture.isValid, "a reset decoder produced a picture");
}

}

int main() {
    try {
        testDecode();
        testDecodeCropped();
        testErrors();
        testReset();
        std::puts("Videodec tests passed");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}
