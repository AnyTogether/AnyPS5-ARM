#include "SceTypes.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceNpCommerceDialogInitialize();
int APS5_VABI sceNpCommerceDialogOpen(const void* param);
int APS5_VABI sceNpCommerceDialogOpen2(void);
int APS5_VABI sceNpCommerceDialogUpdateStatus(void);
int APS5_VABI sceNpCommerceDialogGetStatus(void);
int APS5_VABI sceNpCommerceDialogGetResult(void* result);
int APS5_VABI sceNpCommerceDialogClose(void);
int APS5_VABI sceNpCommerceDialogTerminate();
}

namespace {

void Require(bool value) { if (!value) std::abort(); }

constexpr int statusNone = 0;
constexpr int statusInitialized = 1;
constexpr int statusFinished = 3;
constexpr std::int32_t resultUserCanceled = 1;

void RequireCanceledResult() {
    std::uint8_t result[0x20];
    std::memset(result, 0x33, sizeof(result));
    Require(sceNpCommerceDialogGetResult(result) == 0);
    std::int32_t value = 0;
    std::memcpy(&value, result, sizeof(value));
    Require(value == resultUserCanceled);
    Require(result[4] == 0);
    Require(result[5] == 0x33);
}

}

int main() {
    Require(sceNpCommerceDialogGetStatus() == statusNone);
    Require(sceNpCommerceDialogInitialize() == 0);
    Require(sceNpCommerceDialogGetStatus() == statusInitialized);

    Require(sceNpCommerceDialogOpen2() == 0);
    Require(sceNpCommerceDialogUpdateStatus() == statusFinished);
    Require(sceNpCommerceDialogGetStatus() == statusFinished);
    RequireCanceledResult();

    Require(sceNpCommerceDialogClose() == 0);
    Require(sceNpCommerceDialogGetStatus() == statusFinished);
    Require(sceNpCommerceDialogTerminate() == 0);
    Require(sceNpCommerceDialogGetStatus() == statusNone);

    alignas(8) std::uint8_t param[0x40] = {};
    Require(sceNpCommerceDialogInitialize() == 0);
    Require(sceNpCommerceDialogOpen(param) == 0);
    Require(sceNpCommerceDialogOpen2() == 0);
    Require(sceNpCommerceDialogUpdateStatus() == statusFinished);
    RequireCanceledResult();
    Require(sceNpCommerceDialogTerminate() == 0);
    Require(sceNpCommerceDialogGetStatus() == statusNone);
    return 0;
}
