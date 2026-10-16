#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceG2PDialogInitialize(void);
int APS5_VABI sceG2PDialogOpen(const void* param);
int APS5_VABI sceG2PDialogUpdateStatus(void);
int APS5_VABI sceG2PDialogGetStatus(void);
int APS5_VABI sceG2PDialogGetResult(void* result);
int APS5_VABI sceG2PDialogClose(void);
int APS5_VABI sceG2PDialogTerminate(void);
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

}

int main() {
    std::int64_t param = 0;
    std::int32_t result[2] = {-1, -1};

    Require(sceG2PDialogTerminate() == kErrNotInitialized);
    Require(sceG2PDialogOpen(&param) == kErrNotInitialized);
    Require(sceG2PDialogClose() == kErrNotInitialized);
    Require(sceG2PDialogGetResult(result) == kErrNotInitialized);
    Require(sceG2PDialogGetStatus() == kStatusNone);
    Require(sceG2PDialogUpdateStatus() == kStatusNone);

    Require(sceG2PDialogInitialize() == 0);
    Require(sceG2PDialogInitialize() == kErrAlreadyInitialized);
    Require(sceG2PDialogGetStatus() == kStatusInitialized);
    Require(sceG2PDialogUpdateStatus() == kStatusInitialized);

    Require(sceG2PDialogOpen(nullptr) == kErrArgNull);
    Require(sceG2PDialogGetResult(result) == kErrNotFinished);

    Require(sceG2PDialogOpen(&param) == 0);
    Require(sceG2PDialogGetStatus() == kStatusFinished);
    Require(sceG2PDialogUpdateStatus() == kStatusFinished);

    Require(sceG2PDialogGetResult(nullptr) == kErrArgNull);
    Require(sceG2PDialogGetResult(result) == 0);
    Require(result[0] == kResultUserCanceled);
    Require(result[1] == -1);

    Require(sceG2PDialogClose() == 0);
    Require(sceG2PDialogTerminate() == 0);
    Require(sceG2PDialogTerminate() == kErrNotInitialized);
    Require(sceG2PDialogGetStatus() == kStatusNone);
}
