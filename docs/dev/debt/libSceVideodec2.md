# libSceVideodec2 technical debt

### Unknown function info

- [sceVideodec2GetAvcPictureInfo](../../../core/libs/prx/libSceVideodec2/Export.cpp) (libSceVideodec2) - runs the `sceVideodec2GetPictureInfo` body (KytyPS5 binds both NIDs to one function; SharpProspero gives both the same `outputInfo, first, second` signature); the second (bottom field) picture info is never written, since only progressive H.264 output is modelled. prosper calls the AVC layout unestablished (no title observed calling it)

### Functional

- [sceVideodec2CreateDecoder](../../../core/libs/prx/libSceVideodec2/Export.cpp) (libSceVideodec2) decodes HEVC (codec type 974921) and VP9 (2382845) through FFmpeg, besides H.264. The tags come from SharpProspero's `Videodec2CodecType` and EVO-PLAYER-PS5's `sce_videodec2.h`, which records them from hardware runs. HEVC input is converted from length-prefixed NAL units to Annex B as for H.264, and VP9 frames are passed through. Output is the same 8-bit NV12 for every codec; a decoder for HEVC Main10 or VP9 Profile 2 is created, but a frame deeper than 8 bits throws, since the console's 10-bit output layout is unknown, and `QueryDecoderMemoryInfo` reports the 8-bit frame size for it. `sceVideodec2GetPictureInfo` and `sceVideodec2GetAvcPictureInfo` throw for HEVC and VP9 pictures, which use other layouts (`SceVideodec2HevcPictureInfo`, `SceVideodec2Vp9PictureInfo`), and `sceVideodec2GetHevcPictureInfo` and `sceVideodec2GetVp9PictureInfo` are not exported
