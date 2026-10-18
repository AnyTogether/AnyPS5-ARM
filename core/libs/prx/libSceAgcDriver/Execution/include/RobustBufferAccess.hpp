#ifndef CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_ROBUSTBUFFERACCESS_HPP
#define CORE_LIBS_PRX_LIBSCEAGCDRIVER_EXECUTION_INCLUDE_ROBUSTBUFFERACCESS_HPP

#include <vulkan/vulkan.h>

namespace AgcDriver {

inline bool RobustBufferAccess2Usable(VkDriverId driver) {
    return driver != VK_DRIVER_ID_AMD_PROPRIETARY;
}

}

#endif
