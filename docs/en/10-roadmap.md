# 10. Roadmap

Each phase ships something people can use, behind a switch in the launcher until it is solid.
"Done" means every check in its list passes, not "the code is written".

## Where it stands (2026-10-25)

The code is public and MIT licensed at
[github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether). "Released" means in
AnyPS5-ARM 0.2.15 (the macOS launcher), phone app 1.11.0 or AnyPS5 Desktop 0.1.1 (Windows and
Linux); the website is released as it is built.

| Phase | Status |
|---|---|
| 0 Foundations | **mostly built.** Repository, API, gateway, website, CI. Sign-in by email code or link, passkeys (web), phone hand-off, device code; Apple, Google and Discord checked by the API. Every client signs in (released). Left: provider buttons in the clients, the OpenAPI document, staging, backups to R2, the legal pages. |
| 1 Profile, library, trophies | **mostly built.** Profiles, handles, avatars, privacy; catalogue, sessions, library, trophy sets, rarity; both launchers send play time and trophies and show profiles; the phone edits your profile; web profiles. Left: showcase, profile theme, avatar checks, dates and rarity on the launcher's own trophy screen, Open Graph images. |
| 2 Friends, presence, feed, leaderboards | **built**: friends and presence everywhere; the activity feed with reactions and leaderboards on the web, the macOS launcher and the phone; finding players on the web (looking-for-group board, public parties and share plays, discovery, game hubs). Left: QR codes, comments, monthly and weekly boards, the feed and boards in AnyPS5 Desktop, finding players in the apps. |
| 3 Messages and push | **built** for text with groups and typing, everywhere; notifications with the bell everywhere, browser push and a mail digest. Left: images, reactions on messages, push to the phone. |
| 4 Parties and voice | **built**: parties, public parties, party voice and 1:1 calls with mute on the web, both launchers and the phone; push-to-talk in both launchers; relay support; **joining a friend's game** through game sessions (both launchers). Left: party chat, the phone as headset, call quality reports. |
| 5 Share play | **built**: the macOS launcher hosts; viewers on the web, the phone and the macOS launcher; the host hands pads 2-4 and keeps player 1; public listing and Live now. Left: hosting and watching in AnyPS5 Desktop, glass-to-glass measured over real networks, quality reports. |
| 6 Theme Hub, downloads, compatibility | **built**: the Theme Hub (the macOS launcher and the web, old launchers through the old index), the download page and releases API, the compatibility list with reports from the macOS launcher and the web. Left: profile themes, AnyPS5 Desktop's side, pad layouts and presets. |
| 7 Online play | **in design**: the engine bridge on AnyPS5-ARM's `online-play` branch; game sessions with player properties, signalling and relay credentials on the server built. |
| Running your own | **built**: Docker Compose and a self-hosting guide; every client can point at another server. |
| Moderation | **built**: reports on people, messages, themes and posts; the admin page and the command-line tool; a security review's fixes (see [Security](08-security-privacy.md)). |
| Windows and Linux | [AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) 0.1.1 (early preview): installers, the engine downloads itself, and AnyTogether's sign-in, friends, messages, parties and voice, sync, profiles and joining a friend's game. |

Testing: every client against one real stack (`e2e/`): sign-in, friends, messages, parties, calls,
sync and game sessions passed on 2026-10-24 (see [Clients](07-clients.md) 7.0).

## The plan

The original plan, made before the work started (the order still held; phases 0 to 6 were built
well ahead of these dates):

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
- [x] Feed shows one folded item for five trophies in an hour (test).

## Phase 3: Messages and push (≈3 weeks)

- Direct and group conversations, attachments, read state, typing, reports.
- Push for the phone (APNs, FCM); toasts in the launcher that do not take focus from a game.

**Done when**
- [ ] A message sent from the web arrives in the launcher under 1 s and on a locked phone as a
      push under 5 s.
- [x] Killing the network mid-send and resending never duplicates a message (test).
- [x] Unread counts agree on all doors (the cross-client run).

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

- Viewers see and hear the host's game; the host can hand up to three of them a pad, as player 2,
  3 or 4, and take it back at any time. The host's player 1 is never handed over.
- Every launcher hosts: macOS from Remote Play's capture with WebRTC's H.264 (built), Windows and
  Linux from their own capture and hardware encoders (planned); direct to each viewer, relay if
  needed; viewers on phone, web, any launcher; quality steps; the link shown to both sides.

**Done when**
- [ ] A friend 500 km away watches 720p60 with glass-to-glass under 120 ms (median), with a Mac as
      host and with a Windows PC as host.
- [x] A viewer's pad reaches the host's game only while the host lets them play, and never as
      player 1 (test).
- [ ] A weak network steps down without freezing for more than 500 ms.

## Phase 6: Theme Hub, downloads, compatibility (≈3 weeks, beside 3-5)

- Theme upload from the launcher, review after reports, likes, versions; the launcher's Themes
  screen reads the API (GitHub folder kept as fallback); profile themes (planned).
- Downloads page from the latest GitHub releases with their checksums; `GET /releases/latest`.
- Compatibility reports (opt-in) and verdicts on the list, game hubs and in the launcher's game
  info.
- Later on the same shelf: phone pad layouts, per-game presets, shared shader caches.

**Done when**
- [x] A theme shared from the launcher is installable by another user at once (it is published
      when it passes the checks).
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
- AnyTogether: game sessions with the version guard, each player's properties, signalling between
  the players and relay credentials (built); a session key (planned).

**Done when**
- [ ] Two copies of a game built only on platform services play together on one Mac, then on two
      Macs on one network, then on two networks through the relay.
- [ ] A different game version or engine build is refused with a reason on both sides.
- [ ] Nothing ever goes to Sony or stands in for a publisher's servers (review of the
      observation logs).

## After

- End-to-end encrypted direct messages and voice; App Store / Play Store releases of
  the phone app; tournaments and challenges on leaderboards; share play to many viewers through an
  SFU; a public API for community tools.
