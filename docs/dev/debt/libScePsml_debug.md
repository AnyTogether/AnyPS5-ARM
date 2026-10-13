# libScePsml_debug technical debt

### Unknown function info

- [scePsmlMfsr2CreateContext, scePsmlMfsr2CreateSharedResources, scePsmlMfsr2GetContextInitRequirement, scePsmlMfsr2GetDispatchPackets, scePsmlMfsr2GetDispatchPacketsSizeInDwords, scePsmlMfsr2GetSharedResourcesInitRequirement, scePsmlMfsr2Init, scePsmlMfsr2ReleaseContext, scePsmlMfsr2ReleaseSharedResources](../../../core/libs/prx/libScePsml_debug/Export.cpp) (libScePsml_mfsr2) - unknown signatures, imported by PPSA23566; declared without parameters
- [scePsmlMfsrGetContextBufferRequirement1100, scePsmlMfsrCreateContext1100, scePsmlMfsrGetDispatchMfsrPacket1100](../../../core/libs/prx/libScePsml_debug/Export.cpp) (libScePsml_debug) - argument layouts unknown; only 0x8A810001 (not initialized) is returned
- [scePsmlMfsrGetDispatchMfsrPacket1000](../../../core/libs/prx/libScePsml_debug/Export.cpp) (libScePsml) - unknown signature, imported by PPSA25344; declared without parameters. libScePsml and libScePsml_debug are built from the same source
- [scePsmlMfsrCreateContext1300, scePsmlMfsrGetDispatchMfsrPacket1300](../../../core/libs/prx/libScePsml_debug/Export.cpp) (libScePsml) - unknown signatures, imported by PPSA28416 next to `scePsmlMfsrGetContextBufferRequirement1100`; declared without parameters. The names are not in the aerolib NID list; they hash to the imported NIDs `kLF7WtQ1-Dg` and `DDVUyPyYHTA` (`tools/nid_names.py`)
- [NIDs `xNZM9Y5lf-M` and `lcZD9tJraAw`](../../../core/libs/prx/libScePsml_debug/Export.cpp) (libScePsml_specularAA and libScePsml_quality8K, exported as `scePsmlUnknown01` and `scePsmlUnknown02`) - imported by PPSA01317, which fails to load without them; names and signatures unknown (not in the aerolib NID list), so they throw
