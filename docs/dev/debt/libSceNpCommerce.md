# libSceNpCommerce technical debt

### Silent stubs

- [libSceNpCommerce](../../../core/libs/prx/libSceNpCommerce/Export.cpp) - the PS Store icon show/hide calls and `sceNpCommerceSetPsStoreIconLayout` do nothing

### Unknown function info

- [sceNpCommerceDialogInitializeInternal](../../../core/libs/prx/libSceNpCommerce/Export.cpp) (libSceNpCommerce) - its name and NID are in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceNpCommerce.c); the no-parameter prototype follows [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/f68923fe807f657348e6719ce658bcbd0a2b1c72/src/core/libraries/np/np_commerce/np_commerce.cpp#L61) and is not measured on a console. It is declared without parameters solely to resolve known imports; this is not an ABI claim, and every call throws.
- [sceNpCommerceDialogOpen2](../../../core/libs/prx/libSceNpCommerce/Export.cpp) (libSceNpCommerce) - declared without parameters; follows [prosper](https://github.com/mattias800/prosper/blob/73413cb445b0364bb49c4d2478e9ee1614b9f7d9/prosper/src/hle/np/np.cpp#L500-L504), which serves it with its `sceNpCommerceDialogOpen` handler: every argument is ignored, nothing is validated, it returns 0 and the dialog finishes at once, so `sceNpCommerceDialogGetResult` reports it cancelled. The parameters and the console's error results are unknown. PPSA34501 calls it at Zombies > Online
