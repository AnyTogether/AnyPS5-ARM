# libSceNetCtl technical debt

### Silent stubs

- [sceNetCtlGetNatInfo](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - `sceNetCtlGetNatInfo` validates null pointers and returns `SCE_NET_CTL_ERROR_NOT_CONNECTED` (`0x80412108`) without performing NAT discovery.

### Unknown function info

- [sceNetCtlGetInfoV6](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl, NID `Jy1EO5GdlcM`) - imported by PPSA08587. `(int code, SceNetCtlInfoV6* info)` with codes 1-5 (IP address, link-local address, default route, primary and secondary DNS) comes only from [SharpProspero](https://github.com/SvenGDK/SharpProspero), whose source is unknown; shadPS4 and fpPS4 only stub it. A null `info` answers `INVALID_ADDR`, a code outside 1-5 `INVALID_CODE`, and a host without an IPv6 address `NOT_CONNECTED`, as `sceNetCtlGetStateV6` reports it. The layout of each answer is unverified, so every code throws on a host with an IPv6 address
- [sceNetCtlGetInfo](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - answers from the host interface that holds an IPv4 address, preferring the one that carries the default route: its address, netmask, gateway, MTU and first two IPv4 DNS servers. The device is reported as wired, the link as connected, the IP configuration as DHCP and the HTTP proxy as off, whatever the host uses, and the Ethernet address is the one `sceNetGetMacAddress` reports. A gateway or DNS server the interface does not have is reported as `0.0.0.0`; what a console reports then is unknown. The DHCP host name (12), the PPPoE user name (13), the HTTP proxy server (20) and the Wi-Fi BSSID and SSID (5, 6) are empty strings, as that configuration sets none of them; the remaining Wi-Fi codes (7-10) and the HTTP proxy port (21) report 0; this follows [KytyPS5](https://github.com/KytyPS5/KytyPS5/blob/main/src/libs/network.cpp) and is not measured on hardware
- [sceNetCtlRegisterCallbackForNpToolkit](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlRegisterCallbackIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlRegisterCallbackForLibIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlUnregisterCallbackForNpToolkit](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlUnregisterCallbackIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlUnregisterCallbackForLibIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlCheckCallbackForNpToolkit](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlCheckCallbackForLibIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlClearEventIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlClearEventForNpToolkit](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlClearEventForLibIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetResultIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetStateIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetState2IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetEtherLinkMode](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetWifiType](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlConnectIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlConnectWithRetryIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlConnectConfIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlDisconnectIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlScanIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetScanInfoBssidIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetScanInfoByBssidIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetScanInfoForSsidScanIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetScanInfoBssidForSsidListScanIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetScanInfoForSsidListScanIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlSetErrorNotificationEnabledIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlRegisterCallbackV6IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlUnregisterCallbackV6IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetResultV6](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl, NID `H5yARg37U5g`) - `(int eventType, int* errorCode)` comes only from [SharpProspero](https://github.com/SvenGDK/SharpProspero/blob/5dfdb4b0b166e83dc9ae275001afb695f12c7174/src/SharpProspero/Interop/Net/NetCtl.cs#L246-L251), whose source is unknown; shadPS4 only stubs it. Callbacks registered with `sceNetCtlRegisterCallbackV6` receive no event, so event types 1-3 write 0 to `errorCode`; what a console writes before the first event is unmeasured. A null `errorCode` answers `INVALID_ADDR`, as `sceNetCtlGetResult` does, and other event types throw, as their error code on a console is unknown
- [sceNetCtlGetResultV6IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetStateV6IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetInfoV6IpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetNatInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlSetStunWithPaddingFlagIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlUnsetStunWithPaddingFlagIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlIsBandwidthManagementEnabledIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlDisableBandwidthManagementIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlEnableBandwidthManagementIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetBandwidthInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetNetEvConfigInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetConnectionElapsedTimeIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpCheckCallback](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpClearEvent](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpRegisterCallback](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpUnregisterCallback](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpGetResult](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpGetState](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpGetInfo](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpStart](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApCpStart](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApAppStartWithRetryPid](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApAppStartWithRetry](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpStartWithRetry](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpStartConf](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRpStop](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApCpStop](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApAppInitWpaKey](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApAppInitWpaKeyForQa](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlApRestart](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweCheckCallbackIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweClearEventIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweRegisterCallbackIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweUnregisterCallbackIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweGetInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweStartInternetConnectionTestIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweFinishInternetConnectionTestIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweStartInternetConnectionTestBandwidthTestIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetBweSetInternetConnectionTestResultIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature
- [sceNetCtlGetWifiInfoIpcInt](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - unknown signature

### Functional

- [sceNetCtlCheckCallback](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) - the state comes from the host interfaces, as in `sceNetCtlGetState`: `IPOBTAINED` (3) while the host has a non-loopback IPv4 or IPv6 address, `DISCONNECTED` (1) otherwise; the event values follow [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/15abf68c9b52c4b04d094f2837719fdb871021f3/src/core/libraries/network/net_ctl_codes.h#L27-L29), and no other event is delivered. Each callback registered with `sceNetCtlRegisterCallback` is called on the checking thread with its registration argument when the state differs from the last one it received, so a new registration receives the current state at the next check. This edge-triggered model follows [KytyPS5](https://github.com/KytyPS5/KytyPS5/blob/9e41d8320a2774b303fbad344c2347e8d0292e83/src/libs/network.cpp#L3648-L3661); [shadPS4](https://github.com/shadps4-emu/shadPS4/blob/15abf68c9b52c4b04d094f2837719fdb871021f3/src/core/libraries/network/net_ctl_obj.cpp#L47-L57) delivers the state on every check instead, and neither is measured on hardware. KytyPS5 calls the callbacks under its lock; here they are called after the lock is released, from a copy of their slots, so a `sceNetCtlUnregisterCallback` or `sceNetCtlTerm` on another thread that returns while a check is in flight does not stop that check from calling the callback once more with its old argument. Callbacks registered with `sceNetCtlRegisterCallbackV6` keep their argument but receive no event, because no source says which call delivers them
- [sceNetCtlGetInfo](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) finds the host's default route in `/proc/net/route` on Linux and, on macOS, in the routing table read with `sysctl(NET_RT_FLAGS, RTF_GATEWAY)`, where an interface-scoped default route ranks after the unscoped one
- [sceNetCtlGetIfStat](../../../core/libs/prx/libSceNetCtl/Export.cpp) (libSceNetCtl) throws on macOS: an unprivileged process reads the interface byte counters (`getifaddrs` and `sysctl(NET_RT_IFLIST2)` alike) reduced to their low 32 bits, so a total would wrap every 4 GiB
