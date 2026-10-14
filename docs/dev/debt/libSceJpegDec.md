# libSceJpegDec technical debt

### Unknown function info

- [libSceJpegDec](../../../core/libs/prx/libSceJpegDec/Export.cpp) (libSceJpegDec) - structure layouts follow [OpenOrbis `jpeg.h`](https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain/blob/0a1aaf9dd4a92695538bdeb09fb056d06dd11725/include/orbis/_types/jpeg.h#L13-L72) and [SharpProspero `JpegDec.cs`](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Interop/Image/JpegDec.cs#L20-L117); attributes 1 and 2 are the values [SharpProspero's `JpegImage.cs`](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Graphics/JpegImage.cs#L64-L74) passes. The error codes are libScePngDec's: no reference lists the JpegDec ones, and SharpProspero raises 0x80650020 on its JpegDec path where it raises libScePngDec's 0x80690020 on its PngDec path. Image info always reports color space 3, suitable CSC attribute 1 and zero component ids and sampling factors; the console's values, including which images it reports attribute 2 for, are unknown. The coefficient memory size is 0 because the host decoder needs no coefficient buffer; the size the console reports for progressive images is unknown. `max_image_width` is not checked, and the packed `width << 16 | height` decode result is libScePngDec's

### Functional

- [libSceJpegDec](../../../core/libs/prx/libSceJpegDec/Export.cpp) (libSceJpegDec) - decode modes other than 0 and down scales other than 1 throw
