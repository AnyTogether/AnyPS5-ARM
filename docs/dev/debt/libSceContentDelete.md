# libSceContentDelete technical debt

### Functional

- [sceContentDeleteById and sceContentDeleteByPath](../../../core/libs/prx/libSceContentDelete/Export.cpp) (libSceContentDelete) delete from a content library that is empty on the host, as nothing is exported to it, so both throw for every content id and path once the arguments and the initialization are checked: no reference gives the console's error for content that is not in the library ([SharpProspero](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Interop/Content/ContentDelete.cs#L25-L42) names only `0x809D5006`, no permission). The signatures, a 64-bit content id and a UTF-8 path, follow [Orbital](https://github.com/AlexAltea/orbital/blob/cc408367da6a6ebbf5ac1ac559fefeadc73b2831/tools/ida/db_types.json#L541-L542) and SharpProspero, which agree. A null path and a call outside `sceContentDeleteInitialize` and `sceContentDeleteTerminate` throw, as the console's errors for them are unknown, and the order of the two checks is unverified.

### Unknown function info

- [sceContentDeleteByIdListForSf, sceContentDeleteGlobalMstat, sceContentDeleteMemoryInitialize, sceContentDeleteMemoryTerminate](../../../core/libs/prx/libSceContentDelete/Export.cpp) (libSceContentDelete) - exported symbols from decrypted PS5 firmware 1.00–3.20 libSceContentDelete.sprx; parameter lists and return values are unknown/unverified and no reference (KytyPS5, shadPS4, fpPS4, SharpProspero) documents their signatures. Declared as stubs that throw via `NotImplemented_nid_no_patch`
