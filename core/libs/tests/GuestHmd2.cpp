#include "ProcessParametersFixture.hpp"
#include "prx/libSceHmd/Hmd.hpp"
#include "prx/libSceHmd2/Hmd2.hpp"
#include "prx/libSceUserService/UserService.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>

extern "C" {
int APS5_VABI sceHmd2GazeActivateGazeTracking();
int APS5_VABI sceHmd2ReprojectionGetCurrentOutput();
int APS5_VABI sceHmd2SetFieldOfView();
}
namespace {

alignas(16) std::array<std::byte, 0x40> process{};

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "HMD2: %s\n", message);
        std::abort();
    }
}

void InstallProcessParameters() {
    const std::uint64_t size = process.size();
    const std::uint32_t magic = 0x4942524f;
    std::memcpy(process.data(), &size, sizeof(size));
    std::memcpy(process.data() + 8, &magic, sizeof(magic));
#ifdef __APPLE__
    // The fixture installs the parameters through the main image's PE section or ELF program header;
    // a macOS test executable has neither, so the test is skipped there.
    if (!ProcessParametersFixture::Install(process.data(), process.size())) {
        std::puts("HMD2: process parameters cannot be installed in a macOS executable; skipped");
        std::exit(77);
    }
#else
    Require(ProcessParametersFixture::Install(process.data(), process.size()), "process parameters were not installed");
#endif
}

void TestBeforeInitialize() {
    Hmd2::DeviceInformation info;
    std::memset(&info, 0xcc, sizeof(info));
    Require(sceHmd2GetDeviceInformation(&info) == Hmd2::NotInitialized, "device information before initialization");
    const Hmd2::DeviceInformation cleared{};
    Require(std::memcmp(&info, &cleared, sizeof(info)) == 0, "device information was not cleared before the initialization check");
    Require(sceHmd2GetDeviceInformation(nullptr) == Hmd2::ParameterNull, "null device information before initialization");
    Hmd2::FieldOfView fieldOfView{};
    Require(sceHmd2GetFieldOfViewWithoutHandle(&fieldOfView) == Hmd2::NotInitialized, "field of view before initialization");
    Require(sceHmd2GetFieldOfView(0, &fieldOfView) == Hmd2::InvalidHandle, "field of view of handle 0 before initialization");
    Require(sceHmd2GetDeviceInformationByHandle(0, &info) == Hmd2::NotInitialized, "device information of handle 0 before initialization");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr) == Hmd2::NotInitialized, "open before initialization");
    Require(sceHmd2Close(0) == Hmd2::NotInitialized, "close before initialization");
    Require(sceHmd2Terminate() == Hmd2::NotInitialized, "terminate before initialization");
    Require(sceHmd2SetVibration(0, 0) == 0, "vibration of the unopened handle 0 failed");
}

void TestWithoutHeadset() {
    const std::uint8_t param[16]{};
    Require(sceHmd2Initialize(param) == Hmd::UnsupportedFeature, "initialization without a headset did not fail");
    Require(sceHmd2Initialize(nullptr) == Hmd::UnsupportedFeature, "initialization without a param did not fail as unsupported");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr) == Hmd2::NotInitialized, "open without a headset did not fail");
    Hmd2::DeviceInformation info;
    Require(sceHmd2GetDeviceInformation(&info) == Hmd2::NotInitialized, "device information without a headset");
    Require(sceHmd2Terminate() == Hmd2::NotInitialized, "terminate after the failed initialization");
}

}

void SizeQueriesReturnTheConsoleSizes() {
    const auto display = sceHmd2ReprojectionQueryDisplayBufferSizeAlign();
    Require(display.size == 0x6000000 && display.align == 0x10000, "display buffer size");
    const auto seeThrough = sceHmd2ReprojectionQuerySeeThroughBufferSizeAlign();
    Require(seeThrough.size == 0x1106000 && seeThrough.align == 0x100, "see-through buffer size");
    const auto mirroring = sceHmd2ReprojectionGetMirroringDisplayBufferSizeAlign();
    Require(mirroring.size == 0x5FA0000 && mirroring.align == 0x10000, "mirroring display buffer size");
    const auto work = sceHmd2ReprojectionGetMirroringWorkMemorySizeAlign();
    Require(work.size == 0x4000 && work.align == 0x100, "mirroring work memory size");
}

int main() {
    SizeQueriesReturnTheConsoleSizes();
    InstallProcessParameters();
    TestBeforeInitialize();
    TestWithoutHeadset();
    bool threw = false;
    try {
        sceHmd2GazeActivateGazeTracking();
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw, "gaze activation did not throw");
    threw = false;
    try {
        sceHmd2ReprojectionGetCurrentOutput();
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw, "reprojection get current output did not throw");
    threw = false;
    try {
        sceHmd2SetFieldOfView();
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw, "set field of view did not throw");
    std::puts("HMD2 tests passed");
    return 0;
}
