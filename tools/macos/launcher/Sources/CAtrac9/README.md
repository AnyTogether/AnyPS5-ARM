LibAtrac9 (https://github.com/Thealexbarney/LibAtrac9, MIT, see LICENSE), the C decoder from
3rdparty/LibAtrac9 with the engine's three bounds and speed fixes from
core/libs/prx/libSceAjm.native/PatchLibAtrac9.cmake already applied to unpack.c, decinit.c and
bit_reader.c. The launcher uses it to play a game's theme song (sce_sys/snd0.at9).
