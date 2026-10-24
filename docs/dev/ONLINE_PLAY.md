# Online play

Two players each run the same game on their own Mac. The game makes the PlayStation-platform calls it always makes (sign-in, sessions, matchmaking, signalling, peer-to-peer packets) and AnyPS5 carries them, through the launcher and AnyTogether, to the other player. Nothing ever goes to Sony, and nothing stands in for a publisher's own servers.

This page is the design. Built in the engine so far: the bridge client and its protocol, observation mode, sign-in state (NpManager) and web API pass-through (NpWebApi2), each tested against a fake launcher. Not built yet: the launcher side, push events, session signalling, game traffic and intents.

## The clean line

- No Sony servers, keys, certificates, SDK documents or code. Every format comes from what games send, observed with the log below.
- The title secret a game passes to `sceNpSetNpTitleId` is never logged, stored or sent.
- No tokens or auth codes for publisher back ends, no stand-ins for publisher servers, no anti-cheat bypass.
- Nothing changes unless the launcher sets the variables below; without them every library answers as it does today (signed out, offline).

## What a game calls, and what the engine does today

A typical host-based or peer-to-peer PS5 game goes through these steps. "Today" is `main` without the bridge.

| Step | Libraries and functions | Today | With the bridge |
|---|---|---|---|
| Network up? | `sceNetCtlInit`, `sceNetCtlGetState`, `sceNetCtlGetInfo`, `sceNetCtlCheckCallback` | real host state and address | unchanged |
| NAT type | `sceNetCtlGetNatInfo` | throws (not implemented) | planned: the launcher's measured NAT type; layout unverified on PS5 |
| Signed in? | `sceNpGetState`, `sceNpRegisterStateCallbackA` + `sceNpCheckCallback`, `sceNpHasSignedUp` | signed out | signed in when the launcher says so; callbacks fire on every change |
| Who am I | `sceNpGetOnlineId`, `sceNpGetNpId`, `sceNpGetAccountIdA`, `sceNpGetUserIdByAccountId`, `sceNpGetAccountCountryA`, `sceNpGetAccountLanguageA` | `SIGNED_OUT` errors | the AnyTogether handle and account number |
| Allowed online | `sceNpCheckNpAvailabilityA`, `sceNpGetParentalControlInfoA`, `sceNpCheckPlus`, `sceNpNotifyPlusFeature` | `SIGNED_OUT` | availability: yes; parental info from the launcher when it has an age; **Plus: unchanged, open question** |
| Sessions, matchmaking, friends | Web API: `sceNpWebApi2CreateUserContext`, `CreateRequest(apiGroup, path, method)`, `AddHttpRequestHeader`, `SendRequest`, `ReadData`, `GetHttpResponseHeaderValue`; C++ wrappers in `libSceNpCppWebApi` end up here when a title ships its own copy | requests created, `SendRequest` fails with `0x80553406` | passed through, body untouched, to the launcher; the launcher answers the API groups it implements and says "not offered" for the rest, which the game sees exactly as today |
| Session and invitation news | `sceNpWebApi2PushEventCreateHandle`, `CreateFilter`, `RegisterCallback`, `CreatePushContext`, `StartPushContextCallback` | handles exist, nothing is ever delivered | planned (push frames); callback signature and filter layout still to be observed |
| Join from the system | `sceNpGameIntent*`, `libScePlayerInvitationDialog` | no intents | planned: an AnyTogether invitation becomes a join intent |
| Connect to peers | `sceNpSessionSignalingInitialize`, `CreateContext2`, `ActivateSession`, `ActivateUser`, `GetConnectionInfo`, `GetConnectionStatus`, `GetLocalNetInfo`; older titles `libSceNpSignaling`, `libSceNpMatching2` | contexts exist, activation `UNAVAILABLE`; Signaling and Matching2 not implemented | planned: connection events from the launcher's peer list, each peer at a virtual address |
| Game packets | `sceNetSocket` with the P2P types (datagram and stream, with virtual ports), `sceNetSendto`/`sceNetRecvfrom`, often under `libSceRudp` | P2P types fail with `EPROTONOSUPPORT`; ordinary sockets reach the real network | planned: packets to a virtual address go through the bridge to the launcher, which carries them to the peer |
| Activities, trophies, add-ons | `libSceNpUniversalDataSystem`, `libSceNpTrophy2`, `libSceNpEntitlementAccess` | offline implementations | unchanged |

Unimplemented exports in these libraries stop the game, as everywhere in AnyPS5. The observation log records them first, which is how we learn what a title needs next.

## Architecture

```
 game ─ HLE libraries ─ bridge client (libSceNetCtl)
                              │  loopback TCP, framed, per-start secret
                         launcher (AnyPS5.app)
             ┌────────────────┼──────────────────────┐
     AnyTogether API     realtime socket       WebRTC data channels / QUIC
  (game sessions,       (invitations,         to the other player's launcher,
   invitations)          signalling)           relay when direct fails
```

- **Engine** (this branch): a small client in `libSceNetCtl`, used by the Np libraries through four exported functions (`OnlineAccount`, `OnlineWeb`, `OnlineObserve`, `OnlineEnabled`, all `_nid_no_patch`). It never parses web bodies, never speaks JSON over the wire to a server, never does ICE.
- **Launcher**: starts the game with the variables below, answers the bridge, translates platform API groups into AnyTogether calls, owns the peer connections.
- **AnyTogether**: game sessions and invitations (being added on its `social` branch), the realtime socket that already carries call signalling, and the relay. Peers connect directly whenever they can, as calls and share play already do.

## Bridge protocol (version 1)

**Switch.** The launcher listens on a loopback TCP port and starts the game with:

| Variable | Value |
|---|---|
| `ANYPS5_ONLINE` | `127.0.0.1:<port>`; nothing else is accepted, so the bridge cannot be pointed off the machine |
| `ANYPS5_ONLINE_SECRET` | 64 hex digits, fresh random for every game start |
| `ANYPS5_ONLINE_LOG` | optional; file for the observation log (works without the other two) |

An empty value is unset. A malformed value stops the game with an error naming the variable, as `ANYPS5_REMOTE_PAD` does.

**Handshake.** The secret never crosses the socket. Each side proves it knows it, so neither a stray program on the port nor a stray client can pass:

1. engine → `Hello`: protocol version, 16-byte engine nonce, engine build, process ID
2. launcher → `Welcome`: protocol version, 16-byte launcher nonce, `HMAC-SHA-256(secret, "anyps5-online/1 launcher" ‖ engine nonce ‖ launcher nonce)`
3. engine checks it, else hangs up silently; → `Proof`: the same HMAC with label `"anyps5-online/1 engine"`
4. launcher checks it; → `Account` (always the first frame after the handshake), or `Refuse` and closes

A refusal for a bad proof or protocol version is final; for "no game" or "busy" the engine tries again. On any disconnect the user turns signed out at once (state callbacks fire), pending requests fail as "not offered", and the engine reconnects every 2 s with the same secret, so a launcher that restarts picks the game up again. The first sign-in question waits at most 2 s for the first `Account`.

**Frames.** Little-endian, 12-byte header then payload:

```
0  u32 length   payload bytes, at most 16 MiB (a larger value drops the connection)
4  u16 type
6  u16 flags    bit 0 reply, bit 1 unsupported; others 0
8  u32 call     0 for events; otherwise unique among the sender's open calls
```

A reply has the request's type and call with the reply bit. Fields are packed in order: integers little-endian, `str` = u16 length + UTF-8, `bytes` = u32 length + data, `pairs` = u16 count + (str, str). Fields are only ever added at the end; a reader ignores extra trailing bytes, skips unknown events and answers unknown calls with `unsupported`.

| Type | Name | Direction | Payload |
|---|---|---|---|
| 0x0001 | Hello | engine → | u16 protocol, 16 nonce, str build, u32 pid |
| 0x0002 | Welcome | → engine | u16 protocol, 16 nonce, 32 proof |
| 0x0003 | Proof | engine → | 32 proof |
| 0x0004 | Refuse | → engine | u16 reason (1 bad proof, 2 protocol, 3 no game, 4 busy), str text |
| 0x0101 | Account | → engine, event | u8 signed in, u64 account, str online ID (≤ 16), str country (≤ 2), str language, u8 age (0 unknown), u32 virtual address, u8 NAT type |
| 0x0102 | Observation | engine →, event | str: one observation log line |
| 0x0201 | WebRequest | engine →, call | i32 user, str API group, str path with query, str method, pairs headers, bytes body → reply: u16 status (0 = not offered), pairs headers, bytes body |
| 0x0202–0x0204 | PushFilter, PushFilterGone, PushEvent | planned | filter ID, service, data types; event data opaque |
| 0x0301–0x0306 | SessionActivate, SessionDeactivate, Peer, PeerInfo | planned | session ID; peer account, handle, virtual address, state (connecting, connected, gone, failed), RTT, relayed |
| 0x0310–0x0313 | Datagram, StreamOpen, StreamData, StreamClose | planned | virtual address, ports, virtual ports, bytes |
| 0x0401–0x0402 | Intent, InvitationDialog | planned | intent type and properties; session, maximum |

**Web API.** The engine passes the request as the game built it; the body stays opaque in both directions. The launcher keeps one handler per API group (sessions and matchmaking first) that maps the request onto AnyTogether's game sessions and invitations. Status 0, a timeout (30 s unless the game set one) or a lost connection make the engine answer exactly as it does offline. The launcher never forwards anything to Sony and never invents a 200 for a group it has no specification for.

## Game traffic

- **Virtual addresses.** Each member of an AnyTogether game session gets an address from 198.18.0.0/15 (reserved for benchmarking, so it never collides with a real network), assigned by the session in join order. The game learns peers' addresses from session signalling, as it would learn real ones.
- **Engine side.** A send from a P2P socket, or any UDP or TCP socket, to a virtual address becomes a `Datagram` or `Stream*` frame on the same loopback connection; frames from the launcher are delivered as if they came from that address and virtual port. Sends never block the game: datagrams drop when the queue is full, as UDP would. Loopback TCP adds well under a millisecond and loses nothing, so head-of-line blocking does not matter on that hop.
- **Between launchers.** Datagrams ride an unordered, unreliable WebRTC data channel (or QUIC datagrams); streams ride a reliable ordered channel (or QUIC streams). The launcher connects directly when it can and uses the AnyTogether relay when it cannot, as calls and share play already do. Session membership in AnyTogether is the signalling channel; the realtime socket carries offers and candidates.
- **Session signalling** (`libSceNpSessionSignaling`) is answered from the launcher's peer list: `ActivateSession` asks the launcher, connection callbacks fire on `Peer` events, `GetConnectionInfo` returns the peer's virtual address and port.

## Version guard

Online play only works between identical games and compatible engines:

- **Protocol.** `Hello`/`Welcome` carry the bridge protocol version; a mismatch is refused and final.
- **Game.** The launcher sends title ID and content version (from the game's param file) when it creates or joins an AnyTogether game session; the server refuses a join whose title or version differs, and the launcher says why. The engine build travels in `Hello` so mismatched engines show up in reports, but it does not block play: the game's own netcode does not depend on it.

## Which games can work

- **Class A, the target:** online built only on platform services: player or game sessions, matchmaking through the web API, session signalling, P2P or host-based traffic. Two copies can play once the groups the title uses are answered.
- **Class B:** games that talk to publisher servers (their own back end or a third-party online service). Out of scope: we do not stand in for those servers.
- **Class C:** games that need something we will not provide, such as a PS Plus check that must pass, server-side entitlement checks or anti-cheat. `sceNpCheckPlus` keeps today's answer until there is a decision (see below).

The observation log tells which class a title is in: class A titles only show Np library calls and web API groups; class B titles also open their own sockets or HTTP connections to publisher hosts.

## Observation mode

With `ANYPS5_ONLINE_LOG=<file>`, NpManager, NpWebApi, NpWebApi2, NpSessionSignaling, NpAuth, NpGameIntent, NpEntitlementAccess and NetCtl append one JSON object per call:

```json
{"v":1,"t_ms":5012,"lib":"libSceNpWebApi2","fn":"sceNpWebApi2CreateRequest","in":{"user_context_id":3,"api_group":"sessionManager","path":"/v1/playerSessions","method":"POST","content_parameter":"set","request_id":"set"},"ret":0}
{"v":1,"t_ms":5013,"lib":"libSceNpManager","fn":"sceNpGetOnlineId","in":{"user_id":1,"online_id":"set"},"ret":-2141913082,"err":"0x80550006"}
{"v":1,"t_ms":6000,"lib":"libSceNpManager","fn":"sceNpCheckCallback","ret":0,"repeats":59}
{"v":1,"t_ms":7020,"fn":"sceNpMatching2Initialize","not_implemented":true}
```

Pointers are written as `"set"` or `null`, never as addresses, so identical calls fold: a repeat of the same call is counted and written again at most every 5 s with `repeats`. Request bodies are written as text, or as hex when they are binary, cut at 4 KiB. The log works with or without a launcher; with one, every line is also sent as an `Observation` frame so the launcher can collect them per title.

## Compared with AnyPlay

AnyPlay's public design (`anyplay-gg/network`, engine pull request `feat/net-bridge`) solves the same problem and we learned from it. RPCN (PS3) and shadPS4's shadnet (PS4) go further and reimplement the platform service itself; we pass requests through to the launcher instead, so the engine stays small and the server is AnyTogether. We did not copy code; where we agree it is because the problem leaves little choice.

| Topic | AnyPlay | Ours | Why |
|---|---|---|---|
| Split | bridge forwards, a separate net service translates | same idea, but the translator lives in the launcher | our launcher already owns sign-in, AnyTogether and the realtime socket; one less process |
| Switch | `ANYPS5_NET_ENDPOINT` + `ANYPS5_NET_TOKEN` | `ANYPS5_ONLINE` + `ANYPS5_ONLINE_SECRET` | same shape |
| Authentication | the token is sent raw in `hello` | HMAC challenge both ways; the secret never travels | a program squatting the port learns nothing, and the engine never believes a fake launcher |
| Bad values | bridge silently stays off | the game stops with the variable named | matches `ANYPS5_REMOTE_PAD`; a launcher bug should be loud |
| Frames | 12-byte header, reply = kind \| 0x8000 | 12-byte header, reply and unsupported as flag bits | type numbers stay one space |
| Game packets | separate loopback UDP socket and keyed TCP streams per bound port | the same control connection | one authenticated channel and one reader; loopback has no loss. We will split it out only if profiling says so |
| Peer transport | iroh (QUIC, hole punching) and iroh relays | WebRTC data channels or QUIC, with the relay AnyTogether already runs for calls | reuse what our launcher and server already do for voice and share play |
| Virtual addresses | per account, leased by the cloud from 198.18.0.0/15 | per session, in join order, same range | no lease table on the server |
| Observation | JSONL, async writer, every export | JSONL, folded repeats, flushed per line, implemented exports plus a libc hook for unimplemented ones | a line must survive the crash that follows an unimplemented call |
| Plus check | stays signed out until a legal review | same, until decided | |

## Test plan

1. **Unit** (`ctest -R online_bridge`): frame and field encoding byte for byte, HMAC proofs against reference values, environment parsing, and the client against an in-process fake launcher: handshake, an impostor launcher, refusal, account changes, concurrent web requests answered out of order, unsupported and timed-out requests, unknown frames, oversized frames, dropping and reconnecting, launcher gone.
2. **Libraries** (`ctest -R online_observation`, `guest_np_*`): the observation log through the real exports, and each library answering as today without the variables.
3. **Sign-in and web API through the exports** (`ctest -R online_np_manager`, `online_web_api2`): the real NpManager and NpWebApi2 exports against the fake launcher with the variables set.
4. **Observe real games**: run class A candidates with `ANYPS5_ONLINE_LOG` only, then with a launcher that signs in and answers nothing; read which groups, paths and signalling calls each one makes.
5. **Two instances on one Mac**: two launchers, two games, the relay disabled, loopback transport; then two Macs on one network; then two networks with the relay.
6. **Version guard**: mismatched title version and protocol are refused with a reason on both sides.

## Open questions

- **PS Plus.** Most P2P titles call `sceNpCheckPlus` before online play. Answering "allowed" is a product and legal decision, not a technical one.
- **Push events.** The callback signature and filter parameters of WebApi2 push events are still unknown; they come next from observation.
- **NAT info and P2P socket semantics** (`sceNetCtlGetNatInfo`, P2P socket options, virtual-port rules) need measuring on titles that use them.
- **Voice chat** (`libSceVoiceChat`) can ride the same peer connections; not designed yet.
