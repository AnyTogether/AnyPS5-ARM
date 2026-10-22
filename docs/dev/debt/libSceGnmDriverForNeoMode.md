# libSceGnmDriverForNeoMode technical debt

### Unknown function info

- [libSceGnmDriverForNeoMode pending exports](../../../core/libs/prx/libSceGnmDriverForNeoMode/Export.cpp) - 70 named callable exports are listed in the [PS5 3.20 export table](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceGnmDriverForNeoMode.c) and were cross-checked against the same module in PS5 firmware 13.60. Their signatures and behaviour are unverified; the declarations use the no-parameter unknown-signature convention and throw through `NotImplemented_nid_no_patch`.

### Functional

- [retail-only answers](../../../core/libs/prx/libSceGnmDriverForNeoMode/Export.cpp) (libSceGnmDriverForNeoMode) - the debug resets, the resource and owner registration calls, the SDMA calls and the SQ counter calls return `0x8EEE00FF`, the five `sceGnmDriverInternalRetrieveGnmInterface*` calls return `0x80000000`, `sceGnmGetDbgGcHandle` returns -1, `sceGnmDriverTraceInProgress` and `sceGnmValidateOnSubmitEnabled` return 0 and the other validation calls return `0x80D13FFF`. These are the values [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/a808e76/src/core/libraries/gnmdriver/gnmdriver.cpp) returns for calls it marks as not available in retail firmware; they are not measured on a console, and the arguments are not read
