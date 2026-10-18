#include "prx/libSceAgc/Misc/include/Debug.hpp"

#include <cstdint>
#include "SceTypes.hpp"
#include "prx/libc/include/General.hpp"

extern "C" {

int APS5_VABI sceAgcDebugRaiseException(std::uint32_t exceptionId) {
    APS5_LOG_OUT("sceAgcDebugRaiseException exceptionId=0x%08x", static_cast<unsigned>(exceptionId));
    return 0;
}

}
