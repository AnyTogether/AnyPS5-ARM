#include "ProcessParametersFixture.hpp"
#include "prx/libSceHmd2/Hmd2.hpp"
#include "prx/libSceUserService/UserService.hpp"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>

namespace {

alignas(16) std::array<std::byte, 0x40> process{};

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "HMD2: %s\n", message);
        std::abort();
    }
}

void SetSdkVersion(std::uint32_t version) {
    std::memcpy(process.data() + 0x10, &version, sizeof(version));
}

void InstallProcessParameters() {
    const std::uint64_t size = process.size();
    const std::uint32_t magic = 0x4942524f;
    std::memcpy(process.data(), &size, sizeof(size));
    std::memcpy(process.data() + 8, &magic, sizeof(magic));
    Require(ProcessParametersFixture::Install(process.data(), process.size()), "process parameters were not installed");
}

bool IsDefaultFieldOfView(const Hmd2::FieldOfView& fieldOfView) {
    return fieldOfView.tanOut == 1.84177089f && fieldOfView.tanIn == 0.947190642f &&
           fieldOfView.tanTop == 1.32898104f && fieldOfView.tanBottom == 1.32898104f;
}

void RequireNotDetected(const Hmd2::DeviceInformation& info, std::int32_t userId) {
    Require(info.status == Hmd2::DeviceStatus::NotDetected, "device status is not NOT_DETECTED");
    Require(info.userId == userId, "device user does not match the SDK version");
    Require(info.panelWidth == 4000 && info.panelHeight == 2040, "panel resolution differs from the firmware");
    Require(info.latency90Hz == 5555 && info.latency120Hz == 4160, "flip latencies differ from the firmware");
    Require(info.hmuMount == 0 && info.lensSeparationDistance == 0, "a missing headset reported a mount or lens separation");
    Require(info.reserved[0] == 0 && info.reserved[1] == 0, "reserved bytes were not cleared");
    Require(info.virtualImageDistance == 2.0f, "virtual image distance differs from the firmware");
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

void TestInitialized() {
    const std::uint8_t param[16]{};
    Require(sceHmd2Initialize(nullptr) == Hmd2::ParameterNull, "initialization without a param");
    Require(sceHmd2Initialize(param) == 0, "initialization failed");
    Require(sceHmd2Initialize(param) == Hmd2::AlreadyInitialized, "second initialization");

    Hmd2::DeviceInformation info;
    std::memset(&info, 0xcc, sizeof(info));
    SetSdkVersion(0x06000000);
    Require(sceHmd2GetDeviceInformation(&info) == 0, "device information failed");
    RequireNotDetected(info, -1);
    SetSdkVersion(0x07590001);
    std::memset(&info, 0xcc, sizeof(info));
    Require(sceHmd2GetDeviceInformation(&info) == 0, "device information for SDK 7.59 failed");
    RequireNotDetected(info, 0);

    Hmd2::FieldOfView fieldOfView{};
    Require(sceHmd2GetFieldOfViewWithoutHandle(&fieldOfView) == 0 && IsDefaultFieldOfView(fieldOfView), "default field of view");
    Require(sceHmd2GetFieldOfViewWithoutHandle(nullptr) == Hmd2::ParameterNull, "null field of view");
    Require(sceHmd2GetFieldOfView(12345, &fieldOfView) == Hmd2::InvalidHandle, "field of view of an unknown handle");
    Require(sceHmd2GetFieldOfView(12345, nullptr) == Hmd2::ParameterNull, "null field of view of an unknown handle");
    Require(sceHmd2GetDeviceInformationByHandle(12345, &info) == Hmd2::InvalidHandle, "device information of an unknown handle");
    Require(sceHmd2SetVibration(12345, 0) == Hmd2::InvalidHandle, "vibration of an unknown handle");
    Require(sceHmd2Close(12345) == Hmd2::InvalidHandle, "close of an unknown handle");

    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 1, 0, nullptr) == Hmd2::ParameterInvalid, "open with a device type");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 1, nullptr) == Hmd2::ParameterInvalid, "open with a device index");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, param) == Hmd2::ParameterInvalid, "open with a param");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID + 1, 0, 0, nullptr) == Hmd2::ParameterInvalid, "open for another user on SDK 7.59");

    const auto handle = sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr);
    Require(handle > 0, "open without a headset failed");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr) == Hmd2::AlreadyOpened, "second open");
    std::memset(&info, 0xcc, sizeof(info));
    Require(sceHmd2GetDeviceInformationByHandle(handle, &info) == 0, "device information by handle failed");
    RequireNotDetected(info, 0);
    fieldOfView = {};
    Require(sceHmd2GetFieldOfView(handle, &fieldOfView) == 0 && IsDefaultFieldOfView(fieldOfView), "field of view by handle");
    Require(sceHmd2SetVibration(handle, 26) == 0, "vibration of a disconnected headset failed");
    Require(sceHmd2Close(handle) == 0, "close failed");
    Require(sceHmd2Close(handle) == Hmd2::InvalidHandle, "second close");
    Require(sceHmd2Close(0) == 0, "close of the unopened handle 0 failed");

    const auto kept = sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr);
    Require(kept > 0, "reopen failed");
    Require(sceHmd2Terminate() == 0, "terminate failed");
    Require(sceHmd2Terminate() == Hmd2::NotInitialized, "second terminate");
    Require(sceHmd2GetFieldOfView(kept, &fieldOfView) == Hmd2::NotInitialized, "field of view after terminate");
    Require(sceHmd2Close(kept) == Hmd2::NotInitialized, "close after terminate");
    Require(sceHmd2Initialize(param) == 0, "reinitialization failed");
    Require(sceHmd2Open(USER_SERVICE_INITIAL_USER_ID, 0, 0, nullptr) == Hmd2::AlreadyOpened, "terminate closed the open handle");
    Require(sceHmd2Close(kept) == 0, "close after reinitialization failed");

    SetSdkVersion(0x06000000);
    bool threw = false;
    try {
        sceHmd2Open(USER_SERVICE_INITIAL_USER_ID + 1, 0, 0, nullptr);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    Require(threw, "open for another user before SDK 7.00 did not throw");
    Require(sceHmd2Terminate() == 0, "final terminate failed");
}

}

int main() {
    InstallProcessParameters();
    TestBeforeInitialize();
    TestInitialized();
    std::puts("HMD2 tests passed");
    return 0;
}
