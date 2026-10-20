# libSceAcm technical debt

### Silent stubs

- [libSceAcm](../../../core/libs/prx/libSceAcm/Export.cpp) batches execute as silent no-ops, so `sceAcm_ConvReverb_SharedInput`, `sceAcm_FFT` and `sceAcm_Panner` return success without encoding audio commands.

### Unknown function info

- Context validation error codes (0x81940002 for bad context and 0x81940006 for bad pointer) for [libSceAcm](../../../core/libs/prx/libSceAcm/Export.cpp) follow prosper's `hle_audio_spatial.cpp`. KytyPS5 (`acm.cpp`) and prosper do not track individual batch identifiers, so `sceAcmBatchWait` returns success for valid contexts without inspecting batch IDs. Hardware ACM DSP coprocessor scheduling and console error verification remain unmeasured.
- [sceAcm_ConvReverb_SharedIr, sceAcm_IFFT](../../../core/libs/prx/libSceAcm/Export.cpp) (libSceAcm) - their names and NIDs are in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceAcm.c), but no credible prototypes were found. They are declared without parameters solely to resolve known imports; this is not an ABI claim
- PPSA02530 imports declared without parameters, signatures unknown, added without an implementation because the title fails to load without them: [sceAcmBatchJobPriority](../../../core/libs/prx/libSceAcm/Export.cpp) (libSceAcm) and [scePadVrControllerGetTriggerEffectStates](../../../core/libs/prx/libScePad/Export.cpp) (libScePad).
