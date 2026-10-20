# libSceRegMgr technical debt

### Unknown function info

- [sceRegMgrNonSysGetInt](../../../core/libs/prx/libSceRegMgr/Export.cpp) (libSceRegMgr, NID `dKeshzt29G4`) - observed as an import needed for module loading (issue 4720); its `(int64_t key, int32_t unk, int32_t* data)` signature follows [ChonkyStation4](https://github.com/liuk7071/ChonkyStation4/blob/c101a23ecbc15e56c6e30d5dd24d3ed8880a957a/ChonkyStation4/OS/Libraries/SceRegMgr/SceRegMgr.cpp#L38-L47), not measured on a console, so every call throws
- [sceRegMgrGetBin and sceRegMgrSetBin](../../../core/libs/prx/libSceRegMgr/Export.cpp) (libSceRegMgr) - names and NIDs are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceRegMgr.c), but no credible prototypes were found. They are declared without parameters solely to resolve known imports; this is not an ABI claim. The string and integer prototypes follow [SharpProspero's SystemSettings bindings](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Platform/SystemSettings.cs)
