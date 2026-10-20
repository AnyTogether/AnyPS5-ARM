# libSceGameUpdate technical debt

### Unknown function info

- [sceGameUpdateGetAddcontLatestVersion](../../../core/libs/prx/libSceGameUpdate/Export.cpp) (libSceGameUpdate) - a null `entitlement_label` returns `0x80412803` as in prosper; KytyPS5 accepts it instead, and neither is confirmed on a console. Bytes after `found` are zeroed as in KytyPS5; prosper leaves them untouched
- [sceGameUpdateCreateRequest, sceGameUpdateCheck, sceGameUpdateAbortRequest, sceGameUpdateDeleteRequest](../../../core/libs/prx/libSceGameUpdate/Export.cpp) (libSceGameUpdate) - an initialized `sceGameUpdateCreateRequest` returns `0x80D50001` and creates no request, so `sceGameUpdateCheck`, `sceGameUpdateAbortRequest` and `sceGameUpdateDeleteRequest` answer `0x80412805` for every id that passes their argument checks. The PS5 3.20 module, as read by prosper, keeps 8 requests with ids from `0x20000000`, and answers "no update" when its patch-check service reports `0x80412883`; what that service returns on an offline console is unknown. Closes when: measured on a PS5
