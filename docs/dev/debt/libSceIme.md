# libSceIme technical debt

### Unknown function info

- [sceImeGetPanelPositionAndForm](../../../core/libs/prx/libSceIme/Export.cpp) (libSceIme) - the output is taken to be the `PositionAndForm` that `sceImeDialogGetPanelPositionAndForm` fills; it is never written, since no panel can be open. That a closed panel is reported before a null output is assumed by analogy with `sceImeSetCaret`, not confirmed on a PS5 title

### Functional

- [sceImeKeyboardGetInfo](../../../core/libs/prx/libSceIme/Export.cpp) (libSceIme) returns `0x80bc0023` (no resource id) for every id while a keyboard is open, since the IME keyboard never reports a connected device. [sceImeKeyboardSetMode](../../../core/libs/prx/libSceIme/Export.cpp) validates the mode bits but the mode has no effect, as no IME keyboard events are delivered.
- [sceImeKeyboardGetResourceId](../../../core/libs/prx/libSceIme/Export.cpp) (libSceIme) reports that no USB keyboard is connected (`0x80bc0004`, as [shadPS4](https://github.com/shadps4-emu/shadPS4) does) because IME keyboard events are not delivered to the handler, although [libSceKeyboard](../../../core/libs/prx/libSceKeyboard/src/keyboard_impl.cpp) exposes the host keyboard
