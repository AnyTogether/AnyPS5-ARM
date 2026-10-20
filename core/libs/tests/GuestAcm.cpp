#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstddef>
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceAcmContextCreate(std::uint32_t*);
int APS5_VABI sceAcmContextDestroy(std::uint32_t);
int APS5_VABI sceAcmBatchStartBuffer(std::uint32_t, const void*, std::size_t, void*, std::uint32_t*);
int APS5_VABI sceAcmBatchStartBuffers(std::uint32_t, std::uint32_t, const void* const[], void*, std::uint32_t*);
int APS5_VABI sceAcmBatchWait(std::uint32_t, std::uint32_t, std::uint32_t);
int APS5_VABI sceAcm_ConvReverb_SharedInput(void);
int APS5_VABI sceAcm_FFT(void);
int APS5_VABI sceAcm_Panner(void);
}

static void Require(bool value) {
    if (!value) std::abort();
}

constexpr int BadContext = static_cast<int>(0x81940002);
constexpr int BadPointer = static_cast<int>(0x81940006);

int main() {
    Require(sceAcmContextCreate(nullptr) == BadPointer);
    Require(sceAcmContextDestroy(0) == BadContext);
    Require(sceAcmContextDestroy(999999) == BadContext);

    std::uint32_t context1 = 0;
    Require(sceAcmContextCreate(&context1) == 0 && context1 != 0);

    std::uint32_t context2 = 0;
    Require(sceAcmContextCreate(&context2) == 0 && context2 != 0 && context2 != context1);

    std::uint32_t batch1 = 0;
    Require(sceAcmBatchStartBuffer(0, nullptr, 0, nullptr, &batch1) == BadContext);
    Require(sceAcmBatchStartBuffer(999999, nullptr, 0, nullptr, &batch1) == BadContext);
    Require(sceAcmBatchStartBuffer(context1, nullptr, 0, nullptr, nullptr) == BadPointer);
    Require(sceAcmBatchStartBuffer(context1, nullptr, 0, nullptr, &batch1) == 0 && batch1 != 0);

    Require(sceAcmBatchWait(0, batch1, 0) == BadContext);
    Require(sceAcmBatchWait(999999, batch1, 0) == BadContext);
    Require(sceAcmBatchWait(context1, batch1, 0) == 0);
    Require(sceAcmBatchWait(context1, batch1, 0) == 0);

    std::uint32_t batch2 = 0;
    Require(sceAcmBatchStartBuffers(0, 0, nullptr, nullptr, &batch2) == BadContext);
    Require(sceAcmBatchStartBuffers(999999, 0, nullptr, nullptr, &batch2) == BadContext);
    Require(sceAcmBatchStartBuffers(context2, 0, nullptr, nullptr, nullptr) == BadPointer);
    Require(sceAcmBatchStartBuffers(context2, 0, nullptr, nullptr, &batch2) == 0 && batch2 != 0);
    Require(sceAcmBatchWait(context2, batch2, 0) == 0);

    Require(sceAcm_ConvReverb_SharedInput() == 0);
    Require(sceAcm_FFT() == 0);
    Require(sceAcm_Panner() == 0);

    Require(sceAcmContextDestroy(context1) == 0);
    Require(sceAcmContextDestroy(context1) == BadContext);
    Require(sceAcmBatchStartBuffer(context1, nullptr, 0, nullptr, &batch1) == BadContext);
    Require(sceAcmBatchWait(context1, batch1, 0) == BadContext);

    Require(sceAcmContextDestroy(context2) == 0);
    Require(sceAcmContextDestroy(context2) == BadContext);

    return 0;
}
