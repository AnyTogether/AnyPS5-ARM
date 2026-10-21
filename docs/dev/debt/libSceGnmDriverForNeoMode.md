# libSceGnmDriverForNeoMode technical debt

### Unknown function info

- [libSceGnmDriverForNeoMode pending exports](../../../core/libs/prx/libSceGnmDriverForNeoMode/Export.cpp) - 118 named callable exports are listed in the [PS5 3.20 export table](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceGnmDriverForNeoMode.c) and were cross-checked against the same module in PS5 firmware 13.60. Their signatures and behaviour are unverified; the declarations use the no-parameter unknown-signature convention and throw through `NotImplemented_nid_no_patch`.

- [libSceGnmDriverForNeoMode pending exports](../../../core/libs/prx/libSceGnmDriverForNeoMode/Export.cpp) - 45 named callable exports were identified in the PS5 3.20 export table and cross-checked against firmware 13.60. Signatures and behavior remain unverified; declarations use the unknown-signature convention and throw through `NotImplemented_nid_no_patch`. Evidence: [3.20 export list](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceGnmDriverForNeoMode.c).
