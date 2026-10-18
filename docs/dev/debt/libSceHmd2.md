# libSceHmd2 technical debt

### Silent stubs

- [libSceHmd2](../../../core/libs/prx/libSceHmd2/Export.cpp) reports a console without a PS VR2 headset, as firmware 13.20's libSceHmd2 does with the `/dev/hmd2_cmd` state measured on a retail PS5 with none connected (connected flag 0, status 2, user -1): initialization succeeds, `sceHmd2Open` returns a handle, device information reports `NotDetected` with the firmware's fixed panel, latency and image distance values, both field-of-view calls return the firmware's default tangents and `sceHmd2SetVibration` succeeds without vibrating. The reprojection and gaze exports and every [libSceVrTracker2](../../../core/libs/prx/libSceVrTracker2/Export.cpp) export throw. PPSA01317, PPSA07411, PPSA09030, PPSA15878 and PPSA29866, which skipped their VR set-up while initialization failed, have not been run with initialization succeeding

### Unknown function info

- PPSA29866 imports declared without parameters, signatures unknown, added without an implementation because the title fails to load without them: [sceHmd2ReprojectionQuerySeeThroughBufferSizeAlign](../../../core/libs/prx/libSceHmd2/Export.cpp) (libSceHmd2), [sceVideoOutSetFlipMaster and sceVideoOutClearFlipMaster](../../../core/libs/prx/libSceVideoOut/Unimplemented.cpp) (libSceVideoOut)
- PPSA09030 imports from its `Media/Plugins/psvr2.prx` declared without parameters, signatures unknown, added without an implementation because the title fails to load the plugin without them: [sceHmd2ReprojectionGetStatus](../../../core/libs/prx/libSceHmd2/Export.cpp) (libSceHmd2), [sceVrTracker2GetCoordinateSystem and sceVrTracker2GetPlayAreaBoundaryGeometry](../../../core/libs/prx/libSceVrTracker2/Export.cpp) (libSceVrTracker2)
- [sceHmd2Open](../../../core/libs/prx/libSceHmd2/Export.cpp) (libSceHmd2) - the handle is the value the console's driver returned to the first open; titles built with an SDK before 7.00 may open for any user, and the firmware's `sceMbusAddHandleByUserId` result for a user other than the initial one is unknown, so that case throws. 0x8a720006 for a second open is named `AlreadyOpened` from its use
- [sceHmd2SetVibration](../../../core/libs/prx/libSceHmd2/Export.cpp) (libSceHmd2) - the second parameter is checked against 25 only while a headset is connected; its name and unit are unknown. The field of view member names are assumed: of the firmware's default tangents the first is the widest and the last two are equal
- PPSA01317 imports declared without parameters, signatures unknown: the [libSceHmd2](../../../core/libs/prx/libSceHmd2/Export.cpp) exports that throw and the remaining [libSceVrTracker2](../../../core/libs/prx/libSceVrTracker2/Export.cpp) exports. Names from the aerolib NID list
- PPSA15878 imports declared without parameters, signatures unknown: the [libSceHmd2](../../../core/libs/prx/libSceHmd2/Export.cpp) reprojection and gaze exports, `sceVrTracker2Finalize`, `sceVrTracker2GetPlayAreaOrientedBoundingBox` and `sceVrTracker2LocateCoordinateSystem` in [libSceVrTracker2](../../../core/libs/prx/libSceVrTracker2/Export.cpp), and the `scePadVrController` trigger effect exports in [libScePad](../../../core/libs/prx/libScePad/Export.cpp). Names from the aerolib NID list

### Functional

- [sceHmd2Initialize](../../../core/libs/prx/libSceHmd2/Export.cpp) (libSceHmd2) - the firmware also fails with 0x8a72001f when `sceKernelGetAppInfo` fails and with 0x8a72000a for some applications, depending on app info fields at 0x2c, 0x4b and 0x4d whose meaning is unknown, and then calls `sceMbusInit`; none of this is modelled
