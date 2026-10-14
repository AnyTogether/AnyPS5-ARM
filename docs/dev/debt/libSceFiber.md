# libSceFiber technical debt

### Functional

- [sceFiberGetInfo](../../../core/libs/prx/libSceFiber/Export.cpp) reports the requested-size window at the top of the host stack used for execution, rather than the original caller buffer, which is retained and pinned. The additional 1 MiB host-call margin below that window is not included in `size_context`. Planet Coaster (PPSA01736 v01.017) uses this range for ChakraCore garbage-collector stack scans; reporting the unused caller buffer makes the scan cross unmapped memory. The range is covered by a regression test while running, switching and migrating a fiber between threads. Console behavior for substituted host stacks has no direct equivalent and is not measured.

### Unknown function info

- [_sceFiberGetThreadFramePointerAddress](../../../core/libs/prx/libSceFiber/Export.cpp) (libSceFiber, NID `0dy4JtMUcMQ`) forwards to `sceFiberGetThreadFramePointerAddress`; that the argument list matches is inferred from the export without the underscore, as for the underscore Ult exports, not measured
