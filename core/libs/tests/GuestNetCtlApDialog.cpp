#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceNetCtlApDialogInitialize(void);
int APS5_VABI sceNetCtlApDialogTerminate(void);
int APS5_VABI sceNetCtlApDialogOpen(const void* param);
int APS5_VABI sceNetCtlApDialogClose(void);
int APS5_VABI sceNetCtlApDialogUpdateStatus(void);
int APS5_VABI sceNetCtlApDialogGetStatus(void);
int APS5_VABI sceNetCtlApDialogGetResult(void* result);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

constexpr int kStatusNone = 0;
constexpr int kStatusInitialized = 1;
constexpr int kStatusFinished = 3;
constexpr int kErrNotInitialized = static_cast<int>(0x80B80003);
constexpr int kErrAlreadyInitialized = static_cast<int>(0x80B80004);
constexpr int kErrNotFinished = static_cast<int>(0x80B80005);
constexpr int kErrArgNull = static_cast<int>(0x80B8000D);
constexpr int kResultUserCanceled = 1;

void RequireCanceled(const std::uint8_t (&result)[44]) {
    std::int32_t code = 0;
    std::memcpy(&code, result, sizeof(code));
    Require(code == kResultUserCanceled);
    for (int i = 4; i < 40; ++i) Require(result[i] == 0);
    for (int i = 40; i < 44; ++i) Require(result[i] == 0x5a);
}

}

int main() {
    std::uint8_t param[104] = {};
    std::uint8_t result[44];
    std::memset(result, 0x5a, sizeof(result));

    Require(sceNetCtlApDialogTerminate() == kErrNotInitialized);
    Require(sceNetCtlApDialogOpen(param) == kErrNotInitialized);
    Require(sceNetCtlApDialogClose() == kErrNotInitialized);
    Require(sceNetCtlApDialogGetResult(result) == kErrNotInitialized);
    Require(sceNetCtlApDialogGetStatus() == kStatusNone);
    Require(sceNetCtlApDialogUpdateStatus() == kStatusNone);

    Require(sceNetCtlApDialogInitialize() == 0);
    Require(sceNetCtlApDialogInitialize() == kErrAlreadyInitialized);
    Require(sceNetCtlApDialogGetStatus() == kStatusInitialized);
    Require(sceNetCtlApDialogUpdateStatus() == kStatusInitialized);

    Require(sceNetCtlApDialogOpen(nullptr) == kErrArgNull);
    Require(sceNetCtlApDialogGetStatus() == kStatusInitialized);
    Require(sceNetCtlApDialogGetResult(result) == kErrNotFinished);

    Require(sceNetCtlApDialogOpen(param) == 0);
    Require(sceNetCtlApDialogGetStatus() == kStatusFinished);
    Require(sceNetCtlApDialogUpdateStatus() == kStatusFinished);

    Require(sceNetCtlApDialogGetResult(nullptr) == kErrArgNull);
    Require(sceNetCtlApDialogGetResult(result) == 0);
    RequireCanceled(result);

    Require(sceNetCtlApDialogOpen(param) == 0);
    Require(sceNetCtlApDialogClose() == 0);
    Require(sceNetCtlApDialogTerminate() == 0);
    Require(sceNetCtlApDialogTerminate() == kErrNotInitialized);
    Require(sceNetCtlApDialogGetStatus() == kStatusNone);

    Require(sceNetCtlApDialogInitialize() == 0);
    Require(sceNetCtlApDialogClose() == 0);
    Require(sceNetCtlApDialogGetStatus() == kStatusFinished);
    std::memset(result, 0x5a, sizeof(result));
    Require(sceNetCtlApDialogGetResult(result) == 0);
    RequireCanceled(result);
    Require(sceNetCtlApDialogTerminate() == 0);
}
