# libSceSharePlay technical debt

### Unknown function info

- [sceSharePlayInitialize](../../../core/libs/prx/libSceSharePlay/Export.cpp) (libSceSharePlay) - the library keeps no state, so the heap is not used. A null heap is accepted: PPSA11386 passes a null heap and 0x1800 bytes and stops on any non-zero result. The error for a zero size is unknown, so it throws

### Functional

- [sceSharePlayGetCurrentConnectionInfoA](../../../core/libs/prx/libSceSharePlay/Export.cpp) (libSceSharePlay) - reports no Share Play session, as the library keeps none: status 0 (DORMANT), mode 0, empty online IDs, account IDs 0 and both user IDs -1 (`SCE_USER_SERVICE_USER_ID_INVALID`). A null pointer returns `SCE_SHARE_PLAY_ERROR_INVALID_ARGS` (0x810E0001). The 72-byte `SceSharePlayConnectionInfoA` layout and the error code follow [KytyPS5](https://github.com/KytyPS5/KytyPS5/blob/main/src/libs/libNet.cpp) and [fpPS4](https://github.com/red-prig/fpPS4/blob/trunk/src/ps4_libsceshareplay.pas), which agree on both; KytyPS5 sets the user IDs to -1 and fpPS4 leaves them 0, and which one the console returns is not verified. KytyPS5 also returns `SCE_SHARE_PLAY_ERROR_NOT_INITIALIZED` before `sceSharePlayInitialize`; this library keeps no initialization state and does not.
- [sceSharePlayProhibitController](../../../core/libs/prx/libSceSharePlay/Export.cpp) (libSceSharePlay) - accepts 0 (allow) and 1 (prohibit) and returns 0, following [sharpemu](https://github.com/sharpemu/sharpemu/blob/a2983692930564815a77f81e74c151268f5b935f/src/SharpEmu.Libs/Share/SharePlayExports.cs#L9-L31). The setting is not stored, as no Share Play session or visitor controller exists and no export reads it back. sharpemu rejects any other value with its synthetic `0x80020003`, not a Share Play code, so other values throw. Like the other exports here it does not require `sceSharePlayInitialize`. The `int` argument type and the console's error for other values are unverified
