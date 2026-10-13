#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdlib>

extern "C" {
int APS5_VABI sceNpAuthGetAuthorizedAppCode();
}

int main() {
    constexpr int kSignedOut = static_cast<int>(0x80550006);
    if (sceNpAuthGetAuthorizedAppCode() != kSignedOut) std::abort();
    if (sceNpAuthGetAuthorizedAppCode() != kSignedOut) std::abort();
    return 0;
}
