# libSceJpegEnc technical debt

### Unimplemented functionality

- [sceJpegEncEncode](../../../core/libs/prx/libSceJpegEnc/Export.cpp) (libSceJpegEnc) - MJPEG mode throws; its encoding path is not implemented. Restart intervals are confirmed by the native validator, MCU counter and DRI writer: 0 disables restart markers, -1 selects one MCU row, and 1 through 65535 specify an MCU count. Other values return the invalid-parameter error.
