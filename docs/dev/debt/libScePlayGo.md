# libScePlayGo technical debt

### Unknown function info

- [libScePlayGo](../../../core/libs/prx/libScePlayGo/Export.cpp) - the chunk set comes from `playgo-chunkdefs.xml` (every listed chunk plus chunks 0 through the default chunk), otherwise from `sce_sys/playgo-chunk.dat`, whose `plgx` header is read as holding the chunk count as a 16-bit value at offset 0x0A and ids 0 to count - 1 are taken as valid. The field was identified on four dumps, where exactly that many 0x20-byte entries follow from offset 0x100 (RIDE 4 PPSA01599: 35, Persona 5 Royal PPSA05110: 25, LEGO Horizon Adventures PPSA14632 and Kena PPSA01802: 1); the rest of the format is not decoded and ids are assumed to be contiguous. Every listed chunk is reported as installed (`LOCAL_FAST`). Without either file every chunk id is accepted while `scePlayGoGetChunkId` lists only chunk 0; the console's answer for an id outside the package's chunk table is not checked.
