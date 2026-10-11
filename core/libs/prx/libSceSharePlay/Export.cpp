#include <cstdint>
#include <cstddef>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

static constexpr int SCE_SHARE_PLAY_ERROR_INVALID_ARGS = static_cast<int>(0x810E0001);
static constexpr std::int32_t SCE_USER_SERVICE_USER_ID_INVALID = -1;

extern "C" {

int APS5_VABI sceSharePlayInitialize(void* heap, size_t heapSize) {
    (void)heap;
    if (heapSize == 0) APS5_INVALID_ARG_EX;
    return 0;
}

int APS5_VABI sceSharePlayTerminate(void) {
    return 0;
}

int APS5_VABI sceSharePlayGetCurrentConnectionInfoA(SharePlayConnectionInfoA* info) {
    if (info == nullptr) return SCE_SHARE_PLAY_ERROR_INVALID_ARGS;
    *info = {};
    info->hostUserId = SCE_USER_SERVICE_USER_ID_INVALID;
    info->visitorUserId = SCE_USER_SERVICE_USER_ID_INVALID;
    return 0;
}

}
