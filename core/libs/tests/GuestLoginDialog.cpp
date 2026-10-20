#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <initializer_list>

extern "C" {
int APS5_VABI sceLoginDialogInitialize(void);
int APS5_VABI sceLoginDialogOpen(const void* param);
int APS5_VABI sceLoginDialogUpdateStatus(void);
int APS5_VABI sceLoginDialogGetStatus(void);
int APS5_VABI sceLoginDialogGetResult(void* result);
int APS5_VABI sceLoginDialogClose(void);
int APS5_VABI sceLoginDialogTerminate(void);
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

constexpr int kStatusNone = 0;
constexpr int kStatusInitialized = 1;
constexpr int kStatusFinished = 3;
constexpr int kErrNotInitialized = static_cast<int>(0x81340001);
constexpr int kErrAlreadyInitialized = static_cast<int>(0x81340002);
constexpr int kErrParamInvalid = static_cast<int>(0x81340003);
constexpr int kErrBusy = static_cast<int>(0x81340005);
constexpr int kErrNoService = static_cast<int>(0x81340007);
constexpr int kResultUserCanceled = 1;

void RequireRejected(const std::uint32_t (&valid)[16], std::size_t word, std::uint32_t value) {
    std::uint32_t param[16];
    std::memcpy(param, valid, sizeof(param));
    param[word] = value;
    Require(sceLoginDialogOpen(param) == kErrParamInvalid);
}

void RequireResult(const std::int32_t (&result)[4]) {
    Require(result[0] == kResultUserCanceled);
    Require(result[1] == kErrNoService);
    Require(result[2] == -1 && result[3] == -1);
}

}

int main() {
    const std::uint32_t param[16] = {0x40};
    std::int32_t result[4] = {-1, -1, -1, -1};

    Require(sceLoginDialogTerminate() == kErrNotInitialized);
    Require(sceLoginDialogOpen(param) == kErrNotInitialized);
    Require(sceLoginDialogClose() == kErrNotInitialized);
    Require(sceLoginDialogGetResult(result) == kErrNotInitialized);
    Require(result[0] == -1 && result[1] == -1);
    Require(sceLoginDialogGetStatus() == kStatusNone);
    Require(sceLoginDialogUpdateStatus() == kStatusNone);

    Require(sceLoginDialogInitialize() == 0);
    Require(sceLoginDialogInitialize() == kErrAlreadyInitialized);
    Require(sceLoginDialogGetStatus() == kStatusInitialized);
    Require(sceLoginDialogUpdateStatus() == kStatusInitialized);

    Require(sceLoginDialogOpen(nullptr) == kErrParamInvalid);
    for (std::uint32_t size : {0u, 0x3Cu, 0x3Fu, 0x41u}) RequireRejected(param, 0, size);
    for (std::uint32_t selector : {2u, 0xFFFFFFFFu}) RequireRejected(param, 1, selector);
    for (std::size_t word = 0x2C / 4; word < 16; ++word) RequireRejected(param, word, 1);
    Require(sceLoginDialogGetStatus() == kStatusInitialized);
    Require(sceLoginDialogGetResult(result) == kErrBusy);
    RequireResult(result);
    std::memset(result, 0xFF, sizeof(result));

    Require(sceLoginDialogOpen(param) == 0);
    Require(sceLoginDialogGetStatus() == kStatusFinished);
    Require(sceLoginDialogUpdateStatus() == kStatusFinished);

    Require(sceLoginDialogGetResult(nullptr) == kErrParamInvalid);
    Require(sceLoginDialogGetResult(result) == 0);
    RequireResult(result);

    Require(sceLoginDialogClose() == 0);
    Require(sceLoginDialogTerminate() == 0);
    Require(sceLoginDialogTerminate() == kErrNotInitialized);
    Require(sceLoginDialogGetStatus() == kStatusNone);

    Require(sceLoginDialogInitialize() == 0);
    Require(sceLoginDialogGetStatus() == kStatusInitialized);
    Require(sceLoginDialogClose() == 0);
    Require(sceLoginDialogGetStatus() == kStatusFinished);
    result[0] = -1;
    Require(sceLoginDialogGetResult(result) == 0);
    Require(result[0] == kResultUserCanceled);
    Require(sceLoginDialogTerminate() == 0);
}
