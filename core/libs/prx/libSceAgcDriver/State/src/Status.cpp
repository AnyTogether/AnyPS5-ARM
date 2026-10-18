#include "prx/libSceAgcDriver/State/include/Status.hpp"

#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int AgcDriverDebugUnavailable = static_cast<int>(0x8a6c1000u);

}

extern "C" {

bool APS5_VABI sceAgcDriverIsCaptureInProgress(void) {
    return false;
}

bool APS5_VABI sceAgcDriverIsTraceInProgress(void) {
    return false;
}

bool APS5_VABI sceAgcDriverIsSubmitValidationEnabled(void) {
    return false;
}

// GPU captures need a development kit; a retail driver refuses them with the debug-unavailable error.
int APS5_VABI sceAgcDriverRequestCaptureStart(const char* path) {
    (void)path;
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverRequestCaptureStop() {
    return AgcDriverDebugUnavailable;
}

int APS5_VABI sceAgcDriverTriggerCapture() {
    return AgcDriverDebugUnavailable;
}

}
