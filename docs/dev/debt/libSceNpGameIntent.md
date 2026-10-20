# libSceNpGameIntent technical debt

### Silent stubs

- [sceNpGameIntentVshInitialize, sceNpGameIntentVshTerminate](../../../core/libs/prx/libSceNpGameIntent/Export.cpp) (libSceNpGameIntent) - VSH initialization and termination return 0 without performing shell operations, matching `sceNpGameIntentInitialize` and `sceNpGameIntentTerminate`

### Unknown function info

- [sceNpAppLauncherInitialize, sceNpAppLauncherLaunchApp, sceNpAppLauncherTerminate, sceNpGameIntentGetUdsNpComId, sceNpGameIntentLaunchApp, sceNpGameIntentLaunchApp2, sceNpGameIntentNotifyAppLaunched, sceNpSessionServiceGetJoinedPartySession, sceNpSessionServiceGetRunningGamePlayerSession and sceNpSessionServiceSendPlayerSessionInvitations](../../../core/libs/prx/libSceNpGameIntent/Export.cpp) (libSceNpGameIntent) - names and NIDs are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceNpGameIntent.c), but no credible prototypes were found in the cited sources. They are declared without parameters solely to resolve known imports and make no ABI claim.
- [sceNpGameIntentInitParamInit](../../../core/libs/prx/libSceNpGameIntent/Export.cpp) (libSceNpGameIntent) - struct layout matches [fpPS4](https://github.com/red-prig/fpPS4/blob/master/src/np/ps4_libscenpgameintent.pas#L17) `SceNpGameIntentInitParam`; setting `size`, zeroing reserved bytes, and throwing on null pointer follow Sony SDK `*ParamInit` conventions but are unverified on retail hardware
- [sceNpGameIntentInfoInit](../../../core/libs/prx/libSceNpGameIntent/Export.cpp) (libSceNpGameIntent) - struct layout matches [fpPS4](https://github.com/red-prig/fpPS4/blob/master/src/np/ps4_libscenpgameintent.pas#L28) `SceNpGameIntentInfo`; setting `size`, `user_id = -1`, zeroing fields, and throwing on null pointer match `sceNpGameIntentReceiveIntent` defaults but are unverified on retail hardware
