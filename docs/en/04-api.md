# 4. API

Base: `https://anytogether.kodla.agency/api/v1` (one hostname for everything; see [Architecture](02-architecture.md)); a self-hosted AnyTogether answers the same paths on its own host name. JSON in and out, UTF-8, field names in camelCase (`titleId`, `startedAt`), times as RFC 3339 in UTC,
IDs as UUIDv7 strings (sortable by time). Errors are RFC 9457 problem details:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

Clients translate `code` into their own language (the launcher and the phone already carry
English and Turkish). The code is public ([github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether)):
today the Zod schemas in `packages/shared` are the contract. An OpenAPI 3.1 document generated
from them at `/api/v1/openapi.json`, with Swift, Dart and TypeScript types, is planned.

Every request from a client carries `AnyTogether-Client`, naming the client and platform:
`launcher-macos/0.2.13 (macOS 26.6; Mac15,9)`, `launcher-windows/0.3.0 (Windows 11 24H2)`,
`launcher-linux/0.3.0 (Fedora 41; KDE)`, `phone/1.10.0 (iOS 27.0)`, `web/…`. The API records it with
each signed-in device. Refusing a client too old to be safe with `426 Upgrade Required` (code
`upgrade_required`, shown as "Update AnyPS5 to use AnyTogether") is planned.

Each table below marks what is **built** (in the code on 2026-10-24) and what is **planned**.

## 4.1 Sign-in: one tap, no registration form

There is **no sign-up step and no password**. The first sign-in creates the account; the handle
and display name are taken from the provider or the email address (editable later); the avatar
too, if the provider has one.

| Way in | Where | What the user does | Status |
|---|---|---|---|
| **Email code** | everywhere | type the email, then the 6-digit code from the mail (or click the link in it); nothing to remember | built: web, macOS launcher, phone |
| **Passkey** | the website (Touch ID, Windows Hello, a phone, a password manager) | add one in Settings once signed in; later sign-ins need no email at all | built: web |
| **From the phone** | any launcher whose phone app is paired and signed in, and the other way round | the launcher asks, the phone shows "Sign in <Mac/PC name>?", one tap | built: macOS launcher and phone |
| **Device code** (fallback) | a launcher with no browser at hand | the launcher shows a code and a QR; approve on the web at `/link` | built in the API and web |
| **Continue with Apple** | macOS launcher (native sheet, Touch ID), iPhone (native), web | one tap | API built (off until the server is given client IDs); buttons planned |
| **Continue with Google** | every launcher (system browser), Android (native Credential Manager), web | one tap if already signed in to Google | the same |
| **Continue with Discord** | every launcher (system browser), phone, web | one tap if already signed in to Discord | the same |

**How the launchers will do the providers**: OAuth 2.0 with PKCE in the system browser, as RFC
8252 asks for native apps. macOS uses `ASWebAuthenticationSession` (a sheet that shares the
browser's sign-ins, so Google or Discord is usually one click) and `ASAuthorizationAppleIDProvider`
for Apple; Windows and Linux open the default browser and receive the result on a loopback
redirect (`http://127.0.0.1:<random port>/callback`). The phone uses the native Apple, Google and
Discord flows. All of them end at our API, which checks Apple's and Google's ID tokens against
their keys and our client IDs, exchanges Discord's code (with the PKCE verifier) for the user, and
issues our own tokens.

**The phone hand-off** goes over the local link the phone and the launcher already share (the
phone protocol, [Platforms](12-platforms.md) 12.4): the side that wants to be signed in starts a
hand-off with the API and sends its ID in a `togetherHandoff` message; the other side, signed in,
approves it with the API and answers `togetherHandoffAnswer`; the asker's poll of `/auth/token`
then gets its tokens. A paired phone asking a signed-in launcher is approved at once.

| Method | Path | What it does | Status |
|---|---|---|---|
| POST | `/auth/email/start` | `{email}` → mails a 6-digit code and a link (valid 10 min) | built |
| POST | `/auth/email/verify` | `{email, code}` or `{email, link}` → tokens; creates the account on first use | built |
| POST | `/auth/passkey/start` | → `{challengeId, options}` for `navigator.credentials.get()` (discoverable, valid 5 min) | built |
| POST | `/auth/passkey/finish` | `{challengeId, response, deviceName?}` → tokens | built |
| GET | `/auth/passkeys` | your passkeys (name, synced or not, added, last used) and the maximum, 10 | built |
| POST | `/auth/passkeys/start` | (signed in) → options for `navigator.credentials.create()` | built |
| POST | `/auth/passkeys` | (signed in) `{response, name?}` → the new passkey | built |
| DELETE | `/auth/passkeys/{id}` | remove one | built |
| POST | `/auth/oidc/{apple,google,discord}` | Apple, Google: `{idToken, nonce?}`; Discord: `{code, codeVerifier, redirectUri}` → tokens; creates the account on first use | built |
| POST | `/auth/handoff/start` | (asker) `{deviceName}` → `{handoffId, secret, expiresIn}` (5 min) | built |
| POST | `/auth/handoff/{id}/approve` | (signed in) → approves | built |
| POST | `/auth/device` | (fallback) `{deviceName}` → `deviceCode`, `userCode` (`XXXX-XXXX`), `verificationUri`, `expiresIn`, `interval` (RFC 8628) | built |
| POST | `/auth/device/approve` | (signed in) `{userCode}` → approves | built |
| POST | `/auth/token` | `{grantType: "refresh_token", refreshToken}`, `{grantType: "device_code", deviceCode}` or `{grantType: "handoff", handoffId, secret}` → tokens; until approved, `authorization_pending` | built |
| POST | `/auth/logout` | revokes this session | built |
| GET | `/auth/sessions` | the signed-in devices, this one marked | built |
| DELETE | `/auth/sessions` | sign out everywhere; `?keep=current` keeps this device | built |
| DELETE | `/auth/sessions/{id}` | sign one device out | built |
| GET | `/.well-known/jwks.json` | the public key of the access tokens (the gateway uses it) | built |
| GET | `/auth/providers` | the ways in this client may offer | planned |
| POST | `/me/identities/{provider}` | link another way in (Apple + Discord on one account) | planned |

**Tokens.** Access token: a JWT (EdDSA, Ed25519, 15 minutes) naming the user and the session.
Refresh token: 256 random bits, stored only as a SHA-256 hash, valid 90 days and **rotated on every
use**; reusing an old one revokes the session (`refresh_reused`). Kept in the platform's secure
store: macOS Keychain, Windows Credential Manager, the Secret Service on Linux (GNOME Keyring,
KWallet), iOS Keychain, Android Keystore; the web in an HttpOnly, Secure, SameSite=Lax cookie, so
the browser itself never holds a token.

**Passkeys.** WebAuthn discoverable credentials for the website's host name (the relying party),
so the browser offers them without asking for an email. The user handle inside a passkey is the
account's ID as 16 bytes, never an email or a handle. Up to 10 per account. A banned account is
refused here as everywhere, and signing in to an account waiting to be deleted keeps it.

## 4.2 Me, profiles and settings

| Method | Path | What it does | Status |
|---|---|---|---|
| GET | `/me` | account, profile, privacy | built |
| PATCH | `/me/profile` | `displayName`, `bio` (160), `country`; names and bios cannot carry links | built |
| PATCH | `/me/profile` | showcase, profile theme | planned |
| PATCH | `/me/handle` | new handle (once per 30 days; the old one is held for you 30 days and still leads to the profile) | built |
| PUT | `/me/avatar` | the image itself (PNG or JPEG, up to 5 MB) → re-encoded to a 256 px JPEG without metadata | built |
| DELETE | `/me/avatar` | remove it | built |
| GET | `/avatars/{hash}.jpg` | an avatar, by the hash of its bytes (cached for a year) | built |
| PATCH | `/me/privacy` | per section: `library`, `trophies`, `friends`, `presence`, `search`; each `everyone`, `friends` or `nobody` (see Features 3.5) | built |
| GET | `/me/export` | all your data as one JSON file, at once (KVKK/GDPR) | built |
| POST | `/me/deletion` | mails a 6-digit code to confirm deleting; an account with no email confirms with its handle | built |
| DELETE | `/me` | `{code}` or `{handle}` → the account is deleted after 14 days; signing in before then keeps it | built |
| GET | `/users/{handle}` | a profile, as the asker may see it | built |
| GET | `/users/{handle}/friends` | their friends, if their privacy allows | built |
| GET | `/users/search?q=` | find people by handle or name (those whose `search` setting allows it) | built |
| PATCH | `/me/notifications` | which push and mail notifications | planned |

## 4.3 Games, sessions and trophies

| Method | Path | What it does | Status |
|---|---|---|---|
| POST | `/me/devices` | register a computer: `{id, platform, name, model?}` (the launcher's own random ID) | built |
| PUT | `/games/{titleId}` | teach the catalogue a game: names per language, icon (refused once a moderator has locked it) | built |
| GET | `/games/{titleId}` | catalogue entry, how many players, its trophy sets | built |
| POST | `/me/sessions` | batch of sessions `{id, titleId, deviceId, startedAt, endedAt, exit?}` | built |
| GET | `/users/{handle}/library` | games, play time, last played, progress | built |
| PUT | `/trophy-sets/{titleId}/{setHash}` | the trophy set: IDs, grades, hidden flags, names and descriptions per language | built |
| POST | `/me/trophies` | batch `{titleId, setHash, trophyId, earnedAt}`; repeats are ignored; friends get `trophy.earned` | built |
| GET | `/users/{handle}/trophies?titleId=` | earned trophies with dates and rarity | built |
| POST | `/games/{titleId}/reports` | compatibility report (opt-in), see Features 3.7 | planned |

**Batching and idempotency.** The launcher sends batches of up to 200 items. Sessions carry a
client-made UUID and trophies are keyed by account, game and trophy, so a batch can be resent
after a timeout without double counting. The response lists per item `stored`, `duplicate` or
`rejected` with a code (such as `unknown_device` or `unknown_trophy`).

## 4.4 Friends, presence, activity

| Method | Path | What it does | Status |
|---|---|---|---|
| GET | `/me/friends` | friends with presence | built |
| POST | `/me/friends/requests` | `{handle}` → request (accepted at once if they had asked you) | built |
| GET | `/me/friends/requests` | incoming and outgoing | built |
| POST | `/me/friends/requests/{userId}/accept` / `decline` | | built |
| DELETE | `/me/friends/{userId}` | unfriend | built |
| POST | `/me/blocks` / DELETE `/me/blocks/{userId}` | block, unblock | built |
| POST | `/me/friends/requests` | `{qrToken}`, with `GET /me/qr` for a short-lived token | planned |
| GET | `/me/feed?before=` | friends' activity, newest first, 30 per page | planned |
| POST / DELETE | `/activities/{id}/like`, POST `/activities/{id}/comments` | | planned |

Presence is not set over REST; it travels over the realtime socket (4.7).

## 4.5 Messages and reports

Conversations are between friends.

| Method | Path | What it does | Status |
|---|---|---|---|
| GET | `/me/conversations` | conversations with last message and unread count | built |
| GET | `/me/conversations/unread` | the unread total, for a badge | built |
| POST | `/conversations` | `{members, title?, group?}` → direct (2 people, made once and reused) or group (up to 32) | built |
| GET / PATCH | `/conversations/{id}` | one conversation; rename a group | built |
| POST | `/conversations/{id}/members` / DELETE `/conversations/{id}/members/{userId}` | add to a group; remove someone, or leave | built |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | history, by message sequence (up to 100 per page) | built |
| POST | `/conversations/{id}/messages` | `{clientId, text, replyTo?}`; text up to 4000 characters | built |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | edit (15 min) or delete your message | built |
| POST | `/conversations/{id}/read` | `{upToSeq}` | built |
| POST | `/reports` | `{targetKind: "user" \| "message", targetId, reason, note?}`; a reported message's text is kept for the moderators | built |
| POST | `/conversations/{id}/attachments` | → upload URL for an image | planned |

## 4.6 Parties, calls, game sessions, share play

Voice is peer-to-peer (see [Realtime](06-realtime-voice-shareplay.md)); the API only sets calls up
and hands out relay credentials. Game sessions are the server's half of joining a friend's game
and of online play.

| Method | Path | What it does | Status |
|---|---|---|---|
| POST | `/parties` | `{privacy: "invite" \| "friends"}` → party; the asker leads it (and leaves any other party) | built |
| GET | `/me/party` | the party I am in, and invites waiting for me | built |
| GET / PATCH | `/parties/{id}` | members, what they play, the call; change privacy (leader) | built |
| POST | `/parties/{id}/invites` | `{userIds}` (friends) | built |
| POST | `/parties/{id}/join` / `decline` / `leave` | at most 8 members | built |
| POST | `/parties/{id}/kick` / `leader` | `{userId}`: the leader removes someone or hands over | built |
| POST | `/calls` | `{partyId}` (the party's voice) or `{userId}` (a friend) → the call, ICE servers (STUN, TURN with credentials valid 12 h) | built |
| GET | `/calls/{id}` | who is in it, on which device | built |
| POST | `/calls/{id}/answer` / `decline` / `leave` | a call to you, answered on this device; leaving a party call ends it with its last voice | built |
| GET | `/ice-servers` | fresh TURN credentials for a running call | built |
| POST | `/game-sessions` | `{titleId, gameVersion, engineBuild, capacity (2-16), joinable, properties (≤ 4 KB)}` → the session the asker hosts | built |
| GET | `/me/game-session` | the session I play in, and invites waiting for me | built |
| GET / PATCH / DELETE | `/game-sessions/{id}` | see it (players, invitees, and the host's friends while joinable); change capacity, joinable, properties; end it (host) | built |
| POST | `/game-sessions/{id}/invites` | `{userIds}` (friends) | built |
| POST | `/game-sessions/{id}/join` | `{gameVersion, engineBuild}`; another version or build is refused with `version_mismatch`, a full one with `full` | built |
| POST | `/game-sessions/{id}/decline` / `leave` | the host leaving ends it | built |
| POST / DELETE | `/calls/{id}/share-play` | the host starts or stops sharing; members are told. Watch only: no endpoint ever hands control to a viewer | planned |
| POST | `/calls/{id}/quality` | the client's report at the end: direct or relayed, round trip, loss, glass-to-glass samples | planned |

The offers, answers and ICE candidates themselves travel over the gateway (`signal`, 4.7).

## 4.7 Realtime gateway

`wss://anytogether.kodla.agency/rt`. Built. The client says who it is in the first frame (not in
the URL, so it never lands in logs): launchers and the phone with their access token, the
website's browser with a one-time ticket (`POST /realtime/ticket`, valid 30 s) that its server
asks for, since the browser never holds a token:

```json
{ "op": "hello", "token": "<access token>", "client": "launcher-windows/0.3.0", "resume": "<last event id>" }
```

The server answers `{"op":"ready","session":"…","heartbeat":25}` and then sends events:

```json
{ "op": "event", "id": "…", "type": "message.created", "data": { … } }
```

The client sends `{"op":"heartbeat","presence":{"state":"in_game","titleId":"PPSA01234","since":"…"}}`
every 25 s (and at once when presence changes). Missing two heartbeats closes the socket and the
presence expires. On reconnect, `resume` with the last event ID replays what was missed in the
last 5 minutes (kept in a Valkey stream per user); older gaps are filled with REST calls. Close
codes: 4001 no or bad hello, 4003 signed out, 4008 no heartbeat, 4029 too many frames.

| Event | When | Status |
|---|---|---|
| `presence.updated` | a friend's state or game changed; also their party and joinable game session | built |
| `friend.request`, `friend.accepted`, `friend.removed` | | built |
| `trophy.earned` | a friend earned a trophy (a hidden one without its name) | built |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `conversation.updated` | | built |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | | built |
| `call.ringing`, `call.answered`, `call.joined`, `call.left`, `call.ended` | a call to you; answered on another device; someone in or out of a party's voice; over | built |
| `signal` | WebRTC offer, answer, ICE candidate, bye or renegotiate from a call peer (relayed, never stored) | built |
| `game_session.invite`, `game_session.updated`, `game_session.ended` | | built |
| `account.signed_out` | this session was revoked elsewhere | built |
| `typing` | | planned |
| `share_play.started`, `share_play.stopped` | | planned |
| `activity.created` | a friend's activity for the feed | planned |
| `trophy.rarity_changed` | a trophy you own crossed a rarity label | planned |

`auth.handoff` exists in the shared types; the hand-off itself goes over the phone's local link
(4.1), so the gateway does not send it today.

## 4.8 Themes, downloads, leaderboards

All planned.

| Method | Path | What it does |
|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&cursor=` | the Hub |
| GET | `/themes/{id}` | details, versions, maker |
| POST | `/themes` | start an upload → upload URL; `POST /themes/{id}/publish` after |
| POST | `/themes/{id}/versions` | a new version of your theme |
| POST / DELETE | `/themes/{id}/like` | |
| GET | `/releases/latest?product=launcher\|phone` | version, notes, URL, SHA-256 |
| GET | `/leaderboards/{board}?scope=global\|friends&period=all\|month\|week` | ranks, with yours |
| GET | `/games/{titleId}/leaderboard` | per game |

## 4.9 Limits

Per address and per account, counted in Valkey (built):

| What | Limit |
|---|---|
| Any request | 600 per minute per address, 300 per minute per account |
| Sign-in | 30 attempts per 15 minutes per address (codes asked and tried, providers, passkeys, hand-offs); email codes: 5 per hour per address, 10 wrong tries end the code |
| Token calls | 300 per 10 minutes per address (refreshes, device-code polls; a poll faster than every 4 s gets `slow_down`) |
| Messages | 30 per minute, 1000 per day |
| Friend requests | 50 per day |
| Searches | 120 per minute |
| Reports | 20 per day |
| Profile changes | 30 per hour; avatars 10 per hour, 5 MB each |
| Calls started | 60 per hour; game sessions opened: 120 per hour |
| Passkeys added | 20 per hour |
| Batches | 200 items |

Exceeding a limit gives `429` with `Retry-After`. On the gateway: 30 frames per 10 seconds, and
300 signals per 10 seconds for a call's setup.

## 4.10 Versioning

`/v1` stays compatible: fields are only added. A breaking change goes to `/v2`, and `/v1` keeps
working for at least six months after the launcher release that moved to `/v2`.
