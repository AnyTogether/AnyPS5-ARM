# libSceRazorCpu technical debt

### Silent stubs

- [sceRazorCpuPushMarker](../../../core/libs/prx/libSceRazorCpu/Export.cpp) (libSceRazorCpu) - signature (label, color, flags) from [SharpProspero](https://github.com/SvenGDK/SharpProspero), the same as sceRazorCpuPushMarkerStatic's except that the label is copied; it does nothing without a capture and returns 0
- [sceRazorCpuSync](../../../core/libs/prx/libSceRazorCpu/Export.cpp) (libSceRazorCpu) - the `int(void)` signature and its meaning, an unnamed frame-boundary event, come from [SharpProspero](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Interop/Debug/RazorCpu.cs#L119-L122). Without a capture there is no event to record, so it does nothing and returns 0, like the other `sceRazorCpu*` markers here and the [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/3a9f57265d28975658f1ca941daa5c879c7a74bd/src/core/libraries/razor_cpu/razor_cpu.cpp#L143-L146) stub. PRAGMATA (PPSA02530) continues on 0; the console's result with no capture attached is unverified

### Unknown function info

- [sceRazorCpuFlushOccurred](../../../core/libs/prx/libSceRazorCpu/Export.cpp) (libSceRazorCpu) - signature and return values (1 = flush since the last call, 0 = none) from [SharpProspero](https://github.com/SvenGDK/SharpProspero); without a capture nothing is flushed, so it returns 0 and writes 0 cycles to the optional out pointer (whether the real library writes it when nothing was flushed is unknown)
- [sceRazorCpuPushMarkerStatic, sceRazorCpuPopMarker](../../../core/libs/prx/libSceRazorCpu/Export.cpp) (libSceRazorCpu) - signatures from PPSA26344's calls; (name, color, flags) assumed for the push; both do nothing without a capture
- [sceRazorCpuPlotValue, sceRazorCpuWriteBookmark](../../../core/libs/prx/libSceRazorCpu/Export.cpp) (libSceRazorCpu) - signatures (series, float value) and (label, optional description) from [SharpProspero](https://github.com/SvenGDK/SharpProspero), matching PPSA06320's calls; both do nothing without a capture and return 0
