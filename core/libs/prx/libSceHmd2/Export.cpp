#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr std::int32_t SCE_HMD2_ERROR_UNSUPPORTED_FEATURE = static_cast<std::int32_t>(0x81110016);

}

// No PlayStation VR2 headset can be attached: initialization reports the feature as unsupported, so
// every device, gaze and reprojection call reports the same.
extern "C" {

std::int32_t APS5_VABI sceHmd2Initialize(const void* param) {
    (void)param;
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2Close() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2GazeGetResult() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2GazeGetResultForFoveatedRendering() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2GetDeviceInformation() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2GetFieldOfViewWithoutHandle() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2Open() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionBeginFrame() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionDisableMirroring() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionDisableVrMode() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionEnableMirroring() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionEnableVrMode() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionGetMirroringDisplayBufferSizeAlign() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionGetMirroringWorkMemorySizeAlign() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionGetPredictedDisplayTime() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionInitialize() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionQueryBufferSizeAlign() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionQueryDisplayBufferSizeAlign() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetAllowPositionalReprojection() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetMirroringOption() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetParam() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetParamWithBuffer() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetRenderConfig() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

std::int32_t APS5_VABI sceHmd2ReprojectionSetTiming() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2ReprojectionTerminate() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

std::int32_t APS5_VABI sceHmd2SetVibration() {
    return SCE_HMD2_ERROR_UNSUPPORTED_FEATURE;
}

}
