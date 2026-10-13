# libSceAcm technical debt

### Silent stubs

- [libSceAcm](../../../core/libs/prx/libSceAcm/Export.cpp) batches execute as silent no-ops, so `sceAcm_ConvReverb_SharedInput`, `sceAcm_FFT` and `sceAcm_Panner` return success without encoding audio commands.

### Unknown function info

- PPSA02530 imports declared without parameters, signatures unknown, added without an implementation because the title fails to load without them: [sceAcmBatchJobPriority](../../../core/libs/prx/libSceAcm/Export.cpp) (libSceAcm) and [scePadVrControllerGetTriggerEffectStates](../../../core/libs/prx/libScePad/Export.cpp) (libScePad).

