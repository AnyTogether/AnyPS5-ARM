# libSceOpusCeltDec technical debt

### Unknown function info

- [sceOpusCeltDecCreateEx, sceOpusCeltDecDecode, sceOpusCeltDecDestroy, sceOpusCeltDecGetSize, sceOpusCeltDecInitialize, sceOpusCeltDecTerminate](../../../core/libs/prx/libSceOpusCeltDec/Export.cpp) (libSceOpusCeltDec) - imported by PPSA99001, which fails to load without the module; added without an implementation. Their signatures match libSceOpusDec's in [ProsperoRadio](https://github.com/blackbearreloaded/ProsperoRadio/blob/2c4029c3a8f43e9e1dfef98374d94d99b14d745d/src/opus_decoder.cpp). PPSA99001 opens this decoder only as a fallback when libSceOpusDec reports a retryable error for a CELT packet, which [libSceOpusDec](../../../core/libs/prx/libSceOpusDec/Export.cpp) here never returns, so the fallback is not reached
