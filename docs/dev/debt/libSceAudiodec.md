# libSceAudiodec technical debt

### Unknown function info

- [sceAudiodecDecode](../../../core/libs/prx/libSceAudiodec/src/Codecs.cpp) (libSceAudiodec) - a raw M4AAC stream carries no channel configuration, so the decoder tries the mono/stereo configuration and then configurations 3 to 7 within `ui_max_channels` until one decodes the first access unit, and keeps that one. No reference documents how the library picks the layout (shadPS4 maps the channel count straight to the configuration; SharpProspero only describes the maximum). With the stereo configuration a mono raw stream decodes as 2 channels, so 2 is reported, not 1

### Functional

- [libSceAudiodec](../../../core/libs/prx/libSceAudiodec/Export.cpp) throws for the 24-bit PCM word size (`iBwPcm` 0): its sample layout is unknown. ATRAC9 decoding is covered only by configuration and error tests, as no ATRAC9 encoder is available for a fixture.
