# libSceNpTus technical debt

### Unknown function info

- [SceNpTusVariableA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - the layout of the output array of `sceNpTusGetMultiSlotVariableAAsync` and of `outVariable` in `sceNpTusAddAndGetVariableAAsync` is not verified, so the output is never written and `variableArraySize` / `outVariableSize` are not checked. The signatures and the community error codes follow [shadPS4](https://github.com/shadps4-emu/shadPS4/tree/main/src/core/libraries/np/np_tus), which fpPS4 agrees with for the context and request calls; no console measurement.

### Functional

- [sceNpTusCreateNpTitleCtxA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - creates a title context without checking sign-in, up to 32 contexts (`TOO_MANY_OBJECTS` beyond); shadPS4 returns the `sceNpGetNpId` error instead. Requests are limited to 256, and the limits are not measured on a console.
- [sceNpTusPollAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - there is no PSN, so the four `*Async` calls that validate their arguments start a request that finishes at once with `SCE_NP_ERROR_SIGNED_OUT` (`ABORTED` after `sceNpTusAbortRequest`), reported by the poll result. Poll returns 1 until an operation has started. The slot, option and array-length checks follow shadPS4 and are not measured on a console.
