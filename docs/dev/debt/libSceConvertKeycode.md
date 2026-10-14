# libSceConvertKeycode technical debt

### Unknown function info

- [sceConvertKeycodeGetCharacter](../../../core/libs/prx/libSceConvertKeycode/Export.cpp) (libSceConvertKeycode) - the signature `(uint16_t keycode, uint32_t, uint32_t keyboardType, char16_t* character)` is inferred from PPSA12361, which passes a 16-bit keycode, 0, the type from `sceConvertKeycodeGetImeKeyboardType` and a pointer it reads one UTF-16 unit from when the result is 0. The meaning of the second argument is unknown; a value other than 0 throws, and so does a keyboard type other than 0.

### Functional

- [sceConvertKeycodeGetCharacter](../../../core/libs/prx/libSceConvertKeycode/Export.cpp) (libSceConvertKeycode) takes the keycode as a USB HID keyboard usage and returns the unshifted character of the US layout for letters, digits, punctuation, space and the keypad. A keycode without a character returns 0 with the character 0; whether the console returns an error instead is not measured.
