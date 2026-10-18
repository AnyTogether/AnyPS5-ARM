# libSceCdlgG2P technical debt

### Silent stubs

- [libSceCdlgG2P](../../../core/libs/prx/libSceCdlgG2P/Export.cpp) - the G2P dialog runs the common-dialog state machine but shows nothing and reports the user as having cancelled. The signatures (`Open` and `GetResult` take a pointer, the others none) and the leading `int32` result are assumed from the other common dialogs, not verified for G2P; PPSA01289 imports it
