# libSceJpegEnc technical debt

### Unknown function info

- [sceJpegEncEncode](../../../core/libs/prx/libSceJpegEnc/Export.cpp) (libSceJpegEnc) - `restart_interval` follows SharpProspero's field doc (0 none, -1 every row of blocks, positive a block count); a positive value is taken as the JPEG DRI interval in MCUs and -1 as one restart per MCU row, which no reference confirms. Other negative values throw
