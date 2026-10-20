# libSceVrSetupDialog technical debt

### Silent stubs

- [libSceVrSetupDialog](../../../core/libs/prx/libSceVrSetupDialog/Export.cpp) - the VR setup dialog runs the common-dialog state machine but shows nothing and reports the user as having cancelled, as no headset is supported (see libSceHmd2). The signatures are assumed from the other common dialogs; PPSA12544 imports the library. `sceVrSetupDialogGetStatus` (NID `qRUACYyUNFA`) is present in the firmware export database (aerolib), but direct import by PPSA12544 has not been explicitly confirmed.
