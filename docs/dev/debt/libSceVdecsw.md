# libSceVdecsw technical debt

### Unknown function info

- [libSceVdecsw](../../../core/libs/prx/libSceVdecsw/Export.cpp) (libSceVdecsw) - structure layouts follow shadPS4's `vdecsw.h` and were checked against PPSA05684's movie decoder (`movie-decoder-vdecsw.cpp`), which asserts `pictureCount == 1` at offset 0xb of `OutputInfo` and reads `InputResult` offset 0x10 as the number of frames an access unit produced. The compute, decoder memory and decode input structures and the first 0x28 bytes of the 0x50-byte decoder config are those of libSceVideodec2, and decoding goes through it. The 0x78-byte AVC picture info is filled with Videodec2's leading fields and the cropping fields only. OUTPUT_PENDING (0x81510115), INPUT_QUEUE_EMPTY (0x81510116) and DECODE_PENDING (0x81510117) follow from the codes each call's assert accepts. At most four decoded pictures are queued and the last one is held until `sceVdecswFinalizeDecodeSequence`; the console's queue depth is unknown
