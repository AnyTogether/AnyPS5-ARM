# libSceGameLiveStreaming technical debt

### Unknown function info

- [sceGameLiveStreamingEnableLiveStreaming](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - imported by PS4 titles, which do not load without it, and added without an implementation: declared without parameters, every call throws
- [sceGameLiveStreamingGetCurrentStatus2](../../../core/libs/prx/libSceGameLiveStreaming/Export.cpp) (libSceGameLiveStreaming) - the status layout (user id, on-air flag, spectator, text and command message counts, broadcast resolution, 48 reserved bytes) is taken from shadPS4's `OrbisGameLiveStreamingStatus2`; the call reports that no stream is on air, with an invalid user id
