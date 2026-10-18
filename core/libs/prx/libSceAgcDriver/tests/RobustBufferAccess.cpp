#include "prx/libSceAgcDriver/Execution/include/RobustBufferAccess.hpp"
#include <cstdio>

namespace {

struct Case {
    VkDriverId driver;
    bool usable;
};

constexpr Case Cases[]{
    {VK_DRIVER_ID_AMD_PROPRIETARY, false},
    {VK_DRIVER_ID_AMD_OPEN_SOURCE, true},
    {VK_DRIVER_ID_MESA_RADV, true},
    {VK_DRIVER_ID_NVIDIA_PROPRIETARY, true},
    {VK_DRIVER_ID_INTEL_PROPRIETARY_WINDOWS, true},
    {VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA, true},
    {VK_DRIVER_ID_MESA_LLVMPIPE, true},
    {VK_DRIVER_ID_MOLTENVK, true},
};

}

int main() {
    int failures = 0;
    for (const auto& item : Cases) {
        if (AgcDriver::RobustBufferAccess2Usable(item.driver) != item.usable) {
            std::fprintf(stderr, "driver %d: expected robustBufferAccess2 to be %s\n", static_cast<int>(item.driver), item.usable ? "usable" : "unusable");
            ++failures;
        }
    }
    return failures == 0 ? 0 : 1;
}
