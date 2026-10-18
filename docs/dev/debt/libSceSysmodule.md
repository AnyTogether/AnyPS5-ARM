# libSceSysmodule technical debt

### Silent stubs

- [sceSysmoduleIsLoaded, sceSysmoduleLoadModule, sceSysmoduleUnloadModule](../../../core/libs/prx/libSceSysmodule/Export.cpp) (libSceSysmodule) accept a module id missing from the module table: they log it and return 0 without loading anything, so `sceSysmoduleIsLoaded` reports an unknown module as loaded and unloading it succeeds, because titles that load or unload such an id aborted otherwise. The internal variants (`sceSysmoduleLoadModuleInternal`, `sceSysmoduleUnloadModuleInternal`, `sceSysmoduleLoadModuleInternalWithArg`, `sceSysmoduleGetModuleHandleInternal`) throw for an unknown id. What the console returns for an id it does not know is not verified.

### Functional

- [sceSysmoduleGetModuleInfoForUnwind](../../../core/libs/prx/libSceSysmodule/Export.cpp) (libSceSysmodule) - on Windows the region and file name of an address inside a loaded image are cached after the first lookup, because `VirtualQuery` on a large image section is slow. An entry is used only while the loader still reports the same image for the address (same base, time stamp and size). A page protection change inside the image after the first lookup, which would split or merge the region `VirtualQuery` reports, is not noticed. Addresses outside loaded images are queried every time
