# libSceConvertKeycode technical debt

### Functional

- [sceConvertKeycodeGetVirtualKeycode](../../../core/libs/prx/libSceConvertKeycode/Export.cpp) and `sceConvertKeycodeGetCharacter`: layouts 31–39 throw until the guest platform and compiled SDK version are exposed. `GetVirtualKeycode` also throws for version-dependent Y/Z mappings in layouts 2, 3 and 12. Mapping tables and modifier behavior are recovered; no SDK version is guessed.
- [sceConvertKeycodeGetImeKeyboardType](../../../core/libs/prx/libSceConvertKeycode/Export.cpp): user keyboard language and Japanese/Chinese keyboard variants are not exposed by the current UserService implementation. Valid-user queries throw instead of returning a fabricated keyboard type. The confirmed language/variant mapping and SDK compatibility rules still need integration with those settings.
