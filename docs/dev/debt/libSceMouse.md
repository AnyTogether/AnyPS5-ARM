# libSceMouse technical debt

### Functional

- [sceMouseResetAbsolutePosition](../../../core/libs/prx/libSceMouse/Export.cpp) (libSceMouse) - signature taken from a call site (a handle, then x and y as 16-bit values: PPSA30601 passes the centre of its display size); behaviour not measured on hardware. Validates initialization and the handle like `sceMouseRead` and returns `MOUSE_OK`; the position is not stored because the library reports relative motion only
