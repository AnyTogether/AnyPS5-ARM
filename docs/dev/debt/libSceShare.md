# libSceShare technical debt

### Unknown function info

- [sceShareGetCurrentStatus](../../../core/libs/prx/libSceShare/Export.cpp) (libSceShare) - validation (feature flag non-zero, status non-null) and the all-zero 16-byte status taken from the [KytyPS5](https://github.com/KytyPS5/KytyPS5) reimplementation, not confirmed on a PS5 title; the meaning of the recording status values is unknown
- [sceShareGetRunningStatus](../../../core/libs/prx/libSceShare/Export.cpp) (libSceShare) - only the first 32-bit word of the status is known: PPSA01317 treats bits 0x3c of it as a running share feature and gives the call a 40-byte buffer. The host never records or broadcasts, so it stores 0 in that word and leaves the rest untouched; a null status returns `INVALID_PARAM` by analogy with `sceShareGetCurrentStatus`
- [sceShareSetContentParamForApplicationTitle](../../../core/libs/prx/libSceShare/Export.cpp) (libSceShare) - imported by PPSA12544's Unity plugins; the signature follows [KytyPS5](https://github.com/KytyPS5/KytyPS5/blob/main/src/libs/libShare.cpp), not confirmed on a PS5 title. The application title is only checked for null, as KytyPS5 does, since nothing is captured

### Functional

- [sceShareCaptureVideoClipExtended](../../../core/libs/prx/libSceShare/Export.cpp) (libSceShare) - imported by PPSA12544's Share plugin; the signature (extended parameter, request id) and the answer follow [KytyPS5](https://github.com/KytyPS5/KytyPS5/blob/147188b143f67c27d8da396e759c19336f64c105/src/libs/libShare.cpp), not confirmed on a PS5 title. Nothing is captured, so, like `sceShareCaptureScreenshotExtended`, it stores the invalid request id -1 when the pointer is not null and returns `NOT_SUPPORTED` without reading the extended parameter, whose layout is unknown
