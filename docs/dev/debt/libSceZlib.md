# libSceZlib technical debt

### Functional

- [libSceZlib](../../../core/libs/prx/libSceZlib/Export.cpp) decompresses synchronously and supports one outstanding request. Timed waits, multiple outstanding requests and repeated retrieval throw. Work-memory registration and driver-side destination alignment validation remain unsupported; non-null work memory and unaligned destinations throw. Native user-space validation confirms the 64-bit initialization length, 2 KiB output-length granularity up to 64 KiB, null-argument errors and initialization precedence. Finalization discards the host's completed result. Driver scheduling, completion consumption, cancellation, scratch-memory requirements and decompression error details remain unverified; host decoding maps malformed streams to 0x811200FF and exhausted output to 0x8112001C.
