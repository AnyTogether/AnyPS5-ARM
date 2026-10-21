# libSceVideodec technical debt

### Unknown function info

- [sceVideodecCreateDecoder, sceVideodecDecode, sceVideodecDeleteDecoder, sceVideodecFlush and sceVideodecReset](../../../core/libs/prx/libSceVideodec/Export.cpp) (libSceVideodec) - the structure layouts and the error codes follow [shadPS4's PS4 library](https://github.com/shadps4-emu/shadPS4/blob/main/src/core/libraries/videodec/videodec.h) and its [implementation](https://github.com/shadps4-emu/shadPS4/blob/main/src/core/libraries/videodec/videodec.cpp), not measured on a PS5: the console's error for a rejected argument and its own version of the structures are unknown. The decoder runs through libSceVideodec2, which decodes H.264 with FFmpeg, and the picture is copied into the caller's frame buffer with the pitch aligned to 64 and the coded height, as the reference writes it

- [libSceVideodec](../../../core/libs/prx/libSceVideodec/Export.cpp) (libSceVideodec) - the module's other two exports, `sceVideodecMapMemory` and `sceVideodecQueryResourceInfo`, are not provided, so a title that imports them fails to start

### Functional

- [sceVideodecCreateDecoder](../../../core/libs/prx/libSceVideodec/Export.cpp) (libSceVideodec) - the codec type is not checked and the decoder always decodes H.264, as the PS4 library does; the console's codec ids are not documented. A configuration without a maximum frame size is refused with the configuration error, and the resource information the caller passes is not used

- [sceVideodecDecode and sceVideodecFlush](../../../core/libs/prx/libSceVideodec/Export.cpp) (libSceVideodec) - the picture information's video usability information (the tick rate, the sample aspect ratio and the colour description) stays zero, as the decoder does not report it, and the crop offsets are the decoded picture's crop halved, the unit the H.264 offsets use. The frame buffer holds the coded picture the decoder reports, so the rows the crop covers are in it and the caller crops them

- [sceVideodecMapMemory and sceVideodecQueryResourceInfo](../../../core/libs/prx/libSceVideodec/Export.cpp) (libSceVideodec) - their names are listed in the PS5 3.20 export table and cross-checked against PS5 13.60. Their signatures and behaviour are unverified; these no-parameter declarations only resolve imports and throw through NotImplemented_nid_no_patch.
