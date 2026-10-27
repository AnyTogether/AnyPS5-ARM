#ifndef CORE_LIBS_PRX_LIBSCEIME_INCLUDE_IMEINPUT_HPP
#define CORE_LIBS_PRX_LIBSCEIME_INCLUDE_IMEINPUT_HPP

#include <cstddef>
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
    // Empties the text: a phone sends the whole text it typed, which replaces what was there.
    Clear,
};

struct ImeHostInput {
    ImeHostInputKind kind = ImeHostInputKind::Text;
    char text[32] = {};
};

extern "C" void ImePublishInput_nid_postfix(const ImeHostInput& input);
extern "C" bool ImeCapturesKeyboard_nid_postfix();

// What text the game asks for, for a phone to type it (RemotePad's prompt): sceImeOpen's
// keyboard or sceImeDialogInit's dialog, with the dialog's title and placeholder and the text
// either starts with, all UTF-16 as the game gave them (cut to fit, NUL-terminated).
struct ImeHostPrompt {
    // 0 while nothing asks for text; a new number for each keyboard or dialog opened.
    std::uint32_t id = 0;
    // 1 keyboard (sceImeOpen), 2 dialog (sceImeDialogInit).
    std::uint32_t kind = 0;
    std::uint32_t type = 0;
    std::uint32_t enterLabel = 0;
    bool multiline = false;
    std::uint32_t maxLength = 0;
    char16_t title[128] = {};
    char16_t placeholder[128] = {};
    char16_t text[2049] = {};
};

// The dialog says what it asks for (nullptr once it is done); id is filled in by libSceIme.
extern "C" void ImeSetHostPrompt_nid_no_patch(const ImeHostPrompt* prompt);
// Changes whenever another prompt opens or the last one closes.
extern "C" std::uint32_t ImeHostPromptRevision_nid_postfix();
// The prompt open now (id 0 when none); returns the revision it belongs to.
extern "C" std::uint32_t ImeGetHostPrompt_nid_postfix(ImeHostPrompt* prompt);

using ImeHostTextSink = void (*)(ImeHostInputKind kind, const char16_t* text, std::size_t length);

extern "C" void ImeSetHostTextSink_nid_no_patch(ImeHostTextSink sink);

struct ImeHostPad {
    std::uint32_t buttons = 0;
    std::uint8_t leftX = 128;
    std::uint8_t leftY = 128;
    std::uint8_t l2 = 0;
};

using ImeHostPadSink = void (*)(const ImeHostPad& pad);

extern "C" bool ImeCapturesPad_nid_postfix();
extern "C" void ImePublishPad_nid_postfix(const ImeHostPad& pad);
extern "C" void ImeSetHostPadSink_nid_no_patch(ImeHostPadSink sink);

#endif
