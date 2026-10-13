# libScePngEnc technical debt

### Unknown function info

- [scePngEncEncode](../../../core/libs/prx/libScePngEnc/Export.cpp) (libScePngEnc) - whether rows may stay unfiltered when `filter_type` names a subset of the filters is unknown; as in shadPS4, they may only for 0 and for the all-filters mask
