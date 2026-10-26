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

## Host Public: crash after the Player Session is made (2026-10-26)

With 0.2.21-arm and Online play on, Host Public got further: the push context was made,
`POST /v1/playerSessions` was sent with the push context in it and the launcher answered 200 with
165 bytes. Then the game died at once:

```
[fatal] host signal 11 (SIGSEGV) that no handler takes ends the game: address 0x10,
instruction 0x14d3ff1c4 (libSceNpCppWebApi.prx.guest.prx+0x1d81c4)
```

No `ReadData` followed the send in the observation log.

`libSceNpCppWebApi.prx` is the game's own module (`app0/sce_module`), relinked at start into
`libSceNpCppWebApi.prx.guest.prx` next to it. The image starts at Mach-O 0x140000000 and the ELF's
first segment at +0x10000, so +0x1d81c4 is ELF address 0x1c81c4. The module has no symbols, but its
dynamic symbol table names every export by NID, and the NIDs of the mangled names in our own
`libSceNpCppWebApi` stubs identify about 650 of them. Disassembled from raw bytes with
`llvm-objdump`:

```
1c81c0: push %rbp; mov %rsp,%rbp
1c81c4: mov (%rsi),%rax          <- fault: %rsi = 0x10
        ... copies three quadwords from %rsi to %rdi, then adds a reference
1eedc0: PostPlayerSessionsResponseBody::getPlayerSessions()  (export JFkvxXYRVS0)
        mov %rdi,%rbx; add $0x10,%rsi; call 0x1c81f0 -> 0x1c81c0
```

So the game called `getPlayerSessions()` on a null response body (`this` = 0, member at 0x10).
The body is filled by the executor that `createPlayerSessions` queues (ELF 0x1dbfb0, found through
its job's vtable at 0x478750). After `sceNpWebApi2SendRequest` it takes the status from the
response information option:

```
1dc224: lea -0x190(%rax),%ecx    ; status - 400
        cmp $4,%ecx / cmp $2,%ecx  ; 400..404 skip the body
        cmp $0xc9,%eax; jne 1dc3cf ; anything but 201: no body
        ... ReadData(id, buf, 0xff) loop, Json::Parser::parse, factory, set response
1dc3cf: xor %eax,%eax            ; finish with success and no response
```

The library reads and parses the body only from a **201** reply. For 200 it finishes the
transaction with success and no response. The game does not check for that and crashes. The same
check is in every Player Sessions call that makes something:

| Call (executor) | Body read on |
|---|---|
| `createPlayerSessions` (0x1dbfb0) | 201 |
| `joinPlayerSessionAsPlayer` (0x1e0610), and an unnamed join that follows it (0x1e1900, likely the spectator one) | 201 (409, 412 and 400-404 read as an error body) |
| `sendPlayerSessionInvitations` (0x1e30e0) | 201 |
| `addPlayerSessionJoinableSpecifiedUsers` (0x1da620) | 201 |
| `getPlayerSessions` (0x1df550), `getPlayerSessionInvitations` (0x1de5f0) | 200 |
| `leavePlayerSession`, `setPlayerSessionProperties`, `changePlayerSessionLeader` | any status (no body) |

The JSON the parser wants: `playerSessions[]`, each with `sessionId` (string) and `member`
(`players[]` with `accountId` and `platform`). Other keys are ignored.

What changed:

- **Launcher (`OnlinePlayerSessions`):** create, join (players and spectators), invitations and
  joinable specified users answer 201. The created session's reply has the platform's shape:
  `{"playerSessions":[{"member":{"players":[{"accountId":"…","platform":"PS5"}]},"sessionId":"…"}]}`,
  with spectators only when there are any. Every reply carries `Content-Type` and `Content-Length`.
- **Engine (NpWebApi2):** `GetHttpResponseHeaderValue(Length)` gives `Content-Length` (the body's
  size) when the launcher sent none. For an HTTP error, `SendRequest` copies the error body into
  the error object the game passes in the response information option. The libSceNpWebApi2
  imports of this game's modules are `CreateRequest`, `AddHttpRequestHeader`, `SendRequest`,
  `ReadData`, `GetHttpResponseHeaderValue(Length)`, `AbortRequest`, `DeleteRequest` (the C++ web API
  library) and `Initialize`, `Terminate`, `Create/DeleteUserContext` (the eboot). All are
  implemented and all are in the observation log.
- **Tests:** `online_probe host` makes the session and the invitation the way the library does
  (status checked before reading, 255-byte reads, header lookups) and prints
  `create_response=parsed` or `none`. `OnlineEngineInteropTests` runs it against the launcher's
  service. `OnlinePlayerSessionsTests` and `online_web_api2` check statuses, headers and shape.

## Test runs on this Mac (2026-10-26, 05:30-06:20)

Run with the nightly v0.2.22-arm-nightly.20261026.1 (main 4fdd12ba9) and later with a launcher
built from the Join fix below, Online play on, signed in, menus driven with keyboard events
(Return = Cross, arrows, I = Triangle), screenshots of the game window.

- **Host Public works.** `POST /v1/playerSessions` was answered 201 with 149 bytes, the library
  read the body (`ReadData`, then 0), and the game showed "Host a Public Game" (Mansion, Max 8,
  Join Game). START loaded Mansion and the player could walk (about 4 fps while it loaded). The
  game then sent `PATCH /v1/playerSessions/<id>` (`joinableUserType`), answered 204. While hosting,
  the game held a UDP connection to a Photon game server (port 5056), so its room was up on Photon.
- **The public list works.** In another run the list showed a real player's lobby
  ("terrific_nave74", 1/2, Mansion, In Lobby). At other times it said "No games found": at 6 in the
  morning there were no public rooms. A second copy of the game on the same Mac, signed in as the
  same player, did not list our own hosted room either. That copy started without the launcher
  (same bridge address), and the host was killed without a log line when it loaded its level while
  both ran. Two copies of a 4.5 GB game on one Mac is not a fair test, so whether the hosted room
  shows to other players still needs a second player.
- **Join crashed (found here, fixed below).** Joining "terrific_nave74" sent
  `POST /v1/playerSessions/e12bb290-…/member/players` with our push context. That session was made
  by the host's console, so the launcher did not have it and answered 404. The game then died:
  `SIGSEGV at 0x10, libSceNpCppWebApi.prx.guest.prx+0x1daa84`. ELF 0x1caa84 is the same pattern as
  the Host crash, a 24-byte member copied from offset 0x10 of a null response body. Join "worked"
  in the 0.2.20 nightly only because the push context failed then, so the game never sent the join.
  The platform lets a player join a session that exists. Now the launcher does the same: it takes a
  join into a session ID it has not seen, answers 201 with the players, and keeps the session from
  then on. Tests: `OnlinePlayerSessionsTests.testJoiningASessionMadeElsewhereIsTaken`, and
  `online_probe join <id>` in `OnlineEngineInteropTests.testAGameJoinsAPlayerSessionMadeElsewhere`.

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
