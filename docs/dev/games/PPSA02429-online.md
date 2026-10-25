# Human Fall Flat (PPSA02429): online play

Human Fall Flat 01.017.000, Unity 2019.4.14f1 (IL2CPP). It is the first title tested with Online play
(experimental) turned on. Findings from 2026-10-25: game logs, the online observation log, and the
imports of the installed bundle. Nobody ran the game for this page.

## Summary

- Online play in this game goes through **Photon** (Exit Games), a third-party service, not through
  the console network. The Public Games list, Host and Join all use Photon's servers over ordinary
  sockets. These are internet sockets, and the engine reaches the real internet through them already.
- Before the game goes online it checks the platform: signed in, Plus, the block list and the
  communication restriction status. The launcher now answers all four. It never contacts Sony.
- An engine bug broke the game's socket layer. libSceNet failed every `sceNetEpollControl` and
  `sceNetGetsockopt` call with EBADF on sockets made by POSIX `socket()`. That is fixed in
  c6d921416, so the next run should get further.

## What the logs showed

The game log is `~/Library/Logs/AnyPS5/PPSA02429.log`. The run that came before it is in
`PPSA02429.previous.log`.

- `error during sceNetEpollControl 0x80410109` and `error during sceNetEpollControl del 0x80410109`
  were printed 588,299 times each, starting right after boot, and filled 53 MB of log. These strings
  come from the game's own IL2CPP runtime (`Il2CppUserAssemblies.prx`), not from the engine. Its
  `Poll()` adds each socket to a per-thread `sceNetEpoll`, waits, then deletes it. The add failed, so
  the delete failed too.
- `sceNetGetsockopt failed with 0x80410109` appeared when Online was pressed. This is IL2CPP's
  set-blocking check: it calls `sceNetSetsockopt(fd, SOL_SOCKET, SO_NBIO, v)` and then
  `sceNetGetsockopt(fd, SOL_SOCKET, SO_NBIO)` to read the value back (call site
  `Il2CppUserAssemblies.prx+0x10f0c6e`). Because the read failed, the check reported failure, and the
  game's sockets were left in a mode it did not ask for.
- Root cause: IL2CPP creates its sockets with libkernel's `socket()`, then uses libSceNet calls on
  them. On the console both kinds are kernel descriptors in one namespace. libSceNet only knew the
  sockets made by `sceNetSocket`. `sceNetSetsockopt` already passed unknown descriptors on to
  libkernel; epoll, `sceNetGetsockopt` and `sceNetGetSockInfo` did not.
- The run where Join was pressed did not crash. Its log goes on past the last getsockopt errors: the
  level loads (`Workshop/Models`, `unity default resources`, textures) and runs at about 1.5 fps. It
  ends with the orderly shutdown line (`[gpu] host imports at shutdown`). The `[exception] guest
  context signal=0x1e` lines are Unity's garbage collector stopping its threads with the guest's
  SIGUSR1, which is normal. Since c5ab9e469 the log says how a game ended: `[exit] ...` for the
  title's exit or a closed window, and `[fatal] host signal ...` (address, instruction,
  image+offset) for a fault that no handler takes.
- The game reached the Public Games list (about 11 real lobbies) with no web API request for it. That
  is Photon.

## Which backend

From strings in `Media/Metadata/global-metadata.dat` and `Il2CppUserAssemblies.prx`:

- `(c) Exit Games GmbH`, `ns.exitgames.com` (Photon's name server), `AppIdRealtime`, `AppIdVoice`,
  `AppIdChat`, `FixedRegion`, `BestRegion`, `UseNameServer`. The app IDs are in the game's assets;
  they are the game's and are not copied here.
- `Media/Plugins/PhotonVoiceAudioOutputPlugin.prx` and `PhotonVoiceLocalUserIDPlugin.prx`, for Photon
  Voice.
- Localization keys `MULTIPLAYER/HOSTING`, `MULTIPLAYER/JOIN`, `MULTIPLAYER/LOBBY`,
  `MULTIPLAYER/SERVERFAILED` ("Failed to Start a Server"), `MULTIPLAYER/CONNECTIONFAILED`.

Photon Realtime puts players in rooms on Photon's game servers, and all game traffic is relayed
through those servers. Host creates a room and Join joins one. Neither needs peer-to-peer
connections, the platform's session signaling or Matching2. The game opens its connections with
IL2CPP's POSIX sockets: `socket`, `connect`, `send`/`recv`, `sendto`/`recvfrom`, and polling with
`sceNetEpoll*`. Names are resolved with `sceNetResolverStartNtoa`. The connections go out on the
Mac's own network, so AnyTogether's virtual network plays no part in them. Players on real consoles
and on AnyPS5 use the same rooms. That is why real players' lobbies appeared.

The console network still has a small part through the game's PSN plugin (`Media/Plugins/PSNCore.prx`
with `libSceNpCppWebApi.prx`):

| Request (observed) | What the launcher answers now |
|---|---|
| `sceNpGetState`, `sceNpGetNpReachabilityState` | signed in, reachable |
| `sceNpCheckPremium` (Plus) | authorized |
| `userProfile GET /v1/users/<me>/friends` | AnyTogether friends (`{"friends":[],"totalItemCount":0}` when there are none) |
| `userProfile GET /v1/users/me/blocks?offset=0&limit=0` | `{"blocks":[],"totalItemCount":0}` (496f10910; was 404) |
| `communicationRestrictionStatus GET /v3/users/<me>/communication/restriction/status` | `{"restricted":false}` (496f10910; was "not offered", 0x80553406) |
| Push event filter on `sessionManager` (17 filter parameters) | the filter is made with its data types (now in the log as `data_types`) |
| Host: push context (`CreatePushContext`) with a `sessionManager` filter of 20 data types | made locally (397786071 and earlier answered "not offered", `0x80553406`) |
| `sessionManager` Player Sessions (`/v1/playerSessions…`) | answered by the launcher, kept for the game run (see below) |

## Host Public: "Failed to Start a Server" (2026-10-25)

With the first nightly (v0.2.20-arm-nightly.20261025.1, main 397786071) and Online play on, Join
worked (a real public lobby, through Photon) and Host Public failed with "Failed to Start a Server".

What the observation log of that run showed (`~/Library/Logs/AnyPS5/Online/PPSA02429.jsonl`, the run
with build `397786071a5f`), three times, once per Host press:

```
sceNpWebApi2PushEventCreateHandle                      -> handle
sceNpWebApi2PushEventCreateFilter("sessionManager", 20 filter parameters)
sceNpWebApi2PushEventRegisterPushContextCallback       -> callback
sceNpWebApi2PushEventCreatePushContext(userContextId 2) -> 0x80553406
sceNpWebApi2PushEventUnregisterCallback(that callback)
sessionManager DELETE /v1/playerSessions/cb8a5af3-…/members/<own account> -> 0x80553406
```

Cause: the engine's `sceNpWebApi2PushEventCreatePushContext` always failed with "not offered", so
the game's PSN plugin stopped before it made its Player Session (no `POST /v1/playerSessions` ever
appears) and the game showed the server error. Photon itself reported nothing wrong. The `DELETE`
is the plugin leaving the last session it knew (from the lobby joined earlier), and it failed with
"not offered" too.

The first runs in the same log (build `6d9e9ff6b1ff`, release 0.2.19) show `communicationRestrictionStatus`
failing and the block list 404. That is not a start-up race: 0.2.19 was built before 496f10910,
which answers both. Every request of that kind in the nightly run got 200, the first one included.

What changed:

- **Engine (NpWebApi2):** push contexts are made locally (a version 4 UUID) while the launcher is
  there; `RegisterPushContextCallback`, `StartPushContextCallback`, `DeletePushContext`,
  `RegisterCallback` and both unregisters keep real state. Filters keep their service and data
  types. Push events from the launcher (a new bridge frame, `PushEvent`) go to the matching
  callbacks on the game's thread from `sceNpCheckCallback`. Offline, `CreatePushContext` still
  fails as before.
- **Launcher (`OnlinePlayerSessions`):** the `sessionManager` group answers Player Sessions in memory
  for the game run: create, get, patch, delete, join and leave members, leader, invitations,
  joinable specified users, session messages and the user's own sessions. Leaving a session the
  player is not in (the `DELETE` above) answers 204. Nothing goes to Sony or AnyTogether.
- **Observation log:** each push filter's data types (`data_types`), the push context made, every
  request body up to 64 KiB (the Player Session the game creates) and every push event delivered
  (`PushEventDelivered`).

The data types the game knows for Player Sessions (from its metadata):
`psn:sessionManager:playerSession:created`, `…:playerSession:deleted`, and under
`psn:sessionManager:ps:` `customData1:updated`, `customData2:updated`, `exclusiveLeaderPrivileges:updated`,
`invitableUserType:updated`, `invitations:created`, `joinDisabled:updated`, `joinableSpecifiedUsers:created`,
`joinableSpecifiedUsers:deleted`, `joinableUserType:updated`, `leader:updated`, `leaderPrivileges:updated`,
`localizedSessionNames:updated`, `m:p:customData1:updated`, `m:players:created`, `m:players:deleted`,
`m:players:swapped`, `m:s:customData1:updated`, `m:spectators:created`, `m:spectators:deleted`,
`m:spectators:swapped`, `maxPlayers:updated`, `maxSpectators:updated`, `sessionMessage:created`,
`swapSupported:updated`.

Not built: the Player Session is not mirrored to AnyTogether, so friends do not see a joinable
session from it. Players find the room through Photon's public list, as they did with Join.

Tests: `online_web_api2` (push contexts and delivery through the real exports and a fake launcher),
`online_bridge` ("push events", the frame byte for byte), `guest_np_web_api2` (offline answer),
`OnlinePlayerSessionsTests`, `OnlineBridgeTests.testWireMatchesTheEngineByteForByte` and
`OnlineEngineInteropTests.testAGameHostsAPlayerSessionWithAPushContext` (`online_probe host` plays this
flow through the real engine libraries against the launcher's service).

## Imports

From `relinker --registry` on the unwrapped eboot and every bundled module, classified with
`tools/import_audit.py` against this build's libraries: 2,433 references and 986 unique imports.
980 are implemented. 2 are stubs, `sceAgcUpdateInterpolantMapping_0100` and
`sceSystemServiceLoadExec`, and neither is on the network path. 4 are absent: they are imports from
`Il2CppUserAssemblies.prx` itself, which the game provides. No networking import is missing or stubbed.

| Library | Functions the game imports (module) | State |
|---|---|---|
| libSceNet | `sceNetSocket`, `Bind`, `Listen`, `Accept`, `Connect`, `Send`, `Sendto`, `Recv`, `Recvfrom`, `Getsockname`, `Htons`, `InetPton` (eboot); `sceNetEpollCreate`, `EpollControl`, `EpollWait`, `EpollDestroy`, `Getsockopt`, `Setsockopt`, `GetSockInfo`, `SocketClose`, `ResolverCreate`, `ResolverStartNtoa`, `ResolverStartAton`, `ResolverDestroy`, `PoolCreate`, `PoolDestroy`, `ErrnoLoc` (IL2CPP) | implemented; epoll, getsockopt and sock info fixed for `socket()` descriptors |
| libkernel sockets | `socket`, `bind`, `listen`, `accept`, `connect`, `send`, `sendto`, `sendmsg`, `recvfrom`, `recvmsg`, `getsockopt`, `setsockopt`, `getsockname`, `getpeername`, `shutdown`, `inet_pton` (IL2CPP) | implemented (native host sockets) |
| libSceNetCtl | `sceNetCtlGetInfo` | implemented |
| libSceNpManager | `sceNpGetState`, `GetAccountIdA`, `GetAccountCountryA`, `GetNpReachabilityState`, `HasSignedUp`, `CheckPremium`, `NotifyPremiumFeature`, `CreateRequest`, `CheckCallback`, `Register`/`Unregister` state, reachability and premium callbacks | implemented; answered by the launcher when Online play is on |
| libSceNpWebApi2 | `Initialize`, `Terminate`, `CreateUserContext`, `DeleteUserContext`, `CreateRequest`, `AddHttpRequestHeader`, `SendRequest`, `ReadData`, `AbortRequest`, `DeleteRequest`, `GetHttpResponseHeaderValue(Length)`, `PushEventCreateHandle`, `CreateFilter`, `RegisterCallback`, `CreatePushContext`, `RegisterPushContextCallback`, `StartPushContextCallback`, and the matching deletes | implemented; requests go to the launcher, never to Sony |
| libSceNpAuth | `CreateAsyncRequest`, `GetAuthorizationCodeV3`, `GetIdTokenV3`, `WaitAsync`, `DeleteRequest` | implemented |
| libSceNpGameIntent, libSceNpEntitlementAccess, libSceNpCommerce | initialize, receive intent, add-on list, commerce dialog | implemented |
| libSceHttp2, libSceHttp, libSceSsl | HTTP/2 client and TLS (Photon's web parts, the plugin) | implemented |
| libSceNpSessionSignaling, libSceNpMatching2, libSceNpSignaling, libSceRudp | not imported | none needed |

## What to try next

1. Update to the nightly after 2026-10-25 that carries the Player Sessions (or build main), then
   reinstall or re-convert the game so its bundle gets the new libraries.
2. Settings → AnyTogether → Online play (experimental) on, signed in.
3. Start the game, Online, Host Public.
4. If it still fails, send `~/Library/Logs/AnyPS5/Online/PPSA02429.jsonl` and
   `~/Library/Logs/AnyPS5/PPSA02429.log`. The jsonl now shows the push filter's data types, the
   push context, the `POST /v1/playerSessions` body and every answer.

Open: whether the game wants push events after it creates its session (none are sent for its own
changes), and why the joined level ran at about 1.5 fps.
