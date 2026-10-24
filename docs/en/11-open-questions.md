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
| Windows and Linux | first-class: the server and its contracts are the same for every platform; the Windows/Linux launcher's maintainer connects it when porting, from the documented API and protocols |
| AnyTogether and AnyPlay | AnyTogether is ours, built independently; the Windows/Linux launcher connects to it when porting |
| Media through our server? | no: voice, share play and pads go directly between players; our server introduces them and relays only when direct is impossible |

## Still open

| # | Question | Default in this plan | Needed by |
|---|---|---|---|
| 1 | **Server changes to approve**: the relay's ports, its DNS-only record on an address of its own, the databases, web traffic limited to Cloudflare's ranges | as listed in [Infrastructure](09-infrastructure.md) | Phase 0 (database), Phase 4 (relay) |
| 2 | **Repository**: `utkuhalis/AnyTogether`, private until launch; the OpenAPI document and the protocol documents public, so other launchers can connect | private repo, public contracts | Phase 0 |
| 3 | **Profile defaults**: public card with friends-only details, or fully private? | public card, friends-only details | Phase 1 |
| 4 | **Game and trophy icons** on public pages | shown, scaled down, removed on request | Phase 1 |
| 5 | **Messages**: server-readable at first (moderation possible) or end-to-end encrypted from day one? | server-readable, E2EE later | Phase 3 |
| 6 | **Push on iOS** needs the phone app built with your team (APNs); TestFlight or App Store later? | APNs with your team; TestFlight when ready | Phase 3 |
| 7 | **Big rooms**: add an SFU (LiveKit) later for parties over 8 talkers or share play to many viewers? | not at first | after Phase 5 |
| 8 | **Online play for games themselves** (each player runs the game, the engine's network calls carried between them): a later phase of our own? | after Phase 6 | later |
| 9 | **Moderators** besides you | you, then trusted community members | Phase 2 |
| 10 | **Legal texts** (terms, privacy policy, KVKK disclosure) | drafted here, reviewed by you | before public sign-ups |
| 11 | **Paid features** ever? | none planned | later |
