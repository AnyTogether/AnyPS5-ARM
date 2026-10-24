# 4. API

Base: `https://anytogether.kodla.agency/api/v1` (one hostname for everything; see [Architecture](02-architecture.md)). JSON in and out, UTF-8, times as RFC 3339 in UTC,
IDs as UUIDv7 strings (sortable by time). Errors are RFC 9457 problem details:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

Clients translate `code` into their own language (the launcher and the phone already carry
English and Turkish). The API publishes its OpenAPI 3.1 document at `/api/v1/openapi.json`; Swift,
Rust, Dart and TypeScript types are generated from it.

Every request from a client carries `AnyTogether-Client`, naming the client and platform:
`launcher-macos/0.2.13 (macOS 26.6; Mac15,9)`, `launcher-windows/0.3.0 (Windows 11 24H2)`,
`launcher-linux/0.3.0 (Fedora 41; KDE)`, `phone/1.10.0 (iOS 27.0)`, `web/…`. The API can refuse a client too old to be safe with
`426 Upgrade Required` and a `code` the launcher shows as "Update AnyPS5 to use AnyTogether".

## 4.1 Sign-in: one tap, no registration form

There is **no sign-up step and no password**. The first sign-in creates the account; the handle
and display name are taken from the provider (editable later); the avatar too, if the provider
has one.

| Way in | Where | What the user does |
|---|---|---|
| **Continue with Apple** | macOS launcher (native sheet, Touch ID), iPhone (native), web | one tap |
| **Continue with Google** | every launcher (system browser), Android (native Credential Manager), web | one tap if already signed in to Google |
| **Continue with Discord** | every launcher (system browser), phone, web | one tap if already signed in to Discord |
| **Email code** | everywhere | type the email, then the 6-digit code from the mail (or click the link in it); nothing to remember |
| **From the phone** | any launcher whose phone app is paired and signed in | the launcher asks, the phone shows "Sign in <Mac/PC name>?", one tap |
| **Device code** (fallback) | a launcher with no browser at hand | the launcher shows a code and a QR; approve on the phone or the web |
| Passkeys (later) | everywhere | Touch ID / Windows Hello / phone |

**How the launchers do it**: OAuth 2.0 with PKCE in the system browser, as RFC 8252 asks for native
apps. macOS uses `ASWebAuthenticationSession` (a sheet that shares the browser's sign-ins, so Google
or Discord is usually one click) and `ASAuthorizationAppleIDProvider` for Apple; Windows and Linux
open the default browser and receive the result on a loopback redirect
(`http://127.0.0.1:<random port>/callback`). The phone uses the native Apple, Google and Discord
flows. All of them end at our API, which verifies the provider's ID token (OpenID Connect) and
issues our own tokens.

| Method | Path | What it does |
|---|---|---|
| GET | `/auth/providers` | the ways in this client may offer |
| POST | `/auth/oidc/{apple,google,discord}` | provider's code (with PKCE verifier) or ID token → tokens; creates the account on first use |
| POST | `/auth/email/start` | email → sends a 6-digit code and a magic link (valid 10 min) |
| POST | `/auth/email/verify` | email + code (or the link's token) → tokens |
| POST | `/auth/handoff/start` | (launcher) device name → a handoff ID, pushed to the user's signed-in phones |
| POST | `/auth/handoff/{id}/approve` | (phone, signed in) → approves; the launcher's poll gets tokens |
| POST | `/auth/device` | (fallback) → `device_code`, `user_code`, `verification_uri`, `interval` (RFC 8628) |
| POST | `/auth/device/approve` | (signed in) `user_code` → approves |
| POST | `/auth/token` | `grant_type=refresh_token`, `device_code` or `handoff` → tokens |
| POST | `/auth/logout` | revokes this session |
| GET / DELETE | `/auth/sessions`, `/auth/sessions/{id}` | the signed-in devices; sign one out |
| POST | `/me/identities/{provider}` | link another way in (Apple + Discord on one account) |

**Tokens.** Access token: a JWT (EdDSA, 15 minutes) with the user, the session and the scopes.
Refresh token: 256 random bits, stored only as a SHA-256 hash, valid 90 days and **rotated on every
use**; reusing an old one revokes the session. Kept in the platform's secure store: macOS Keychain,
Windows Credential Manager, the Secret Service on Linux (GNOME Keyring, KWallet), iOS Keychain,
Android Keystore; the web in an HttpOnly, Secure, SameSite=Lax cookie.

## 4.2 Me, profiles and settings

| Method | Path | What it does |
|---|---|---|
| GET | `/me` | account, profile, settings, counts |
| PATCH | `/me/profile` | display name, bio, country, showcase, profile theme |
| PATCH | `/me/handle` | new handle (once per 30 days) |
| POST | `/me/avatar` | → presigned R2 upload URL; then `PUT` the file; then `POST /me/avatar/confirm` |
| PATCH | `/me/privacy` | visibility per item (see Features 3.5) |
| PATCH | `/me/notifications` | which push and mail notifications |
| POST | `/me/export` | queue a full data export (zip by mail link), KVKK/GDPR |
| DELETE | `/me` | delete the account (14 days to change your mind) |
| GET | `/users/{handle}` | a profile, as the asker may see it |
| GET | `/users/search?q=` | find users by handle or name (trigram), verified accounts only |

## 4.3 Games, sessions and trophies

| Method | Path | What it does |
|---|---|---|
| PUT | `/games/{title_id}` | teach the catalogue a game: names per language, icon upload URL (only if unknown or the asker is trusted) |
| GET | `/games/{title_id}` | catalogue entry, community compatibility, rarity summary |
| POST | `/me/sessions` | batch of sessions `{id, title_id, mac_id, started_at, ended_at, exit}` |
| GET | `/users/{handle}/library` | games, play time, last played, progress |
| PUT | `/trophy-sets/{title_id}/{set_hash}` | the trophy set: IDs, grades, hidden flags, names/descriptions per language, icon upload URLs |
| POST | `/me/trophies` | batch `{title_id, set_hash, trophy_id, earned_at}`; repeats are ignored |
| GET | `/users/{handle}/trophies?title_id=` | earned trophies with dates and rarity |
| POST | `/games/{title_id}/reports` | compatibility report (opt-in), see Features 3.7 |

**Batching and idempotency.** The launcher's outbox sends batches of up to 200 items. Each item
carries a client-made UUIDv7; the server stores it and ignores a second copy, so a batch can be
resent after a timeout without double counting. The response lists per item `stored`,
`duplicate` or `rejected` with a code.

## 4.4 Friends, presence, activity

| Method | Path | What it does |
|---|---|---|
| GET | `/me/friends` | friends with presence |
| POST | `/me/friends/requests` | `{handle}` or `{qr_token}` → request |
| GET | `/me/friends/requests` | incoming and outgoing |
| POST | `/me/friends/requests/{id}/accept` / `decline` | |
| DELETE | `/me/friends/{user_id}` | unfriend |
| POST | `/me/blocks` / DELETE `/me/blocks/{user_id}` | block, unblock |
| GET | `/me/feed?before=` | friends' activity, newest first, 30 per page |
| POST | `/activities/{id}/like` / DELETE | |
| POST | `/activities/{id}/comments` | |
| GET | `/me/qr` | a short-lived token for the add-friend QR |

Presence is not set over REST; it travels over the realtime socket (4.7).

## 4.5 Messages

| Method | Path | What it does |
|---|---|---|
| GET | `/me/conversations` | conversations with last message and unread count |
| POST | `/conversations` | `{members: [...], title?}` → direct (2 people, reused) or group |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | history, by message sequence |
| POST | `/conversations/{id}/messages` | `{client_id, text?, attachments?, reply_to?}` |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | edit (15 min) or delete your message |
| POST | `/conversations/{id}/read` | `{up_to_seq}` |
| POST | `/conversations/{id}/attachments` | → presigned upload URL |
| POST | `/messages/{id}/report` | |

## 4.6 Parties, calls, share play

Voice and share play are peer-to-peer (see [Realtime](06-realtime-voice-shareplay.md)); the API
only sets calls up and hands out relay credentials.

| Method | Path | What it does |
|---|---|---|
| POST | `/parties` | `{privacy}` → party (the asker is the owner) |
| GET | `/parties/{id}` | members, what they play, call and share play state |
| POST | `/parties/{id}/invites` | `{user_ids}` |
| POST | `/parties/{id}/join` / `leave` | |
| POST | `/calls` | `{party_id}` or `{user_id}` → call ID, ICE servers (STUN, TURN with credentials valid 12 h) |
| GET | `/ice-servers` | fresh TURN credentials for a running call |
| POST | `/calls/{id}/share-play` | the host starts sharing; members are told |
| POST | `/calls/{id}/share-play/controller` | `{user_id, slot}` hand a pad slot to a member, or take it back |
| DELETE | `/calls/{id}/share-play` | stop sharing |
| POST | `/calls/{id}/quality` | the client's report at the end: direct or relayed, round trip, loss, glass-to-glass samples |

The offers, answers and ICE candidates themselves travel over the gateway (`signal`, 4.7).

## 4.7 Realtime gateway

`wss://anytogether.kodla.agency/rt`. The client sends the access token in the first
frame (not in the URL, so it never lands in logs):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher-windows/0.3.0", "resume": "<last event id>" }
```

The server answers `{"op":"ready","session":"…","heartbeat":25}` and then sends events:

```json
{ "op": "event", "id": "01J…", "type": "message.created", "data": { … } }
```

The client sends `{"op":"heartbeat","presence":{"state":"in_game","title_id":"PPSA01234","since":"…"}}`
every 25 s (and at once when presence changes). Missing two heartbeats closes the socket and the
presence expires. On reconnect, `resume` with the last event ID replays what was missed in the
last 5 minutes (kept in a Valkey stream per user); older gaps are filled with REST calls.

| Event | When |
|---|---|
| `presence.updated` | a friend's state or game changed |
| `friend.request`, `friend.accepted`, `friend.removed` | |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `typing` | |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | |
| `call.ringing`, `call.answered`, `call.ended` | a call to you, answered on another device, over |
| `signal` | WebRTC offer, answer, ICE candidate or bye from a call peer (relayed, never stored) |
| `share_play.started`, `share_play.controller_changed`, `share_play.stopped` | |
| `auth.handoff` | (phone) a launcher asks to be signed in |
| `activity.created` | a friend's activity for the feed |
| `trophy.rarity_changed` | a trophy you own crossed a rarity label |
| `account.signed_out` | this session was revoked elsewhere |

## 4.8 Themes, downloads, leaderboards

| Method | Path | What it does |
|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&cursor=` | the Hub |
| GET | `/themes/{id}` | details, versions, maker |
| POST | `/themes` | start an upload → presigned URL; `POST /themes/{id}/publish` after |
| POST | `/themes/{id}/versions` | a new version of your theme |
| POST / DELETE | `/themes/{id}/like` | |
| GET | `/releases/latest?product=launcher\|phone` | version, notes, URL, SHA-256 |
| GET | `/leaderboards/{board}?scope=global\|friends&period=all\|month\|week` | ranks, with yours |
| GET | `/games/{title_id}/leaderboard` | per game |

## 4.9 Limits

Per account (and per IP at Cloudflare for unauthenticated calls):

| What | Limit |
|---|---|
| Sign-in attempts | email codes: 5 sends per hour per address, 10 wrong codes lock it for 15 min; 30 attempts per IP |
| Messages | 30 per minute, 1000 per day |
| Friend requests | 50 per day |
| Uploads | avatar 5 MB, image 10 MB, theme 300 MB (the launcher's own limit) |
| Batches | 200 items, 1 MB |

Exceeding a limit gives `429` with `Retry-After`.

## 4.10 Versioning

`/v1` stays compatible: fields are only added. A breaking change goes to `/v2`, and `/v1` keeps
working for at least six months after the launcher release that moved to `/v2`.
