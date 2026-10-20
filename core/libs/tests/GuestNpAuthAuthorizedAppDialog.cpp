#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceNpAuthAuthorizedAppDialogInitialize(void);
int APS5_VABI sceNpAuthAuthorizedAppDialogOpen(const void* param);
int APS5_VABI sceNpAuthAuthorizedAppDialogUpdateStatus(void);
int APS5_VABI sceNpAuthAuthorizedAppDialogGetStatus(void);
int APS5_VABI sceNpAuthAuthorizedAppDialogGetResult(void* result);
int APS5_VABI sceNpAuthAuthorizedAppDialogClose(void);
int APS5_VABI sceNpAuthAuthorizedAppDialogTerminate(void);
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

    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusNone);
    Require(sceNpAuthAuthorizedAppDialogTerminate() == kErrNotInitialized);
    Require(sceNpAuthAuthorizedAppDialogClose() == kErrNotInitialized);
    Require(sceNpAuthAuthorizedAppDialogOpen(&param) == kErrNotInitialized);
    Require(sceNpAuthAuthorizedAppDialogGetResult(result) == kErrNotInitialized);

    Require(sceNpAuthAuthorizedAppDialogInitialize() == 0);
    Require(sceNpAuthAuthorizedAppDialogInitialize() == kErrAlreadyInitialized);
    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusInitialized);
    Require(sceNpAuthAuthorizedAppDialogUpdateStatus() == kStatusInitialized);

    Require(sceNpAuthAuthorizedAppDialogOpen(nullptr) == kErrArgNull);
    Require(sceNpAuthAuthorizedAppDialogGetResult(result) == kErrNotFinished);

    Require(sceNpAuthAuthorizedAppDialogOpen(&param) == 0);
    Require(sceNpAuthAuthorizedAppDialogUpdateStatus() == kStatusFinished);
    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusFinished);

    Require(sceNpAuthAuthorizedAppDialogGetResult(nullptr) == kErrArgNull);
    Require(sceNpAuthAuthorizedAppDialogGetResult(result) == 0);
    Require(result[0] == kResultUserCanceled);
    Require(result[1] == -1);

    Require(sceNpAuthAuthorizedAppDialogClose() == 0);
    Require(sceNpAuthAuthorizedAppDialogTerminate() == 0);
    Require(sceNpAuthAuthorizedAppDialogTerminate() == kErrNotInitialized);
    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusNone);

    Require(sceNpAuthAuthorizedAppDialogInitialize() == 0);
    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusInitialized);
    Require(sceNpAuthAuthorizedAppDialogClose() == 0);
    Require(sceNpAuthAuthorizedAppDialogGetStatus() == kStatusFinished);
    result[0] = -1;
    Require(sceNpAuthAuthorizedAppDialogGetResult(result) == 0);
    Require(result[0] == kResultUserCanceled);
    Require(sceNpAuthAuthorizedAppDialogTerminate() == 0);
    return 0;
}
