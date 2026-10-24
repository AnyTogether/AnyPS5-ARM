# 4. API

Base: `https://api.anytogether.kodla.agency/v1`. JSON in and out, UTF-8, times as RFC 3339 in UTC,
IDs as UUIDv7 strings (sortable by time). Errors are RFC 9457 problem details:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

Clients translate `code` into their own language (the launcher and the phone already carry
English and Turkish). The API publishes its OpenAPI 3.1 document at `/v1/openapi.json`; Swift and
Dart types are generated from it.

Every request from a client carries `AnyTogether-Client: launcher/0.2.13 (macOS 26.6; Mac15,9)`
(or `phone/1.10.0 (iOS 27.0)`, `web/…`). The API can refuse a client too old to be safe with
`426 Upgrade Required` and a `code` the launcher shows as "Update AnyPS5 to use AnyTogether".

## 4.1 Sign-in and sessions

Three ways in, one account:

1. **Email and password** (on the web and the phone): password hashed with Argon2id
   (m=64 MB, t=3, p=1); email verified with a 6-digit code before the account can be found by
   others.
2. **Sign in with Apple** and **Discord** (OAuth 2.0 / OpenID Connect) on the web and the phone;
   linked to an existing account by verified email or from settings.
3. **Device link** for the launcher (and TVs or anything without a keyboard): OAuth 2.0 Device
   Authorization Grant, RFC 8628. The launcher shows a code and a QR; the user confirms on the
   phone or the web. The phone app, already paired with the launcher over the local network, can
   confirm in one tap.

| Method | Path | What it does |
|---|---|---|
| POST | `/auth/register` | email, password, handle → sends a verification code |
| POST | `/auth/verify-email` | code → account verified |
| POST | `/auth/login` | email, password → tokens |
| POST | `/auth/oauth/{apple,discord}` | provider's code or ID token → tokens |
| POST | `/auth/device` | client, device name → `device_code`, `user_code`, `verification_uri`, `interval` |
| POST | `/auth/device/approve` | (signed in) `user_code` → approves that device |
| POST | `/auth/token` | `grant_type=device_code` or `refresh_token` → tokens |
| POST | `/auth/logout` | revokes this session |
| GET | `/auth/sessions` | the account's signed-in devices |
| DELETE | `/auth/sessions/{id}` | signs a device out |
| POST | `/auth/password/forgot`, `/auth/password/reset` | mail a code, set a new password |

**Tokens.** The access token is a JWT (EdDSA, 15 minutes) with the user ID, session ID and
scopes. The refresh token is a random 256-bit string, stored only as a SHA-256 hash, valid 60
days, **rotated on every use**; reusing an old one revokes the whole session (theft detection).
The launcher keeps the refresh token in the macOS Keychain; the phone in the iOS Keychain or
Android Keystore-backed storage; the web in an HttpOnly, Secure, SameSite=Lax cookie.

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

## 4.6 Parties, voice, share play

| Method | Path | What it does |
|---|---|---|
| POST | `/parties` | `{privacy}` → party (the asker is the owner) |
| GET | `/parties/{id}` | members, what they play, share play state |
| POST | `/parties/{id}/invites` | `{user_ids}` |
| POST | `/parties/{id}/join` / `leave` | |
| POST | `/parties/{id}/voice-token` | → LiveKit URL and room token (audio publish/subscribe) |
| POST | `/parties/{id}/share-play` | host starts sharing → token that may publish video; members get viewer tokens |
| POST | `/parties/{id}/share-play/controller` | `{user_id, slot}` hand a pad slot to a member, or take it back |
| DELETE | `/parties/{id}/share-play` | stop |

Room tokens carry the exact grants: viewers may subscribe and send data on the `pad` topic only
when the host gave them a slot; the token is reissued when the grant changes.

## 4.7 Realtime gateway

`wss://rt.anytogether.kodla.agency/v1/socket`. The client sends the access token in the first
frame (not in the URL, so it never lands in logs):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher/0.2.13", "resume": "<last event id>" }
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
| `share_play.started`, `share_play.controller_changed`, `share_play.stopped` | |
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
| Sign-in attempts | 10 per 15 min per account, 30 per IP |
| Messages | 30 per minute, 1000 per day |
| Friend requests | 50 per day |
| Uploads | avatar 5 MB, image 10 MB, theme 300 MB (the launcher's own limit) |
| Batches | 200 items, 1 MB |

Exceeding a limit gives `429` with `Retry-After`.

## 4.10 Versioning

`/v1` stays compatible: fields are only added. A breaking change goes to `/v2`, and `/v1` keeps
working for at least six months after the launcher release that moved to `/v2`.
