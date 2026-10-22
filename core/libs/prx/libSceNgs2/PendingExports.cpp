#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceNgs2CustomRackGetModuleInfo(std::uintptr_t rackHandle, std::uint32_t moduleIndex, void* outInfo, std::size_t infoSize) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2FftInit() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2FftProcess() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2FftQuerySize() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2GetWaveformFrameInfo(void* format, std::uint32_t* outFrameSize, std::uint32_t* outNumFrameSamples, std::uint32_t* outUnitsPerFrame, std::uint32_t* outNumDelaySamples) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2ParseWaveformUser(std::uintptr_t handler, std::uintptr_t userData, void* outInfo) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2SystemEnumHandles(std::uintptr_t* outHandles, std::uint32_t maxHandles) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2SystemEnumRackHandles(std::uintptr_t systemHandle, std::uintptr_t* outHandles, std::uint32_t maxHandles) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}
int APS5_VABI sceNgs2VoiceGetMatrixInfo(std::uintptr_t voiceHandle, std::uint32_t matrixId, void* outInfo, std::size_t infoSize) {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}
