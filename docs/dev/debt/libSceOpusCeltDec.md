# libSceOpusCeltDec technical debt

### Unknown function info

- [sceOpusCeltDecCreate, sceOpusCeltDecCtl, sceOpusCeltDecDecodeFloat, sceOpusCeltDecDecodeFloatWithPriority, sceOpusCeltDecDecodeWithPriority](../../../core/libs/prx/libSceOpusCeltDec/Export.cpp) (libSceOpusCeltDec) - names and NIDs are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceOpusCeltDec.c), but no credible prototypes were found. They are declared without parameters solely to resolve known imports; this is not an ABI claim.
- [sceOpusCeltDecCreateEx, sceOpusCeltDecDecode, sceOpusCeltDecDestroy, sceOpusCeltDecGetSize, sceOpusCeltDecInitialize, sceOpusCeltDecTerminate](../../../core/libs/prx/libSceOpusCeltDec/Export.cpp) (libSceOpusCeltDec) - imported by PPSA99001. Their signatures are assumed to match libSceOpusDec's in [ProsperoRadio](https://github.com/blackbearreloaded/ProsperoRadio/blob/2c4029c3a8f43e9e1dfef98374d94d99b14d745d/src/opus_decoder.cpp), and the 640-byte state size, context handling and byte-count return are taken from [libSceOpusDec](../../../core/libs/prx/libSceOpusDec/Export.cpp); none of them was measured on a console. PPSA99001 opens this decoder only as a fallback when libSceOpusDec reports a retryable error for a CELT packet, which libSceOpusDec here never returns, so the fallback is not reached

### Functional

- [sceOpusCeltDecDecode](../../../core/libs/prx/libSceOpusCeltDec/Export.cpp) (libSceOpusCeltDec) decodes with the FFmpeg decoder of [libSceOpusDec](../../../core/libs/prx/libSceOpusDec/include/OpusDecoder.hpp) and shares its limits. Packets whose TOC configuration is below 16 (SILK and hybrid) throw: whether the console decodes them or returns an error code is unknown. Contexts and decoder states are separate from libSceOpusDec's
