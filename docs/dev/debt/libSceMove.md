# libSceMove technical debt

### Silent stubs

- [libSceMove](../../../core/libs/prx/libSceMove/Export.cpp) implements only the no-controller path: initialization and termination succeed, `sceMoveOpen` returns a new handle, `sceMoveClose` and `sceMoveResetLightSphere` succeed for an open handle, and the device info, state, extension port, vibration and `sceMoveSetLightSphere` calls return 1 (no controller connected) and write nothing

### Unknown function info

- [libSceMove](../../../core/libs/prx/libSceMove/Export.cpp) (libSceMove) - behaviour, error codes and the handle values (`0x30B0100`, then every `0x100`) follow [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/f68923fe807f657348e6719ce658bcbd0a2b1c72/src/core/libraries/move/move.cpp) (PS4), which checks no handle or open arguments; none is measured on a PS5. Signatures follow [Orbital](https://github.com/AlexAltea/orbital/blob/master/tools/ida/db_types.json), except `sceMoveGetExtensionPortInfo`, which follows shadPS4. Before `sceMoveInit` and after `sceMoveTerm` every other call returns `NOT_INIT` (`0x80EE0001`); a null output or a negative timestamp returns `INVALID_ARG` (`0x80EE0003`). Closes when: measured on a PS5
- [libSceMove](../../../core/libs/prx/libSceMove/Export.cpp) (libSceMove) - a handle that was never opened, is closed or was opened before `sceMoveTerm` throws: the console's `INVALID_HANDLE` (`0x80EE0004`) result and its order against `INVALID_ARG` are not known. `sceMoveOpen` throws for a user other than the initial user and for a type and index that are already open, whose console results are not known, and accepts any type and index. Closes when: measured on a PS5
