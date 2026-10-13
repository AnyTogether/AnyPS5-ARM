# libSceSystemGesture technical debt

### Silent stubs

- [System gesture recognizers](../../../core/libs/prx/libSceSystemGesture/Export.cpp) (libSceSystemGesture) - `sceSystemGestureGetPrimitiveTouchEvents`, `GetPrimitiveTouchEventsCount`, `GetTouchEvents`, `GetPrimitiveTouchEventByIndex` and the recognizer append, remove, reset and update calls report that no touch input exists and keep no recognizer state, so a title never receives a gesture event. Handle and pointer arguments are still checked. Error codes follow the 0x80D1 values main already uses in this file; KytyPS5 uses 0x8089 (INVALID_ARGUMENT 0x80890001, INVALID_HANDLE 0x80890006), and which one the console returns is not verified
