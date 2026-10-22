#include "prx/libSceHmd/Hmd.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>

namespace {

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "HMD: %s\n", message);
        std::abort();
    }
}

void CheckDisconnected() {
    Hmd::DeviceStatus status = Hmd::DeviceStatus::Ready;
    Require(sceHmdInternalGetDeviceStatus(&status) == 0, "status query failed");
    Require(status == Hmd::DeviceStatus::NotDetected, "headset reported connected");
    Require(sceHmdInternalGetDeviceStatus(nullptr) == Hmd::ParameterNull, "null status");
    Require(sceHmdInternalMmapIsConnect() == 0, "connection reported present");
}

void CheckBufferQueries() {
    Require(sceHmdDistortionGetWorkMemoryAlign() == 0x400, "distortion work memory alignment");
    Require(sceHmdDistortionGetWorkMemorySize() == 0x20000, "distortion work memory size");
    Require(sceHmdReprojectionQueryGarlicBuffAlign() == 0x100, "reprojection garlic buffer alignment");
    Require(sceHmdReprojectionQueryGarlicBuffSize() == 0x100000, "reprojection garlic buffer size");
    Require(sceHmdReprojectionQueryOnionBuffAlign() == 0x100, "reprojection onion buffer alignment");
    Require(sceHmdReprojectionQueryOnionBuffSize() == 0x810, "reprojection onion buffer size");
}

void CheckHandleQueries(std::int32_t expected) {
    unsigned char left[16];
    unsigned char right[16];
    unsigned char fieldOfView[16];
    unsigned char sensor[64];
    std::memset(left, 0x5a, sizeof(left));
    std::memset(right, 0x5a, sizeof(right));
    std::memset(fieldOfView, 0x5a, sizeof(fieldOfView));
    std::memset(sensor, 0x5a, sizeof(sensor));
    for (const auto handle : {0, -1, 1, 0x0f000000}) {
        Require(sceHmdGetFieldOfView(handle, nullptr) == Hmd::ParameterNull, "null field of view accepted");
        Require(sceHmdGetFieldOfView(handle, reinterpret_cast<HmdFieldOfView*>(fieldOfView)) == expected, "field of view without a headset");
        Require(sceHmdGet2DEyeOffset(handle, reinterpret_cast<HmdEyeOffset*>(left), reinterpret_cast<HmdEyeOffset*>(right)) == expected, "eye offset without a headset");
        Require(sceHmdGet2DEyeOffset(handle, nullptr, nullptr) == expected, "eye offset with null outputs");
        Require(sceHmdGetInertialSensorData(handle, reinterpret_cast<HmdInertialSensorData*>(sensor), 1) == expected, "sensor data without a headset");
    }
    for (const auto* bytes : {left, right, fieldOfView}) {
        for (std::size_t index = 0; index < 16; ++index) Require(bytes[index] == 0x5a, "a refused query wrote its output");
    }
    for (const auto byte : sensor) Require(byte == 0x5a, "a refused sensor query wrote its output");
}

void CheckAssyError(std::int32_t expected) {
    unsigned char data[32];
    std::memset(data, 0x5a, sizeof(data));
    Require(sceHmdGetAssyError(nullptr) == Hmd::ParameterNull, "null assembly error output accepted");
    Require(sceHmdGetAssyError(reinterpret_cast<HmdAssemblyError*>(data)) == expected, "assembly error query without a headset");
    for (const auto byte : data) Require(byte == 0x5a, "a refused assembly error query wrote its output");
}

}

int main() {
    Hmd::InitializeParam param{};
    Hmd::DeviceInformation info;
    std::memset(&info, 0xa5, sizeof(info));
    const auto untouched = info;

    CheckDisconnected();
    CheckBufferQueries();
    Require(sceHmdTerminate() == Hmd::NotInitialized, "terminate before initialize");
    Require(sceHmdOpen(1, 0, 0, nullptr) == Hmd::NotInitialized, "open before initialize");
    Require(sceHmdClose(0) == Hmd::NotInitialized, "close before initialize");
    Require(sceHmdGetDeviceInformation(nullptr) == Hmd::ParameterNull, "null information");
    Require(sceHmdGetDeviceInformation(&info) == Hmd::NotInitialized, "query before initialize");
    Require(std::memcmp(&info, &untouched, sizeof(info)) == 0, "failed query modified output");
    CheckHandleQueries(Hmd::NotInitialized);
    CheckAssyError(Hmd::NotInitialized);
    Require(sceHmdGetDeviceInformationByHandle(0, &info) == Hmd::NotInitialized,
            "handle query before initialize");
    Require(sceHmdInitialize(nullptr) == Hmd::ParameterNull, "null initialize");
    Require(sceHmdInitialize315(nullptr) == Hmd::ParameterNull, "null initialize315");
    param.reserved0 = &param;
    Require(sceHmdInitialize(&param) == Hmd::UnsupportedFeature, "distortion unsupported");
    Require(sceHmdInitialize315(&param) == Hmd::UnsupportedFeature, "distortion315 unsupported");
    param.reserved0 = nullptr;

    for (const auto initialize : {sceHmdInitialize, sceHmdInitialize315}) {
        Require(initialize(&param) == 0, "initialize failed");
        Require(sceHmdInitialize(&param) == Hmd::AlreadyInitialized, "duplicate initialize");
        Require(sceHmdInitialize315(&param) == Hmd::AlreadyInitialized, "shared initialization");
        Require(sceHmdInitialize(nullptr) == Hmd::AlreadyInitialized, "duplicate precedence");
        CheckDisconnected();
        Require(sceHmdGetDeviceInformation(&info) == 0, "device query failed");
        Hmd::DeviceInformation expected{};
        expected.status = Hmd::DeviceStatus::NotDetected;
        expected.userId = -1;
        Require(std::memcmp(&info, &expected, sizeof(info)) == 0, "incorrect absent-device output");
        Require(sceHmdGetDeviceInformation(nullptr) == Hmd::ParameterNull, "null device query");

        Require(sceHmdOpen(-1, 0, 0, nullptr) == Hmd::ParameterInvalid, "invalid user");
        Require(sceHmdOpen(0xff, 0, 0, nullptr) == Hmd::ParameterInvalid, "system user");
        Require(sceHmdOpen(1, 1, 0, nullptr) == Hmd::ParameterInvalid, "invalid type");
        Require(sceHmdOpen(1, 0, 1, nullptr) == Hmd::ParameterInvalid, "invalid index");
        Require(sceHmdOpen(1, 0, 0, reinterpret_cast<Hmd::OpenParam*>(&param)) ==
                    Hmd::ParameterInvalid, "non-null reserved open parameter");
        Require(sceHmdOpen(1, 0, 0, nullptr) == Hmd::DeviceDisconnected, "open faked a handle");
        Require(sceHmdOpen(1, 0, 0, nullptr) == Hmd::DeviceDisconnected, "failed open created state");
        for (const auto handle : {0, -1, 1, 0x0f000000}) {
            Require(sceHmdClose(handle) == Hmd::InvalidHandle, "close accepted invalid handle");
            Require(sceHmdGetDeviceInformationByHandle(handle, &info) == Hmd::InvalidHandle,
                    "query accepted invalid handle");
            Require(std::memcmp(&info, &expected, sizeof(info)) == 0, "invalid handle modified output");
        }
        CheckHandleQueries(Hmd::InvalidHandle);
        CheckAssyError(Hmd::DeviceDisconnected);
        Require(sceHmdGetDeviceInformationByHandle(0, nullptr) == Hmd::InvalidHandle,
                "null query accepted invalid handle");
        Require(sceHmdTerminate() == 0, "terminate failed");
        Require(sceHmdTerminate() == Hmd::NotInitialized, "duplicate terminate");
        Require(sceHmdGetDeviceInformation(&info) == Hmd::NotInitialized, "query after terminate");
        CheckDisconnected();
    }
}
