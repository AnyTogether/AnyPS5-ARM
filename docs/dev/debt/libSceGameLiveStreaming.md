# libSceGameLiveStreaming technical debt

### Functional

- [sceGameLiveStreamingEnableLiveStreaming](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - imported by PS4 titles, which do not load without it, and added without an implementation: declared without parameters, every call throws
- [libSceGameLiveStreaming](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) - native initialization requires exactly 0x4000 heap bytes before checking repeated initialization. Host lifecycle and pointer errors now match the wrapper, but service registration, allocation failures and asynchronous service readiness are not modelled. The host becomes ready immediately after initialization.
- [sceGameLiveStreamingGetCurrentStatus2](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) - the supplied module confirms the 72-byte layout and inactive status (user -1, remaining bytes zero). Live service counters, active-user changes and broadcast-resolution conversion are unimplemented.
- [sceGameLiveStreamingGetProgramInfo](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) - consumes one output pointer and uses a 4940-byte record. Field semantics remain unresolved; the protected body remains unimplemented.

### Unknown function info

- [sceGameLiveStreamingScreenInitialize](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenInitializeSeparateModeParameter](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenTerminate](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenCloseSeparateMode](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenConfigureSeparateMode](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenOpenSeparateMode](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingScreenSetMode](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingPermitLiveStreaming](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetMaxBitrate](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingGetCurrentStatus](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingEnableSocialFeedback](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingGetSocialFeedbackMessagesCount](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingGetSocialFeedbackMessages](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingPermitServerSideRecording](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetMetadata](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetSpoilerTag](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingClearSpoilerTag](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetPresetSocialFeedbackCommands](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingClearPresetSocialFeedbackCommands](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetPresetSocialFeedbackCommandsDescription](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingClearSocialFeedbackMessages](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingPostSocialMessage](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetCameraFrameSetting](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetServiceProviderPermission](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetDefaultServiceProviderPermission](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetInvitationSessionId](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStartGenerateStandbyScreenResource](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStopGenerateStandbyScreenResource](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingRegisterCallback](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingUnregisterCallback](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingCheckCallback](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetStandbyScreenResource](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingGetCurrentBroadcastScreenLayout](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingLaunchLiveViewer](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingLaunchLiveViewerA](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetGuardAreas](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStartSocialFeedbackMessageFiltering](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStopSocialFeedbackMessageFiltering](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingApplySocialFeedbackMessageFilter](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingSetLinkCommentPreset](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStartDebugBroadcast](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
- [sceGameLiveStreamingStopDebugBroadcast](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - unknown signature
