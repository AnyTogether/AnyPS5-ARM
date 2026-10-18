#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>

extern "C" int APS5_VABI sceKernelIsThreadSanitizerEnabled(void);

int main() {
    if (sceKernelIsThreadSanitizerEnabled() != 0) std::abort();
    return 0;
}
