# 11. Open questions

Decisions this plan made on its own are marked **(proposed)** in the documents; these are the
ones that need an answer before or during the phase named.

| # | Question | Default in this plan | Needed by |
|---|---|---|---|
| 1 | **The server**: which machine, where (city), how much CPU/RAM/bandwidth, what already runs on it? | One 4 vCPU / 16 GB machine in Istanbul or Frankfurt, Docker Compose | Phase 0 |
| 2 | **Stack**: is TypeScript (Hono, Next.js) fine, or does kodla.agency already use something it would rather keep? | TypeScript | Phase 0 |
| 3 | **Sign-in methods** at launch: email + Apple + Discord? Google too? | email, Apple, Discord | Phase 0 |
| 4 | **Repository**: a new `utkuhalis/AnyTogether` (private or public)? | new repository, private until launch | Phase 0 |
| 5 | **Signing the launcher with Developer ID** so microphone and screen recording permissions survive updates (they are lost at every ad-hoc-signed update today) | needed before voice | Phase 4 (better: Phase 0) |
| 6 | **Profile defaults**: public profile with friends-only details (this plan), or fully private by default? | public card, friends-only details | Phase 1 |
| 7 | **Game icons and trophy icons** on public pages: show them (taught by launchers) or only on signed-in pages? | shown, scaled down, removed on request | Phase 1 |
| 8 | **Messages encryption**: server-readable at first (moderation possible) or end-to-end from day one? | server-readable, E2EE later | Phase 3 |
| 9 | **Push on iOS** needs the phone app signed with your team for APNs; distribution through AltStore today: TestFlight or the App Store later? | APNs with your team; TestFlight when ready | Phase 3 |
| 10 | **Voice recording**: never (this plan). Any reason to ever record (reports)? | never | Phase 4 |
| 11 | **Share play to people outside the party** (public streams)? | no, party members only | Phase 5 |
| 12 | **Branding**: AnyTogether inside AnyPS5 as "AnyTogether" with its two-ring mark; also a logo for the launcher's top bar? | the two-ring mark | Phase 0 |
| 13 | **Moderators**: who besides you? | you, then trusted community members | Phase 2 |
| 14 | **Legal texts**: terms, privacy policy, KVKK disclosure: written by kodla.agency's usual counsel or drafted here first? | drafted here, reviewed | before public sign-ups |
| 15 | **Paid features** ever (cosmetic themes, larger share play quality)? | none planned | later |
