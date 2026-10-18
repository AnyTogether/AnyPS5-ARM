# libSceNpCommerce technical debt

### Silent stubs

- [libSceNpCommerce](../../../core/libs/prx/libSceNpCommerce/Export.cpp) - the PS Store icon show/hide calls and `sceNpCommerceSetPsStoreIconLayout` do nothing

### Unknown function info

- [sceNpCommerceDialogOpen2](../../../core/libs/prx/libSceNpCommerce/Export.cpp) (libSceNpCommerce) - declared without parameters; follows [prosper](https://github.com/mattias800/prosper/blob/73413cb445b0364bb49c4d2478e9ee1614b9f7d9/prosper/src/hle/np/np.cpp#L500-L504), which serves it with its `sceNpCommerceDialogOpen` handler: every argument is ignored, nothing is validated, it returns 0 and the dialog finishes at once, so `sceNpCommerceDialogGetResult` reports it cancelled. The parameters and the console's error results are unknown. Call of Duty: Black Ops (PPSA34501) calls it at Zombies > Online
