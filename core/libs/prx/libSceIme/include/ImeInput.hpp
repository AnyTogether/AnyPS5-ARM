#ifndef CORE_LIBS_PRX_LIBSCEIME_INCLUDE_IMEINPUT_HPP
#define CORE_LIBS_PRX_LIBSCEIME_INCLUDE_IMEINPUT_HPP

#include <cstdint>

enum class ImeHostInputKind : std::uint32_t {
    Text,
    Backspace,
    Delete,
    Left,
    Right,
    Home,
    End,
    Enter,
    Escape,
};

struct ImeHostInput {
    ImeHostInputKind kind = ImeHostInputKind::Text;
    char text[32] = {};
};

extern "C" void ImePublishInput_nid_postfix(const ImeHostInput& input);
extern "C" bool ImeCapturesKeyboard_nid_postfix();

#endif
