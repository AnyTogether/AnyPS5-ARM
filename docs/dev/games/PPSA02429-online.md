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
| Push event filter on `sessionManager` (17 filter parameters) | the filter is made; no events come |

The `sessionManager` push filter and the `PlayerSession` / `sessionManager` strings show that the game
uses platform Player Sessions, probably for invitations and "join a friend" from the system UI. No
`sessionManager` web request has been seen yet. If Host turns out to make one (for example
`POST /v1/playerSessions`), the launcher would need to answer it locally from the AnyTogether session,
the same way it answers `userProfile`. It must never be passed on to Sony.

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

1. Update to a build with c6d921416 and later (the next release after 0.2.19, or a local
   `taskpolicy -b ninja -C build-mac all libs`), then reinstall or re-convert the game so the bundle
   picks up the new libraries.
2. Turn on Settings → AnyTogether → Online play (experimental) and sign in.
3. Start the game, press Online, then Host Public, and try Join on a public lobby.
4. Send `~/Library/Logs/AnyPS5/PPSA02429.log` (and `PPSA02429.previous.log` if the game was started
   again since) and `~/Library/Logs/AnyPS5/Online/PPSA02429.jsonl`. The jsonl shows any
   `sessionManager` request the game makes on Host. Repeated error lines are now cut after 50
   copies every 10 s, so the log stays small.

Open: whether Host makes a `sessionManager` request that needs a local answer, and why the joined
level ran at about 1.5 fps. Check the second one again once the poll loop stops failing.
