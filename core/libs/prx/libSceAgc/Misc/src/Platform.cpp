#include "prx/libSceAgc/Misc/include/Platform.hpp"
#include "prx/libSceAgc/Command/include/Packet.hpp"

#include <atomic>
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <mutex>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

namespace {

constexpr int AGC_ERROR_INVALID_ALIGNMENT = static_cast<int>(0x8a6c0002u);
constexpr int AGC_ERROR_INVALID_VALUE = static_cast<int>(0x8a6c000bu);
constexpr int AGC_ERROR_ALREADY_INITIALIZED = static_cast<int>(0x8a6c0048u);
constexpr int AGC_ERROR_NOT_INITIALIZED = static_cast<int>(0x8a6c0049u);


}

extern "C" {

int APS5_VABI sceAgcGetIsTrinityMode(bool* isTrinityMode) {
    Agc::Command::CheckAddress(reinterpret_cast<std::uintptr_t>(isTrinityMode), alignof(bool), __func__);
    *isTrinityMode = false;
    return 0;
}


}
