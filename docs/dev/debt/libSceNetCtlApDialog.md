# libSceNetCtlApDialog technical debt

### Silent stubs

- [libSceNetCtlApDialog](../../../core/libs/prx/libSceNetCtlApDialog/Export.cpp) - the access-point dialog runs the common-dialog state machine but shows nothing and reports the user as having cancelled, as no access-point connection is brought up. `Open` takes the 104-byte parameter block and `GetResult` writes a 40-byte result (int32 result and 36 zeroed reserved bytes), following [SharpProspero](https://github.com/SvenGDK/SharpProspero/blob/60977b29103452b9681ae10c7a9011d44965bf16/src/SharpProspero/Interop/Net/NetCtlApDialog.cs); the parameter block is not validated and the 0x80B8xxxx error codes follow the other common dialogs, neither verified on hardware. Deathloop imports it
