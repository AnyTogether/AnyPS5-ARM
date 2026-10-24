# 10. Roadmap

Each phase ships something people can use, behind a switch in the launcher until it is solid.
"Done" means every check in its list passes, not "the code is written".

## Where it stands (2026-10-24)

The code is public and MIT licensed at
[github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether). "Released" means in
AnyPS5-ARM v0.2.13-arm (phone app 1.9.1); "next release" means on AnyPS5-ARM's `main`, not yet
released.

| Phase | Status |
|---|---|
| 0 Foundations | **mostly built.** Repository, API, gateway, website, CI. Sign-in by email code or link, passkeys (web), phone hand-off, device code; Apple, Google and Discord checked by the API. The macOS launcher and the phone sign in (released). Left: provider buttons in the clients, the OpenAPI document, staging, backups to R2, the legal pages. |
| 1 Profile, library, trophies | **mostly built.** Profiles, handles, avatars, privacy; catalogue, sessions, library, trophy sets, rarity; the launcher sends play time and trophies (released) and shows profiles (next release); web profiles. Left: showcase, profile theme, avatar checks, dates and rarity on the launcher's trophy screen, Open Graph images. |
| 2 Friends, presence, feed, leaderboards | **friends and presence built** (web; launcher released; phone next release). Left: QR codes, the feed, leaderboards. |
| 3 Messages and push | **messages built** for text (web; launcher and phone next release). Left: images, reactions, typing, push notifications. |
| 4 Parties and voice | **built**: parties, calls, peer-to-peer voice on the web, in the launcher and on the phone (next release), push-to-talk on macOS, relay support; and **joining a friend's game** through game sessions (launcher, next release). Left: party chat, the phone as headset, call quality reports. |
| 5 Share play | planned, **watch only**. |
| 6 Theme Hub, downloads, compatibility | planned. |
| 7 Online play | **in design**: the engine bridge on AnyPS5-ARM's `online-play` branch; game sessions on the server built. |
| Running your own | **built**: Docker Compose and a self-hosting guide; the launcher and the phone can point at another server (next release). |
| Windows and Linux | [AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) is public and in development; its AnyTogether part is planned. |

## The plan

The original plan, made before the work started (the order still holds; most of phases 0 to 4
was built well ahead of these dates):

```mermaid
gantt
    dateFormat YYYY-MM-DD
    axisFormat %b
    section Base
    0 Foundations           :p0, 2026-11-01, 3w
    section Me
    1 Profile, library, trophies :p1, after p0, 4w
    section Together
    2 Friends, presence, feed, leaderboards :p2, after p1, 3w
    3 Messages and push     :p3, after p2, 3w
    4 Parties and voice     :p4, after p3, 4w
    5 Share play            :p5, after p4, 5w
    section Shelf
    6 Theme Hub, downloads, compatibility :p6, after p2, 3w
    section Online
    7 Online play         :p7, after p4, 6w
```

Dates are a guide for one developer working with Claude on the server, the macOS launcher and
the phone app; AnyPS5-Desktop connects the Windows/Linux launcher itself, from the same API and
protocols. Phase 6 can run beside 3-5.

## Phase 0: Foundations (≈3 weeks)

**Ships**: the repository, the server, one-tap sign-in, and every launcher signed in.

- AnyTogether monorepo (apps/api, realtime, worker, web; packages/shared, db), CI, staging.
- On our server: the apps (web, api, realtime, worker), PostgreSQL and Valkey,
  memory limits, backups to R2, the `/api` and `/rt` routes on `anytogether.kodla.agency`.
- Sign-in: Apple, Google, Discord (OpenID Connect + PKCE), email codes, passkeys, phone hand-off,
  device code fallback; the first sign-in creates the account; sessions; refresh rotation.
- Realtime gateway with hello, heartbeats, resume (no features on it yet).
- macOS launcher: `TogetherClient`, `TogetherAuth`, `TogetherSocket`, Settings → AnyTogether →
  Continue with Apple / Google / Discord / phone / email, signed-in chip in the top bar.
- The OpenAPI document and the gateway protocol published, versioned, so any launcher
  (AnyPS5-Desktop first) can connect without our help. The code itself is public.
- macOS launcher release builds signed with Developer ID and notarized.
- Website: landing page replacing "Coming soon", one-tap sign-in, `/link`, settings, privacy pages.

**Done when**
- [ ] A new user taps "Continue with Google" in the launcher and is signed in, with an account
      created, in one tap (already signed in to Google in the browser); signing out on the web
      signs the launcher out within 5 s.
- [x] The phone, signed in, signs the launcher in with one tap.
- [ ] The published OpenAPI document validates and matches the running API (CI).
- [ ] A launcher with the server unreachable behaves exactly as before AnyTogether (automated test).
- [ ] Backups restore on staging; the restore test is green.
- [x] Refresh-token reuse revokes the session (test).

## Phase 1: Profile, game library, trophies (≈4 weeks)

**Ships**: your gamer card, your games and trophies online.

- Profiles, handles, avatars (R2 + worker resizing + nudity check), showcase, privacy settings.
- Game catalogue, sessions (launcher `SessionRecorder` + outbox), library with play time.
- Trophy sets and earned trophies (launcher `TrophySync`), rarity job, points.
- Launcher: profile overlay, dates and rarity on the trophy screen and banner, play time from all
  computers. Phone: profile card. Web: `/u/<handle>`, games, trophies pages with Open Graph images.

**Done when**
- [ ] Playing Silksong for 10 minutes and earning a trophy shows both on the web profile within
      30 s; offline, they appear after the launcher reconnects, once.
- [ ] Two computers on one account (a Mac and a Windows PC) add up play time correctly.
- [ ] Rarity of a trophy matches a hand count on staging data.
- [x] Hidden trophies stay hidden to users who have not earned them (test).

## Phase 2: Friends, presence, activity feed, leaderboards (≈3 weeks)

- Friend requests (handle, QR), blocks, presence with games, feed with folding, likes and
  comments, leaderboards (friends and global, per game).
- Launcher: Friends panel, online count, feed panel, "friends playing" on the game page.
  Phone: Friends and Feed tabs. Web: friends, feed, leaderboards.

**Done when**
- [ ] Starting a game shows "playing X" on a friend's launcher within 3 s; closing it within 60 s
      at most (expiry) and usually at once.
- [x] Presence set to "nobody" and blocks hide presence completely (test).
- [ ] Feed shows one folded item for five trophies in an hour.

## Phase 3: Messages and push (≈3 weeks)

- Direct and group conversations, attachments, read state, typing, reports.
- Push for the phone (APNs, FCM); toasts in the launcher that do not take focus from a game.

**Done when**
- [ ] A message sent from the web arrives in the launcher under 1 s and on a locked phone as a
      push under 5 s.
- [x] Killing the network mid-send and resending never duplicates a message (test).
- [ ] Unread counts agree on all three doors.

## Phase 4: Parties and voice (≈4 weeks)

- coturn on the server (`anytogether-relay.kodla.agency`, ports 3478, 5349, relay range opened
  with Utku's approval); calls and signalling over the gateway; peer-to-peer voice in every
  launcher (the macOS WebRTC framework; the Windows/Linux port with its own WebRTC library), the phone (`flutter_webrtc`) and
  the web; push-to-talk; the phone as headset; party chat; joining a friend's game through game
  sessions, checked against the game version and engine build.

**Done when**
- [ ] Five people (Mac, Windows PC, Linux, iPhone, browser) talk for 30 minutes with no drop,
      mouth-to-ear under 200 ms within Türkiye/Europe (measured).
- [ ] Most calls connect directly; the quality reports show the share that needed the relay.
- [ ] A game in front keeps voice going; the party overlay shows who speaks.
- [ ] A user behind a UDP-blocking network joins through TURN/TLS.
- [x] A friend joins the host's game only with the same game version and engine build (test).

## Phase 5: Share play (≈5 weeks)

- **Watch only**: viewers see and hear, and control never passes to them.
- Every launcher hosts: macOS from `RemotePlay`'s capture and low-latency H.264, Windows and
  Linux from their own capture and hardware encoders; direct to each viewer, relay if needed;
  viewers on phone, web, any launcher; quality steps; latency badge.

**Done when**
- [ ] A friend 500 km away watches 720p60 with glass-to-glass under 120 ms (median), with a Mac as
      host and with a Windows PC as host.
- [ ] Nothing a viewer sends reaches the host's game (test).
- [ ] A weak network steps down without freezing for more than 500 ms.

## Phase 6: Theme Hub, downloads, compatibility (≈3 weeks, beside 3-5)

- Theme upload from the Studio, moderation queue, likes, versions; launcher's Themes screen reads
  the API (GitHub folder kept as fallback); profile themes.
- Downloads page with mirrored releases and checksums; `GET /releases/latest`.
- Compatibility reports (opt-in) and verdicts on game pages and in the launcher's library.
- Later on the same shelf: phone pad layouts, per-game presets, shared shader caches.

**Done when**
- [ ] A theme made in the Studio is installable by another user 1 minute after it is approved.
- [ ] Downloads match GitHub releases byte for byte (checksum test in CI).
- [ ] Turning compatibility reports off sends nothing (test).

## Phase 7: Online play (in design)

Each player runs the game on their own computer and the copies play together, as they would over
PlayStation Network, through AnyTogether. Design:
[ONLINE_PLAY.md](https://github.com/utkuhalis/AnyPS5-ARM/blob/online-play/docs/dev/ONLINE_PLAY.md)
on AnyPS5-ARM's `online-play` branch; summary in [Realtime](06-realtime-voice-shareplay.md) 6.7.

- Engine: the authenticated loopback bridge, the observation log, sign-in state and Plus checks,
  web API pass-through, datagram traffic at virtual addresses (built and tested against a fake
  launcher); push events, session signalling, streams, join intents (planned).
- Launcher: the bridge's other end, the `anyps5` API group mapped onto game sessions, the first
  peer link (plain UDP with an HMAC per packet), off by default (built on the branch); WebRTC data
  channels or QUIC with the relay (planned).
- AnyTogether: game sessions with the version guard (built); the players' endpoints and a session
  key, session signalling (planned).

**Done when**
- [ ] Two copies of a game built only on platform services play together on one Mac, then on two
      Macs on one network, then on two networks through the relay.
- [ ] A different game version or engine build is refused with a reason on both sides.
- [ ] Nothing ever goes to Sony or stands in for a publisher's servers (review of the
      observation logs).

## After

- End-to-end encrypted direct messages and voice; App Store / Play Store releases of
  the phone app; tournaments and challenges on leaderboards; spectating public share play for
  friends of friends; a public API for community tools.
