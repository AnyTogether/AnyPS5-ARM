# libScePngDec technical debt

### Unknown function info

- [scePngDecQueryMemorySize, scePngDecCreate](../../../core/libs/prx/libScePngDec/Export.cpp) (libScePngDec) - the work memory is a fixed 0x20 bytes, because decoding uses host memory; the PS5 module asks for `((max_image_width + 0x47) & ~7) * (8 << attribute)` plus a constant, as read from the 3.20 module by prosper. A null parameter returns `0x80690003`; prosper returns `0x80690001` when it cannot read the parameter, which was not measured. Closes when: measured on a PS5
- [scePngDecDecodeWithInputControl](../../../core/libs/prx/libScePngDec/Export.cpp) (libScePngDec) - its name and NID are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libScePngDec.c); the no-parameter prototype follows [shadPS4's pngdec.h](https://github.com/shadps4-emu/shadPS4/blob/f68923fe807f657348e6719ce658bcbd0a2b1c72/src/core/libraries/libpng/pngdec.h#L76) and is not measured on a console. It is declared without parameters solely to resolve known imports; this is not an ABI claim.
