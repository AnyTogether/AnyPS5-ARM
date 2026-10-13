# ulobjmgr technical debt

### Silent stubs

- [ulobjmgr](../../../core/libs/prx/ulobjmgr/Export.cpp) registers no object: `_sceUlobjmgrRegisterObject` always hands out id 0 and `_sceUlobjmgrUnregisterObject` releases nothing, as shadPS4 does

### Unknown function info

- [_sceUlobjmgrRegisterObject](../../../core/libs/prx/ulobjmgr/Export.cpp) (ulobjmgr) - parameters taken from shadPS4 (PS4): a nonzero 64-bit object, a nonzero 32-bit kind and a 32-bit id output; the meaning of the first two and the PS5 signature are unverified. The id bound of `_sceUlobjmgrUnregisterObject` (below 0x4000) and the raw `EINVAL` (22) return also come from shadPS4
