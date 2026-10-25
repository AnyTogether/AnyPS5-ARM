# Online play: design

Date: 2026-10-25. Status: phase 0 built; phase 1 built and tested on one Mac (two launchers, two engine processes, real WebRTC data channels), not yet run between two Macs; phase 2 designed.
Wire format and the per-library tables: [docs/dev/ONLINE_PLAY.md](../../dev/ONLINE_PLAY.md).

## Goal

Two people who own the same game run it on their own computers and play its online mode together, through AnyTogether, the way the game would have played over the console's network. Today AnyTogether is social only (friends, parties, calls, share play) and every game runs signed out and offline.

AnyPlay ships the same idea (`anyplaynet/AnyPS5` bridge plus `anyplaynet/network`), and this design is based on their bridge spec (https://github.com/anyplaynet/network/blob/main/spec/bridge-protocol.md, MIT/Apache-2.0). Their own status page says no real game plays online yet: the bridge is under review and every platform web API group is still answered "not offered". So the race is not about plumbing, which both sides have, but about who first learns what real games need and answers it.

## The clean line

- Nothing talks to Sony. No Sony keys, certificates, SDK headers or documents; no tokens or auth codes for publisher servers; no anti-cheat bypass.
- The formats we answer come from what games send (the observation log) and from public, community documentation of the console network's web API. Every answer that is not observed working in a game is marked "unverified".
- The title secret a game passes to `sceNpSetNpTitleId` is never logged, stored or sent.
- Off by default. Without the launcher's variables every library answers exactly as before (signed out, offline), and the existing NP and Net tests prove it.
- Only games the player owns; only between identical game versions and engine builds.

## Pieces

```
 game ─ HLE libraries (NpManager, NpWebApi2, Net, NetCtl, ...)
          └ bridge client in libSceNetCtl ──── loopback TCP, HMAC handshake, framed
                                                   │
                                     launcher (AnyPS5.app; on Windows/Linux the Flutter launcher)
                       ┌───────────────────────────┼─────────────────────────────┐
              AnyTogether API              realtime gateway /rt            WebRTC data channels
     (account, friends, game sessions,   (game_session.signal: offers,     to each other player,
      member properties, ICE servers)     answers, candidates)             direct or through TURN
```

1. **Engine bridge.** One small client inside `libSceNetCtl` (every online library already depends on it), reached by the Np and Net libraries through four exported helpers. It is switched on only by `ANYPS5_ONLINE=127.0.0.1:<port>` plus `ANYPS5_ONLINE_SECRET=<64 hex>` for one game start; `ANYPS5_ONLINE_LOG=<file>` adds the observation log, with or without the bridge. A malformed value stops the game naming the variable (as `ANYPS5_REMOTE_PAD` does), because a launcher bug should be loud. We chose our own names rather than AnyPlay's `ANYPS5_NET_*` so the two can never be confused in one environment.
2. **The launcher is the local service.** No helper process: the Mac launcher already holds the AnyTogether session, the realtime socket and WebRTC (Google's prebuilt framework, already used for party voice and share play). It listens on loopback, proves the secret, tells the engine who is signed in, answers web API requests, writes the observation log to a per-game file and owns the peer connections. The Windows/Linux launcher implements the same protocol in Dart from the spec; `flutter_webrtc` gives it the same data channels, so Mac and PC players can meet.
3. **AnyTogether.** Already has what the network side needs: accounts and friends, game sessions with version and engine-build checks (`POST /game-sessions`, `join`, `invites`), per-player member properties (`PUT /game-sessions/:id/members/me`, at most 2 KB, seen only by the session's players), ICE servers with short-lived TURN credentials (`GET /game-sessions/:id/ice-servers`), and the gateway relaying `game_session.signal` only between a session's players. Nothing new is needed on the server for phases 0 and 1.

## Identity

| What the game asks | Answer |
|---|---|
| Signed in? (`sceNpGetState`, state callbacks) | signed in while the launcher reports the AnyTogether user; callbacks fire on every change, and on a lost launcher the user turns signed out at once |
| Online ID | the AnyTogether handle, cut to the platform's 16 characters (handles are 3 to 20 of `a-z 0-9 _ .`; two players whose handles share the first 16 letters look alike in the game, the account IDs still differ) |
| Account ID | the first 8 bytes of SHA-256 of the AnyTogether user ID: stable, never 0, the same on every Mac, so a friend's ID in one game is the same in the next |
| Country, language | the Mac's region and language |
| Plus and premium checks | allowed while signed in through the bridge (Utku's decision of 2026-10-24: signing in is for playing online) |
| Friends | AnyTogether friends, through the `userProfile` web API group below |

## Web API

The engine passes each `libSceNpWebApi2` request through untouched: user, API group, path with query, method, headers, body. Titles that ship their own `libSceNpCppWebApi` copy reach `libSceNpWebApi2` the same way. The launcher answers with status, headers and body; status 0 means "not offered" and the game sees exactly the offline error it sees today. A 30 s timeout or a lost launcher is "not offered" too.

The launcher routes by group:

- **`anyps5`** (our own group, for test programs and future homebrew): AnyTogether game sessions for the running title (`POST /v1/sessions`, `GET/PATCH /v1/sessions/{id}`, `join`, `leave`, `invites`, `GET /v1/me/session`).
- **`userProfile`** (offered, unverified): the friends list (`GET /v1/users/{me | local_<user> | <account>}/friends`, with `offset` and `limit`), one user's profile (`GET /v1/users/{account}/profiles`) and basic presence (`GET /v1/users/{account}/basicPresences`, `GET /v1/users/basicPresences?accountIds=`), shaped after public community documentation of the console network's API. AnyPlay observed Minecraft Dungeons II asking for `GET /v1/users/local_268435456/friends?` every 5 to 10 s; nobody has seen what a game does with an answer yet. The router can be told to answer every platform group "not offered" for a clean observation run.
- **Everything else** (`sessionManager`, `matchmaking`, `gameSessions`, ...): "not offered", counted per path and written to the observation log, until a title tells us its format.

`libSceNpWebApi` (the older interface) has no request functions in AnyPS5 yet; they stop the game as every unimplemented export does, after the observation log records them. `libSceNpCppWebApi`'s high-level typed calls stay offline: filling their response objects needs layouts nobody has observed.

## Observation mode

With `ANYPS5_ONLINE_LOG`, the online libraries append one JSON object per call (library, function, arguments with pointers written as "set"/null, outputs, result, error code), fold repeats of the same call to one line per 5 s, and record unimplemented exports before they stop the game. With the launcher's setting on, each start writes to `~/Library/Logs/AnyPS5/Online/<TitleID>.jsonl`, so a crash still leaves the last line. The log decides which class a title is in:

- **Class A**, the target: only platform services (player/game sessions, matchmaking through the web API, session signalling, P2P or host-based packets).
- **Class B**: the title talks to its publisher's own servers. Out of scope; we do not stand in for them.
- **Class C**: needs something we refuse to provide (server-side entitlement, anti-cheat).

## Game traffic between players

**Virtual addresses.** Each player in an AnyTogether game session gets 198.18.0.N (from 198.18.0.0/15, reserved for benchmarks, so it never meets a real network), N being the place in join order, starting at 1. The game learns peers' addresses the way it would learn real ones (session signalling, or a session's properties); the bridge reports the player's own address with the account.

**In the engine (built for datagrams).** A send from a datagram P2P socket, or from any UDP socket to a 198.18.0.0/15 address, becomes a `Datagram` frame on the bridge connection, queued so the game never blocks (dropped when full, as UDP would). Received datagrams are injected into the game's socket, which is a real host UDP socket on loopback, so poll, epoll, non-blocking mode and timeouts keep working, and the game sees the sender's virtual address and virtual port. Streams (stream P2P sockets, TCP to a virtual address) are phase 2.

**Between launchers: WebRTC data channels.** One `RTCPeerConnection` per pair of players in the session:

- Channel `game`: unordered, `maxRetransmits = 0`. One message per datagram: a 9-byte header (source port, source virtual port, destination port, destination virtual port, kind) and the game's bytes. The sender's virtual address is not in the packet; the receiver knows it from the connection, so a peer cannot pretend to be another.
- Channel `stream` (phase 2): ordered and reliable, multiplexing the game's streams.
- Signalling: offer, answer and ICE candidates as `game_session.signal`, sent to the device each player published in its member properties (`{"online": 1}` is enough; publishing sets the device). The player with the smaller user ID offers, so two launchers never offer at once; a launcher that starts following later sends `renegotiate` so the offer is made again once it listens; leaving sends `bye`.
- ICE servers: `GET /game-sessions/:id/ice-servers`, STUN plus TURN with REST credentials. Direct when the NATs allow; TURN when they do not.
- Security: the gateway relays signals only between the session's players over the authenticated socket, so each side learns the other's DTLS fingerprint from AnyTogether; data channels are encrypted. A frame from a connection whose player is not in the session is dropped.

**Why WebRTC and not a new relay stack.** AnyPlay uses QUIC (iroh) with its own relays. For us WebRTC is already in the Mac launcher, in the Flutter launcher's reach, and AnyTogether already hands out TURN credentials and relays signalling for calls and share play. SCTP over DTLS adds about 50 bytes per message and its datagram path is fine for game packets (a few hundred bytes, 20 to 60 per second per peer). If profiling ever shows a problem, the transport sits behind one Swift protocol (`OnlinePeerTransport`) and can be swapped.

The plain-UDP `OnlinePeerLink` from 2026-10-24 (per-packet HMAC, no NAT traversal) stays as a LAN and test transport behind the same protocol.

## What is hard (honest list)

1. **Session formats, not transport, are the blocker.** A typical PS5 online mode creates a player session (`sessionManager` group), gets invitations and join news through push events, and connects peers through `libSceNpSessionSignaling`. Until the launcher answers a title's `sessionManager` requests in a shape it accepts, that title never reaches the point where it sends a packet. Each group's format must be observed in a class A title we own, answered, and checked by watching what the game does next.
2. **Push events.** The callback signature and filter layout of `sceNpWebApi2PushEvent*` are unknown; sessions and invitations depend on them.
3. **No class A title in hand yet.** Of the titles tested here, Cat Quest III has only local co-op (observed 2026-10-24: start-up calls only), Silksong is offline, Minecraft talks to its publisher's services (class B). Phase 2 needs dumps of P2P online games (small co-op games with PSN sessions are the best bet).
4. **NAT and relay cost.** Symmetric NATs and many mobile hotspots need TURN; game traffic through TURN costs server bandwidth (roughly 50 to 500 kbit/s per player). Production TURN must be configured before two homes can meet; on one network host candidates suffice.
5. **P2P socket semantics.** Virtual ports, the P2P socket options, `libSceRudp` on top, `sceNetCtlGetNatInfo` layouts: unmeasured, learned per title.
6. **Determinism across machines.** Peer-to-peer games assume both sides run the same code. The version guard (same game version, same engine build) is enforced by AnyTogether's `join`; a mixed Mac/PC session also needs the same engine build on both.
7. **Two launchers to keep in step.** The Flutter launcher must speak the same bridge protocol and the same data channel format; the spec is the contract, and the reference bytes in both test suites keep the Mac side honest.

## Phases

**Phase 0: identity, web API, observation. Built.**
Engine bridge (handshake, account, web requests, observation, reconnect), NpManager sign-in and identity, Plus checks, NpWebApi2 pass-through; launcher bridge server, per-title observation file, `userProfile` friends from AnyTogether, the setting Together → "Online play (experimental)" (off by default). Tests: `online_bridge`, `online_observation`, `online_np_manager`, `online_web_api2`, `online_probe_offline`, the guest NP and Net suites unchanged; `swift test --filter Online`, including `OnlineEngineInteropTests`, which starts the real engine libraries in a stand-in game (`online_probe`) against the launcher's real service and checks the game signs in as the AnyTogether user (handle, account ID, country) and gets its AnyTogether friends through `userProfile`.

**Phase 1: packets between two computers. Built; tested on one Mac.**
Datagram P2P sockets and UDP to virtual addresses (engine, `online_net_p2p`); WebRTC data-channel transport with game-session signalling (`OnlinePeerMesh`); the app makes it the transport and follows the AnyTogether game session it already keeps for the running game. Tests: `OnlinePeerMeshTests` (two launchers, two fake engines, real data channels: ping, pong, a burst of 200 packets of 1200 bytes, a stranger's address refused, a goodbye on leaving) and `OnlineEngineP2pTests` (two `online_probe` processes play ping-pong through P2P sockets, each behind its own launcher). Done when two Macs on different networks pass the probe's packets both ways, which needs production STUN and TURN.

Left in phase 1: the two-Mac run; the peers' connection state in the UI (`OnlinePeerMesh.states` and `traffic` exist); TURN credential renewal for sessions longer than the credentials (calls renew them; the mesh asks once per session); a slow game that stops reading its bridge would block WebRTC's thread on delivery (the engine reads on its own thread, so this needs a stuck process).

**Phase 2: sessions a real game accepts.**
`libSceNpSessionSignaling` answered from the mesh (activation, connection events, peer address and RTT); stream P2P and TCP to virtual addresses over the `stream` channel; push events; join intents and the invitation dialog from AnyTogether invitations; the `sessionManager` player-session requests of the first class A title mapped onto AnyTogether game sessions. Done when one real title plays a match between two Macs.

**Phase 3: breadth.** More groups per title (matchmaking), `libSceNpMatching2` and `libSceNpSignaling` for older titles, voice chat over the same connections, the Windows/Linux launcher, a compatibility list of online titles.

## Decisions and needs

- **TURN in production.** `iceServers` returns nothing unless `TURN_URLS` and `TURN_SECRET` are set; without STUN/TURN only players on one network connect. Utku: confirm production has STUN and TURN configured (the server-control session knows) and that game traffic may use it.
- **Unverified `userProfile` answers.** Offered by default because friends were asked for; if a title misbehaves on them, the router turns platform groups off (`defaults write <launcher> OnlinePlayPlatformGroups -bool NO`).
- **Titles to observe.** Utku: dumps of P2P co-op or versus games you own, for the first class A observation runs.
- **Plus checks** stay "allowed while signed in" (decided 2026-10-24).
