#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceSigninDialogInitialize(void);
int APS5_VABI sceSigninDialogOpen(const void* param);
int APS5_VABI sceSigninDialogUpdateStatus(void);
int APS5_VABI sceSigninDialogGetStatus(void);
int APS5_VABI sceSigninDialogGetResult(void* result);
int APS5_VABI sceSigninDialogClose(void);
int APS5_VABI sceSigninDialogTerminate(void);
int APS5_VABI sceNetCtlApDialogInitialize(void);
int APS5_VABI sceNetCtlApDialogOpen(const void* param);
int APS5_VABI sceNetCtlApDialogUpdateStatus(void);
int APS5_VABI sceNetCtlApDialogGetResult(void* result);
int APS5_VABI sceNetCtlApDialogClose(void);
int APS5_VABI sceNetCtlApDialogTerminate(void);
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

struct Dialog {
    int (APS5_VABI* initialize)(void);
    int (APS5_VABI* open)(const void*);
    int (APS5_VABI* updateStatus)(void);
    int (APS5_VABI* getResult)(void*);
    int (APS5_VABI* close)(void);
    int (APS5_VABI* terminate)(void);
    int resultWords;
};

void Check(const Dialog& dialog) {
    std::int64_t param = 0;
    std::int32_t result[5] = {-1, -1, -1, -1, -1};
    Require(dialog.updateStatus() == kStatusNone);
    Require(dialog.open(&param) == kErrNotInitialized);
    Require(dialog.getResult(result) == kErrNotInitialized);
    Require(dialog.close() == kErrNotInitialized);
    Require(dialog.terminate() == kErrNotInitialized);
    Require(dialog.initialize() == 0);
    Require(dialog.initialize() == kErrAlreadyInitialized);
    Require(dialog.updateStatus() == kStatusInitialized);
    Require(dialog.getResult(result) == kErrNotFinished);
    Require(dialog.open(nullptr) == kErrArgNull);
    Require(dialog.open(&param) == 0);
    Require(dialog.updateStatus() == kStatusFinished);
    Require(dialog.getResult(nullptr) == kErrArgNull);
    Require(dialog.getResult(result) == 0);
    Require(result[0] == kResultUserCanceled && result[dialog.resultWords] == -1);
    for (int word = 1; word < dialog.resultWords; ++word) Require(result[word] == 0);
    Require(dialog.close() == 0);
    Require(dialog.terminate() == 0);
    Require(dialog.updateStatus() == kStatusNone);
}

}

int main() {
    Check({sceSigninDialogInitialize, sceSigninDialogOpen, sceSigninDialogUpdateStatus, sceSigninDialogGetResult, sceSigninDialogClose,
        sceSigninDialogTerminate, 4});
    Require(sceSigninDialogGetStatus() == kStatusNone);
    Check({sceNetCtlApDialogInitialize, sceNetCtlApDialogOpen, sceNetCtlApDialogUpdateStatus, sceNetCtlApDialogGetResult, sceNetCtlApDialogClose,
        sceNetCtlApDialogTerminate, 1});
}
