# 10. Roadmap

Each phase ships something people can use, behind a switch in the launcher until it is solid.
"Done" means every check in its list passes, not "the code is written".

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
```

Dates are a guide for one developer working with Claude; phase 6 can run beside 3-5.

## Phase 0: Foundations (≈3 weeks)

**Ships**: the repository, the server, sign-in, and the launcher signed in.

- AnyTogether monorepo (apps/api, realtime, worker, web; packages/shared, db), CI, staging.
- Server set up with Docker Compose, Cloudflare DNS and certificates, backups, Uptime Kuma.
- Accounts: email/password with verification, Sign in with Apple, Discord; sessions; refresh
  rotation; device link (RFC 8628) with the web `/link` page.
- Realtime gateway with hello, heartbeats, resume (no features on it yet).
- Launcher: `TogetherClient`, `TogetherAuth`, `TogetherSocket`, Settings → AnyTogether →
  Sign in (code + QR), signed-in chip in the top bar.
- Website: landing page replacing "Coming soon", sign up/in, `/link`, settings, privacy pages.

**Done when**
- [ ] A new user signs up on the web, signs the launcher in by code, sees their name in the
      launcher; signing out on the web signs the launcher out within 5 s.
- [ ] The launcher with the server unreachable behaves exactly as 0.2.12 (automated test).
- [ ] Backups restore on staging; the restore test is green.
- [ ] Refresh-token reuse revokes the session (test).

## Phase 1: Profile, game library, trophies (≈4 weeks)

**Ships**: your gamer card, your games and trophies online.

- Profiles, handles, avatars (R2 + worker resizing + nudity check), showcase, privacy settings.
- Game catalogue, sessions (launcher `SessionRecorder` + outbox), library with play time.
- Trophy sets and earned trophies (launcher `TrophySync`), rarity job, points.
- Launcher: profile overlay, dates and rarity on the trophy screen and banner, play time from all
  Macs. Phone: profile card. Web: `/u/<handle>`, games, trophies pages with Open Graph images.

**Done when**
- [ ] Playing Silksong for 10 minutes and earning a trophy shows both on the web profile within
      30 s; offline, they appear after the launcher reconnects, once.
- [ ] Two Macs on one account add up play time correctly.
- [ ] Rarity of a trophy matches a hand count on staging data.
- [ ] Hidden trophies stay hidden to users who have not earned them.

## Phase 2: Friends, presence, activity feed, leaderboards (≈3 weeks)

- Friend requests (handle, QR), blocks, presence with games, feed with folding, likes and
  comments, leaderboards (friends and global, per game).
- Launcher: Friends panel, online count, feed panel, "friends playing" on the game page.
  Phone: Friends and Feed tabs. Web: friends, feed, leaderboards.

**Done when**
- [ ] Starting a game shows "playing X" on a friend's launcher within 3 s; closing it within 60 s
      at most (expiry) and usually at once.
- [ ] "Appear offline" and blocks hide presence completely (test).
- [ ] Feed shows one folded item for five trophies in an hour.

## Phase 3: Messages and push (≈3 weeks)

- Direct and group conversations, attachments, read state, typing, reports.
- Push for the phone (APNs, FCM); toasts in the launcher that do not take focus from a game.

**Done when**
- [ ] A message sent from the web arrives in the launcher under 1 s and on a locked phone as a
      push under 5 s.
- [ ] Killing the network mid-send and resending never duplicates a message (test).
- [ ] Unread counts agree on all three doors.

## Phase 4: Parties and voice (≈4 weeks)

- LiveKit and TURN on the server; party lifecycle; room tokens; voice in launcher (Swift SDK),
  phone (Flutter SDK), web; push-to-talk; the phone as headset; party chat; "Play the same game".

**Done when**
- [ ] Four people (Mac, iPhone, Android, browser) talk for 30 minutes with no drop, mouth-to-ear
      under 200 ms within Türkiye/Europe (measured).
- [ ] A game in front keeps voice going; the party overlay shows who speaks.
- [ ] A user behind a UDP-blocking network joins through TURN/TLS.

## Phase 5: Share play (≈5 weeks)

- Launcher publishes `RemotePlay` capture and `StreamEncoder` frames to LiveKit; direct
  peer-to-peer first; viewers on phone, web, launcher; pad over data channel into a remote pad
  bridge; take over player 1; quality steps; latency badge.

**Done when**
- [ ] A friend 500 km away watches 720p60 with glass-to-glass under 120 ms (median) and plays as
      player 2 with input round trip under 80 ms.
- [ ] The host takes player 1 back with PS at once.
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

## After

- Passkeys; end-to-end encrypted direct messages and voice; App Store / Play Store releases of
  the phone app; tournaments and challenges on leaderboards; spectating public share play for
  friends of friends; a public API for community tools.
