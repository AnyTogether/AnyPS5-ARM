# libSceMbus technical debt

### Silent stubs

- [libSceMbus](../../../core/libs/prx/libSceMbus/Export.cpp) implements only the no-device path: initialization and termination succeed, no device events are reported and device queries return no entries

### Unknown function info

- [libSceMbus](../../../core/libs/prx/libSceMbus/Export.cpp) (`libSceDeviceService`) - signatures taken from PPSA01317, which calls `sceDeviceServiceInitialize(3, 0)`, polls `sceDeviceServiceGetEventState(1)` and queries again when bit 0 or 1 is set, and calls `sceDeviceServiceQueryDeviceInfo_(0x7001, 0, 0, infos, 1, &count, &unknown, 0x70)`, treating a negative result as an error and `count` as the number of entries. The host has no devices: the event state is 0 and a query returns 0 with `count` 0
