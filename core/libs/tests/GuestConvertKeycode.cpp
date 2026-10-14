#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>

extern "C" {
int APS5_VABI sceConvertKeycodeGetImeKeyboardType(std::int32_t, std::uint32_t*);
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    constexpr int invalidAddress = static_cast<int>(0x80BC0031u);
    constexpr int invalidUserId = static_cast<int>(0x80BC0010u);

    Require(sceConvertKeycodeGetImeKeyboardType(0, nullptr) == invalidAddress);
    Require(sceConvertKeycodeGetImeKeyboardType(-1, nullptr) == invalidAddress);

    std::uint32_t type = 0xFFFFFFFFu;
    Require(sceConvertKeycodeGetImeKeyboardType(-1, &type) == invalidUserId);
    Require(type == 0xFFFFFFFFu);

    Require(sceConvertKeycodeGetImeKeyboardType(0, &type) == 0);
    Require(type == 0);

    type = 0xFFFFFFFFu;
    Require(sceConvertKeycodeGetImeKeyboardType(1, &type) == 0);
    Require(type == 0);
    return 0;
}
