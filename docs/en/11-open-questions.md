# 11. Open questions

The technologies and defaults in this plan are proposals, chosen so work can start; any of them
can change.

## Answered

| Question | Answer |
|---|---|
| The server | our own existing server (details kept out of this public plan); see [Infrastructure](09-infrastructure.md) |
| Stack | TypeScript is fine |
| Sign-in | one tap: email code, passkey, the phone, Apple, Google, Discord; no sign-up form, no password |
| Developer ID signing | yes: release builds of the macOS launcher get signed and notarized |
| Hostnames | one level under `kodla.agency` only: everything on `anytogether.kodla.agency` by path, plus `anytogether-cdn` and `anytogether-relay` |
| **Repository** | **public, MIT licensed**: [github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether), with a self-hosting guide so anyone can run their own; the launcher and the phone can point at another server |
| Windows and Linux | first-class: the server and its contracts are the same for every platform. The Windows/Linux launcher is [AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), a public project that connects to AnyTogether itself (0.1.1 released, with installers and an engine that downloads itself) |
| Licence | **MIT** for AnyTogether (the launchers stay GPL-2.0, like the engine) |
| Push on the web | Web Push with the server's own VAPID keys, no outside service; off on a server without keys |
| Strangers playing together | yes, by choice: the looking-for-group board and public parties and share plays (off unless the host lists them), with lower limits for new accounts and reports on posts; messages stay between friends |
| AnyTogether and AnyPlay | AnyTogether is ours, built independently. Online play uses our own engine bridge; we read AnyPlay's public design and copied no code |
| Media through our server? | no: voice, share play and online game traffic go directly between players; our server introduces them and relays only when direct is impossible |
| **Share play** | **watch, and play along**: friends see and hear the host's game, and the host can invite viewers to play as **player 2, 3 or 4** with their own pad (decided after the first plan, which said watch only). The host never hands over player 1, and only the host hands out pads. Each player running their own copy is online play |
| Online play for games themselves | yes, our own phase (7): the engine hands the game's platform calls to the launcher, which carries them through AnyTogether; designed on AnyPS5-ARM's `online-play` branch ([Realtime](06-realtime-voice-shareplay.md) 6.7) |
| **PlayStation Plus checks** in online play | **answered "allowed"** while the launcher reports a user signed in to AnyTogether (`sceNpCheckPlus` and the premium checks; `sceNpIsPlusMember` reports a member); signed out, they answer as before. Online play is the point of signing in |

## Still open

| # | Question | Default in this plan | Needed by |
|---|---|---|---|
| 1 | **Server changes to approve**: the relay's ports, its DNS-only record on an address of its own, web traffic limited to Cloudflare's ranges | as listed in [Infrastructure](09-infrastructure.md) | the relay going live |
| 2 | **Profile defaults**: public card with friends-only details, or fully private? | public card; games, trophies, friends list and presence for friends; found in search by everyone (built this way) | before public sign-ups |
| 3 | **Game and trophy icons** on public pages | shown, scaled down, removed on request (not stored yet) | game pages |
| 4 | **Messages**: server-readable (moderation possible) or end-to-end encrypted? | server-readable now (built this way, reported messages kept for moderators), E2EE later | later |
| 5 | **Push on iOS** needs the phone app built with your team (APNs); TestFlight or App Store later? | APNs with your team; TestFlight when ready | push notifications |
| 6 | **Big rooms**: add an SFU (LiveKit) later for parties over 8 talkers or share play to more than 4 viewers? | not at first | when share plays fill up |
| 7 | **Moderators** besides you | you, then trusted community members | before public sign-ups |
| 8 | **Legal texts** (terms, privacy policy, KVKK disclosure) | drafted here, reviewed by you | before public sign-ups |
| 9 | **Paid features** ever? | none planned | later |
| 10 | **The relay for strangers**: should connections with people who are not friends (public share plays, the looking-for-group board) go through the relay by default, so neither side sees the other's IP address? | direct, with an "Always use the relay" setting (planned) | before finding players is in the apps |
| 11 | **Share play's game sound**: keep Remote Play's PCM on a data channel (no encoding delay, ~1.5 Mbit/s) or move to an Opus track (~128 kbit/s)? | PCM (built this way) | when hosts on slow uploads complain |
