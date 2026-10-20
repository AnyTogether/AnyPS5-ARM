# libSceLoginDialog technical debt

### Silent stubs

- [libSceLoginDialog](../../../core/libs/prx/libSceLoginDialog/Export.cpp) - the login dialog runs the common-dialog state machine but shows nothing and reports the user as having cancelled
- [sceLoginDialogClose](../../../core/libs/prx/libSceLoginDialog/Export.cpp) - sceLoginDialogClose transitions an initialized dialog directly to COMMON_DIALOG_STATUS_FINISHED even when called before Open, following the Signin / NetCtlAp / PlayerSelection convention; this behavior is unverified against real hardware.

### Unknown function info

- [sceLoginDialogOpen, sceLoginDialogGetResult](../../../core/libs/prx/libSceLoginDialog/Export.cpp) - the 0x8134xxxx codes, the Open param checks (size 0x40, word 1 below 2, words 0x2C to 0x3C zero) and the `{1, 0x81340007}` result words are the ones [prosper](https://github.com/mattias800/prosper/blob/ed42e499888d5a86792c3e1b2df3aebd8ca1a681/prosper/src/hle/service/hle_service.cpp#L805-L874) reads from the shipped module. The order of the param and state checks follows prosper's handlers and is not stated separately, the meaning of word 1 and of the second result word is unknown, words 2 to 10 are not checked, and Open's busy result is never reached because the dialog never runs. Closes when: the module's check order is read or measured on a PS5
