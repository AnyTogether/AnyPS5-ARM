# libSceNpParty technical debt

### Unknown function info

- [sceNpPartyGetState](../../../core/libs/prx/libSceNpParty/Export.cpp) (libSceNpParty) - the 16-bit state, its `NOT_IN_PARTY` value 2 and the `INVALID_ARGUMENT` (`0x80552504`) error follow shadPS4's [np_party.h](https://github.com/shadps4-emu/shadPS4/blob/a808e76/src/core/libraries/np/np_party.h) and [np_error.h](https://github.com/shadps4-emu/shadPS4/blob/a808e76/src/core/libraries/np/np_error.h) (PS4); shadPS4 does not check for a null state, and whether the console needs an initialized party library first is not known. Not measured on a PS5
