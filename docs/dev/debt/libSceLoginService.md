# libSceLoginService technical debt

### Silent stubs

- [sceLoginServiceInitialize, sceLoginServiceTerminate](../../../core/libs/prx/libSceLoginService/Export.cpp) (libSceLoginService) - return success and keep no login-service state: AnyPS5 has no PSN login service. EA SPORTS FC 27 (PPSA34015) loads the module with `sceSysmoduleLoadModule(0xe3)` and calls `sceLoginServiceInitialize` with no arguments; a missing `libSceLoginService.prx` stops Windows start-up with `Failed to load module` / `GetLastError: 126`

### Unknown function info

- [sceLoginServiceRequestDevices](../../../core/libs/prx/libSceLoginService/Export.cpp) (libSceLoginService) - PPSA34015 passes one pointer to a stack buffer (`lea rdi, [rbp-0x80]`) then calls `sceLoginServiceTerminate`. The buffer layout, other arguments and console errors are unknown, so every call throws without reading or writing caller memory
