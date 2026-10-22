# libSceKeyboard technical debt

### Functional

- [sceKeyboardGetKey2Char](../../../core/libs/prx/libSceKeyboard/src/keyboard_impl.cpp): the original validates HID usages 4 through 231 before the handle and preserves unconverted HID usages in the output with `processed == 0`. The host instead accepts out-of-range usages and writes zero for unconverted keys. The original ignores the Kana LED, while the host throws for it. This partially implemented function contains `NotImplemented_nid_no_patch(__func__)`; its body is preserved under the requested restriction.

### Unknown function info

- [sceDbgKeyboardClose, sceDbgKeyboardGetKey2Char, sceDbgKeyboardInit, sceDbgKeyboardOpen, sceDbgKeyboardRead, sceDbgKeyboardReadState](../../../core/libs/prx/libSceKeyboard/Export.cpp) (libSceKeyboard) - names and NIDs are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceKeyboard.c), but no credible prototypes were found. They are declared without parameters solely to resolve known imports; this is not an ABI claim.
- [sceKeyboardGetDeviceInfo and sceKeyboardSetProcessFocus](../../../core/libs/prx/libSceKeyboard/Export.cpp): pointer arguments are passed to device ioctls. Device-info storage is 168 bytes in the connection-query caller, but its fields and the process-focus layout remain unresolved.
- [sceKeyboardConnectPort, sceKeyboardDisconnectPort and sceKeyboardDeviceOpen](../../../core/libs/prx/libSceKeyboard/Export.cpp): argument widths are confirmed. The meaning/order of the two 32-bit port arguments and the final 32-bit device-open argument still require the device-service backend.
- [sceKeyboardPadEmulateClose and sceKeyboardPadEmulateOpen](../../../core/libs/prx/libSceKeyboard/Export.cpp): the supplied keyboard library has neither export; their signatures remain unresolved.
