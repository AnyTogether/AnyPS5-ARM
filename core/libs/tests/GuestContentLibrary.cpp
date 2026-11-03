#include "SceTypes.hpp"

#include <cstdint>
#include <cstdlib>
#include <stdexcept>

extern "C" {
int APS5_VABI sceContentDeleteInitialize(const ContentDeleteInitParam*);
int APS5_VABI sceContentDeleteTerminate();
int APS5_VABI sceContentDeleteByPath(const char*);
int APS5_VABI sceVideoRecordingGetStatus();
int APS5_VABI sceVideoRecordingStart();
int APS5_VABI sceVideoRecordingStop();
int APS5_VABI sceVideoRecordingClose(int);
}

static void Require(bool value) { if (!value) std::abort(); }

template <typename TError, typename TAction>
static bool Throws(TAction action) {
    try {
        action();
    } catch (const TError&) {
        return true;
    }
    return false;
}

static void CheckContentDelete() {
    constexpr int NotInitialized = static_cast<int>(0x809D5002u);
    Require(sceContentDeleteByPath(nullptr) == NotInitialized);
    Require(sceContentDeleteByPath("/data/a.png") == NotInitialized);
    ContentDeleteInitParam param{};
    param.heap_size = 0x4000;
    Require(sceContentDeleteInitialize(&param) == 0);
    Require(Throws<std::invalid_argument>([] { sceContentDeleteByPath(nullptr); }));
    // Not implemented: upstream's NotImplemented_nid_no_patch throws std::runtime_error now.
    Require(Throws<std::runtime_error>([] { sceContentDeleteByPath("/data/a.png"); }));
    Require(sceContentDeleteTerminate() == 0);
}

static void CheckVideoRecording() {
    // Without an open recorder upstream's calls return SCE_VIDEO_RECORDING_ERROR_NOT_OPEN.
    constexpr int NotOpen = static_cast<int>(0x80a80006u);
    Require(sceVideoRecordingGetStatus() == 0);
    Require(sceVideoRecordingStart() == NotOpen);
    Require(sceVideoRecordingStop() == NotOpen);
    Require(sceVideoRecordingClose(1) == NotOpen);
}

int main() {
    CheckContentDelete();
    CheckVideoRecording();
    return 0;
}
