#include "Hmd.hpp"
#include "prx/libc/include/General.hpp"

#include <atomic>

namespace {

std::atomic<bool> initialized{false};

std::int32_t Initialize(const Hmd::InitializeParam* param) {
    if (initialized.load()) return Hmd::AlreadyInitialized;
    if (!param) return Hmd::ParameterNull;
    if (param->reserved0) return Hmd::UnsupportedFeature;
    return initialized.exchange(true) ? Hmd::AlreadyInitialized : 0;
}

}

extern "C" {

std::int32_t APS5_VABI sceHmdInitialize(const Hmd::InitializeParam* param) {
    return Initialize(param);
}

std::int32_t APS5_VABI sceHmdInitialize315(const Hmd::InitializeParam* param) {
    return Initialize(param);
}

std::int32_t APS5_VABI sceHmdTerminate() {
    return initialized.exchange(false) ? 0 : Hmd::NotInitialized;
}

std::int32_t APS5_VABI sceHmdOpen(std::int32_t userId, std::int32_t type, std::int32_t index,
                                Hmd::OpenParam* param) {
    if (!initialized.load()) return Hmd::NotInitialized;
    if (type != 0 || index != 0 || param || userId == -1 || userId == 0xff)
        return Hmd::ParameterInvalid;
    return Hmd::DeviceDisconnected;
}

std::int32_t APS5_VABI sceHmdClose(std::int32_t handle) {
    (void)handle;
    return initialized.load() ? Hmd::InvalidHandle : Hmd::NotInitialized;
}

std::int32_t APS5_VABI sceHmdGetDeviceInformation(Hmd::DeviceInformation* info) {
    if (!info) return Hmd::ParameterNull;
    if (!initialized.load()) return Hmd::NotInitialized;
    *info = {};
    info->status = Hmd::DeviceStatus::NotDetected;
    info->userId = -1;
    return 0;
}

std::int32_t APS5_VABI sceHmdGetDeviceInformationByHandle(std::int32_t handle,
                                                        Hmd::DeviceInformation* info) {
    (void)handle;
    (void)info;
    return initialized.load() ? Hmd::InvalidHandle : Hmd::NotInitialized;
}

std::int32_t APS5_VABI sceHmdInternalGetDeviceStatus(Hmd::DeviceStatus* status) {
    if (!status) return Hmd::ParameterNull;
    *status = Hmd::DeviceStatus::NotDetected;
    return 0;
}

std::int32_t APS5_VABI sceHmdInternalMmapIsConnect() {
    return 0;
}

int APS5_VABI sceHmdInternalGetPUVersion(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalEventInitialize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetVirtualDisplaySize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSocialScreenSetOutput(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetVirtualDisplayDepth(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetEyeStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenOpen(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionUnsetCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetCrashReportCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDebugTextMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGetWorkMemoryAlign(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalRegisterEventCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGetWorkMemorySize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartWideNear(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetPUSerialNumber(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDebugSocialScreenMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetM2LedBrightness(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetIPD(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMirroringModeSetAspect(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuGetStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenSendVideo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetRequiredPUPVersion(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionSetCallback(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuCheckAfterPvt(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalResetInertialSensor(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionSetUserEventStart(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionSetOutputMinColor(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetVirtualDisplayDepth(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetDistortionWorkMemoryAlign(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartMultilayer(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalPushVr2dData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionClearUserEventEnd(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetIPD(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetVRMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCrashReportReadDataSize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetVr2dData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenSendAudio(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetPuPositionParam(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionInitializeCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGet2DEyeOffset(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDebugSocialScreenMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetHmuPowerStatusForDebug(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetDistortionWorkMemorySize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionSetDisplayBuffers(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenSetFadeAndSwitch(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCreateSharedMemory(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMirroringModeSetAspectDebug(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetPuBuildNumber(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGetCompoundEyeCorrectionCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetS3dPassMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStopCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalIsCommonDlgMiniAppVr2d(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMmapGetSensorCalibrationData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGetCorrectionCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionQueryOnionBuffAlign(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDebugMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalIsMiniAppVr2d(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalIsCommonDlgVr2d(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionSetOutputMinColor(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetPortConnection(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionDebugGetLastInfo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetM2LedOn(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetFieldOfView(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionAddDisplayBuffer(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetIpdSettingEnableForSystemService(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetLedOn(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternal3dAudioSendData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionInitialize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDeviceInformationByHandle(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStopLiveCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenClose(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCrashReportReadData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDeviceInformation(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDefaultLedData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuClose(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionQueryGarlicBuffAlign(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetHmuPowerControl(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalBindDeviceWithUserId(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetHmuSerialNumber(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGetWideNearCorrectionCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCheckS3dPassModeAvailable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenGetAudioStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeGetAudioStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartLiveCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalIsGameVr2d(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetAssyError(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionFinalize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSocialScreenSetFadeAndSwitch(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuStart(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetVirtualDisplayHeight(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionInitialize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuSetMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetForcedCrash(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuCheckPartialUpdateAvailable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeClose(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDebugTextMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCrashReportClose(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetHmuPowerControlForDebug(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetVirtualDisplayHeight(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStart(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalResetLedForVsh(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuOpen(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDebugMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCrashReportCancel(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeGetVideoStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCheckDeviceModelMk3(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdSetVr2dEnable(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetSidetone(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeOpen(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMmapGetModeId(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdDistortionGet2dVrCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuSendSize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetWideNearDistortionCorrectionCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartMultilayer2(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetDistortionCorrectionCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDeviceConnection(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetVirtualDisplaySize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionUnsetDisplayBuffers(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetHmuOpticalParam(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeSendVideo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalResetLedForVrTracker(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionQueryOnionBuffSize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartWithOverlay(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionSetUserEventEnd(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalCrashReportOpen(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDemoMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStartWideNearWithOverlay(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetDistortionParams(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuSend(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionClearUserEventStart(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetUserType(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetDemoMode(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMapSharedMemory(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetCrashDumpInfo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetTv4kCapability(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalDfuReset(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStart2dVr(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalMmapGetCount(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDefaultLedData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGetInertialSensorData(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternal3dAudioClose(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetBrightness(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSocialScreenGetFadeState(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSeparateModeSendAudio(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetStatusReport(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetBrightness(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionFinalizeCapture(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetPortStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionStop(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenGetVideoStatus(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternal3dAudioOpen(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalAnotherScreenGetFadeState(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalSetDebugGpo(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetIpdSettingEnableForSystemService(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionDebugGetLastInfoMultilayer(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdInternalGetPuRevision(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdReprojectionQueryGarlicBuffSize(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceHmdGet2dVrCommand(void) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
