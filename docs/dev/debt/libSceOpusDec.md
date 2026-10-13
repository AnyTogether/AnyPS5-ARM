# libSceOpusDec technical debt

### Functional

- [libSceOpusDec](../../../core/libs/prx/libSceOpusDec/Export.cpp) uses FFmpeg for 48000 Hz mono/stereo signed-16 decoding. The six signatures, 640-byte opaque state allocation and byte-count return follow [public PS5 decoder research](https://github.com/blackbearreloaded/ps5-hardware-audio-decoding/blob/26be5a12f92b2cdc67f8a9e082fd69ae0e9a35a2/docs/DECODING.md#direct-opus-abi) and [ProsperoRadio](https://github.com/blackbearreloaded/ProsperoRadio/blob/2c4029c3a8f43e9e1dfef98374d94d99b14d745d/src/opus_decoder.cpp). Console PCM equivalence and error codes are unverified. Other sample rates, packet loss concealment, invalid inputs and termination with live decoders throw. Context identifiers and host decoder state are private registries; the firmware's opaque state layout and error recovery are unknown.
