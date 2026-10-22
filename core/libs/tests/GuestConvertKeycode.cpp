#include "SceTypes.hpp"
#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdlib>
#include <initializer_list>
#include <stdexcept>

extern "C" {
int APS5_VABI sceConvertKeycodeGetVirtualKeycode(std::uint16_t, std::uint32_t, std::uint16_t*);
int APS5_VABI sceConvertKeycodeGetImeKeyboardType(std::int32_t, std::uint32_t*);
int APS5_VABI sceConvertKeycodeGetCharacter(std::uint16_t, std::uint32_t, std::uint32_t, char16_t*);
}

static void Require(bool value) { if (!value) std::abort(); }

int main() {
    constexpr int invalidAddress = static_cast<int>(0x80BC0031u);
    constexpr int invalidUserId = static_cast<int>(0x80BC0010u);

    Require(sceConvertKeycodeGetImeKeyboardType(0, nullptr) == invalidAddress);
    Require(sceConvertKeycodeGetImeKeyboardType(-1, nullptr) == invalidAddress);

    std::uint16_t virtualKey = 0xABCD;
    Require(sceConvertKeycodeGetVirtualKeycode(4, 0, nullptr) == invalidAddress);
    Require(sceConvertKeycodeGetVirtualKeycode(4, 0, &virtualKey) == static_cast<int>(0x80BC001Du));
    Require(virtualKey == 0xABCD);
    Require(sceConvertKeycodeGetVirtualKeycode(4, 40, &virtualKey) == static_cast<int>(0x80BC001Du));
    Require(sceConvertKeycodeGetVirtualKeycode(4, 4, &virtualKey) == 0 && virtualKey == 65);
    Require(sceConvertKeycodeGetVirtualKeycode(4, 9, &virtualKey) == 0 && virtualKey == 81);
    Require(sceConvertKeycodeGetVirtualKeycode(100, 4, &virtualKey) == 0 && virtualKey == 255);
    Require(sceConvertKeycodeGetVirtualKeycode(136, 24, &virtualKey) == 0 && virtualKey == 21);
    Require(sceConvertKeycodeGetVirtualKeycode(65535, 4, &virtualKey) == 0 && virtualKey == 255);
    for (std::uint32_t layout : {2u, 3u, 12u, 31u, 39u}) {
        virtualKey = 0xABCD;
        bool rejected = false;
        try {
            sceConvertKeycodeGetVirtualKeycode(28, layout, &virtualKey);
        } catch (const std::runtime_error&) {
            rejected = true;
        }
        Require(rejected && virtualKey == 0xABCD);
    }

    std::uint32_t type = 0xFFFFFFFFu;
    Require(sceConvertKeycodeGetImeKeyboardType(-1, &type) == invalidUserId);
    Require(type == 0xFFFFFFFFu);

    bool rejected = false;
    try {
        sceConvertKeycodeGetImeKeyboardType(0, &type);
    } catch (const std::runtime_error&) {
        rejected = true;
    }
    Require(rejected && type == 0xFFFFFFFFu);

    Require(sceConvertKeycodeGetCharacter(4, 0, 0, nullptr) == invalidAddress);
    char16_t character = u'?';
    Require(sceConvertKeycodeGetCharacter(4, 0, 0, &character) == static_cast<int>(0x80BC001Du));
    Require(character == u'?');
    Require(sceConvertKeycodeGetCharacter(4, 0, 40, &character) == static_cast<int>(0x80BC001Du));
    for (std::uint32_t state : {0u, 0x4000000u}) {
        Require(sceConvertKeycodeGetCharacter(4, state, 4, &character) == 0 && character == u'a');
        Require(sceConvertKeycodeGetCharacter(30, state, 4, &character) == 0 && character == u'1');
        Require(sceConvertKeycodeGetCharacter(58, state, 4, &character) == 0 && character == 0);
        Require(sceConvertKeycodeGetCharacter(65535, state, 4, &character) == 0 && character == 0);
    }
    Require(sceConvertKeycodeGetCharacter(4, 0x200, 4, &character) == 0 && character == u'A');
    Require(sceConvertKeycodeGetCharacter(4, 0x20000, 4, &character) == 0 && character == u'A');
    Require(sceConvertKeycodeGetCharacter(4, 0x20200, 4, &character) == 0 && character == u'a');
    Require(sceConvertKeycodeGetCharacter(30, 0x200, 4, &character) == 0 && character == u'!');
    Require(sceConvertKeycodeGetCharacter(89, 0, 4, &character) == 0 && character == 0);
    Require(sceConvertKeycodeGetCharacter(89, 0x10000, 4, &character) == 0 && character == u'1');
    Require(sceConvertKeycodeGetCharacter(89, 0x10200, 4, &character) == 0 && character == u'1');
    Require(sceConvertKeycodeGetCharacter(4, 0, 9, &character) == 0 && character == u'q');
    Require(sceConvertKeycodeGetCharacter(28, 0, 2, &character) == 0 && character == u'z');
    Require(sceConvertKeycodeGetCharacter(20, 0x4000, 2, &character) == 0 && character == u'@');
    Require(sceConvertKeycodeGetCharacter(47, 0x20000, 3, &character) == 0 && character == 220);
    Require(sceConvertKeycodeGetCharacter(47, 0x20200, 3, &character) == 0 && character == 200);
    Require(sceConvertKeycodeGetCharacter(4, 0x4000000, 24, &character) == 0 && character == 0x3141);
    Require(sceConvertKeycodeGetCharacter(5, 0x4000000, 30, &character) == 0 && character == 1575);
    Require(sceConvertKeycodeGetCharacter(5, 0x4000200, 30, &character) == 0 && character == 1570);
    Require(sceConvertKeycodeGetCharacter(30, 0x4000300, 30, &character) == 0 && character == 0x200D);
    Require(sceConvertKeycodeGetCharacter(31, 0x4000300, 30, &character) == 0 && character == 0x200C);
    Require(sceConvertKeycodeGetCharacter(32, 0x4000300, 30, &character) == 0 && character == 0x200E);
    Require(sceConvertKeycodeGetCharacter(33, 0x4000300, 30, &character) == 0 && character == 0x200F);
    for (std::uint32_t layout = 1; layout <= 30; ++layout) {
        for (std::uint16_t key : {83, 224, 225, 226, 227, 228, 229, 230, 231}) {
            Require(sceConvertKeycodeGetCharacter(key, 0xFFFFFFFFu, layout, &character) == 0 && character == 0);
        }
    }
    return 0;
}
