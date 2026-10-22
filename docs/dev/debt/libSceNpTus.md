# libSceNpTus technical debt

### Unknown function info

- [TUS variable outputs](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - the layouts of the variable arrays of the `sceNpTusGetMultiSlotVariable*` calls and of `outVariable` in `sceNpTusAddAndGetVariableAAsync` are not verified, so the output is never written and `variableArraySize` / `outVariableSize` are not checked; shadPS4, and RPCS3 in its PS3 `sceNpTusGetMultiSlotVariable*` and `sceNpTusAddAndGetVariable*` calls, return `INVALID_ALIGNMENT` unless the size is `arrayLen` variables of the call's type, or one variable for `outVariable`. The signatures and the community error codes follow [shadPS4](https://github.com/shadps4-emu/shadPS4/tree/main/src/core/libraries/np/np_tus), which fpPS4 agrees with for the context and request calls; no console measurement.
- [Multi-slot variable calls](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - the argument checks of the multi-slot get, set and delete calls are not measured on a console; they follow [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/c1b26558352b863f80142256e4df38585aa7d727/src/core/libraries/np/np_tus/np_tus.cpp), where they differ between functions: `arrayLen < 1` is `INSUFFICIENT_ARGUMENT` in the NpId and virtual-user delete calls and in `sceNpTusGetMultiSlotVariableVUserAsync`, and `INVALID_ARGUMENT` in the others; a null NpId is accepted except in delete; an empty virtual user ID is `INVALID_ARGUMENT`. RPCS3's [PS3 module](https://github.com/RPCS3/rpcs3/blob/1a9dca3a3a84a18df866e3021918322bd295160a/rpcs3/Emu/Cell/Modules/sceNpTus.cpp) has only the NpId and virtual-user calls; it returns `INVALID_ARGUMENT` for an empty array in all of them, rejects a null target in get and set and does not check for an empty virtual user ID.
- [Variable, data, data status and TSS requests](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - the argument checks of the 82 add-and-get, try-and-set, data, data status, multi-user, friends and `sceNpTssGetSmallStorage` calls are not measured on a console; their signatures, checks and order follow [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/a808e76/src/core/libraries/np/np_tus/np_tus.cpp), including its differences between forms: the NpId try-and-set calls return `INVALID_ARGUMENT` for an operation type outside 1-6 where the others return `INVALID_TYPE`, and the NpId and virtual-user multi-slot data status calls return `TOO_MANY_NPID` for more than 64 slots. As for the calls above, the output and structure sizes are not checked, and every request finishes with `SCE_NP_ERROR_SIGNED_OUT`
- [sceNpTusSetThreadParam](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTssCreateNpTitleCtx](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTssCreateNpTitleCtxA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusCreateTitleCtx](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusSetTimeout](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusChangeModeForOtherSaveDataOwners](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusDeleteMultiSlotDataVUser](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusDeleteMultiSlotDataVUserAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTssGetStorage](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTssGetStorageAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTssGetDataAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetDataForCrossSaveVUser](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetDataForCrossSaveVUserAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetMultiUserVariableForCrossSave](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsVariableA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsVariableAAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsVariableForCrossSave](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsVariableForCrossSaveAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsDataStatusA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsDataStatusAAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsDataStatusForCrossSave](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusGetFriendsDataStatusForCrossSaveAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - unknown signature
- [sceNpTusDeleteNpTitleCtx](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - the PS5 signature, error codes and child-request lifetime have not been measured on a console. Deletion invalidates the context and all its requests, following [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/a808e7626e3c7de8d0f0fda6a91f620b42f6c762/src/core/libraries/np/np_tus/np_tus.cpp#L158-L180).

### Functional

- [sceNpTusCreateNpTitleCtxA](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - creates a title context without checking sign-in, up to 32 contexts (`TOO_MANY_OBJECTS` beyond); shadPS4 returns the `sceNpGetNpId` error instead. Requests are limited to 256, and the limits are not measured on a console.
- [sceNpTusPollAsync, sceNpTusWaitAsync](../../../core/libs/prx/libSceNpTus/Export.cpp) (libSceNpTus) - there is no PSN, so every implemented `*Async` call whose arguments pass the checks starts a request that finishes at once with `SCE_NP_ERROR_SIGNED_OUT`, which poll and wait report and the blocking calls return; shadPS4 returns `SIGNED_OUT` from the `*Async` call itself when no shadNet client is signed in, and RPCS3 returns `INVALID_ONLINE_ID` while offline, marked there as probable behaviour. An abort stays set, so every later operation on the request, blocking ones included, finishes with `ABORTED`; in shadPS4 an abort only ends the operation in progress. Until an operation has started, poll returns 1 and wait returns `INVALID_ARGUMENT` as in shadPS4; RPCS3 [blocks until a result is set](https://github.com/RPCS3/rpcs3/blob/1a9dca3a3a84a18df866e3021918322bd295160a/rpcs3/Emu/NP/np_contexts.cpp#L40-L52).
