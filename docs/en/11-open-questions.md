# 11. Open questions

The technologies and defaults in this plan are proposals, chosen so work can start; any of them
can change.

## Answered (2026-10-24)

| Question | Answer |
|---|---|
| The server | our own existing server (details kept out of this public plan); see [Infrastructure](09-infrastructure.md) |
| Stack | TypeScript is fine |
| Sign-in | one tap: Apple, Google, Discord, email code; no sign-up form, no password |
| Developer ID signing | yes: release builds of the macOS launcher get signed and notarized |
| Hostnames | one level under `kodla.agency` only: everything on `anytogether.kodla.agency` by path, plus `anytogether-cdn` and `anytogether-relay` |
| Windows and Linux | first-class: the Rust launcher gets every feature, through the `anytogether` crate |
| Media through our server? | no: voice, share play and pads go directly between players; our server introduces them and relays only when direct is impossible |

## Still open

| # | Question | Default in this plan | Needed by |
|---|---|---|---|
| 1 | **Server changes to approve**: the relay's ports, its DNS-only record on an address of its own, the databases, web traffic limited to Cloudflare's ranges | as listed in [Infrastructure](09-infrastructure.md) | Phase 0 (database), Phase 4 (relay) |
| 2 | **AnyPlay**: the Windows/Linux launcher's makers are designing their own network (Rust, accounts, friends, encrypted QUIC tunnels between players, a self-hostable cloud, and an engine bridge for games' own online modes). Build AnyTogether independently and offer them the `anytogether` crate, or work together (shared protocol, their bridge for game online play, our accounts/profiles/trophies)? | independent, with the crate and the phone protocol offered openly | before Phase 0 ends |
| 3 | **Repository**: a new `utkuhalis/AnyTogether`, private until launch? The Rust crate public from the start (so the Windows/Linux launcher can use it)? | private repo, public crate | Phase 0 |
| 4 | **Profile defaults**: public card with friends-only details, or fully private? | public card, friends-only details | Phase 1 |
| 5 | **Game and trophy icons** on public pages | shown, scaled down, removed on request | Phase 1 |
| 6 | **Messages**: server-readable at first (moderation possible) or end-to-end encrypted from day one? | server-readable, E2EE later | Phase 3 |
| 7 | **Push on iOS** needs the phone app built with your team (APNs); TestFlight or App Store later? | APNs with your team; TestFlight when ready | Phase 3 |
| 8 | **Big rooms**: add an SFU (LiveKit) later for parties over 8 talkers or share play to many viewers? | not at first | after Phase 5 |
| 9 | **Online play for games themselves** (each player runs the game, the engine's network calls carried between them): a later phase of our own, or AnyPlay's bridge (question 2)? | after Phase 6, decided with question 2 | later |
| 10 | **Moderators** besides you | you, then trusted community members | Phase 2 |
| 11 | **Legal texts** (terms, privacy policy, KVKK disclosure) | drafted here, reviewed by you | before public sign-ups |
| 12 | **Paid features** ever? | none planned | later |
