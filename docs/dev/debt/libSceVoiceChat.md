# libSceVoiceChat technical debt

### Unknown function info

- [sceVoiceChatRequestCreateVoiceChatGroup, sceVoiceChatRequestJoinVoiceChatGroup, sceVoiceChatRequestLeaveVoiceChatGroup, sceVoiceChatRequestDeleteVoiceChatGroup](../../../core/libs/prx/libSceVoiceChat/Export.cpp) (libSceVoiceChat) - assumed to take a request id and two pointers like the other `sceVoiceChatRequest*` calls; offline, every argument is ignored and `SIGNED_OUT` is returned, as for those
