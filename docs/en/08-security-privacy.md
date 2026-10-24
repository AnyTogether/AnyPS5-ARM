# 8. Security, privacy and rules

## 8.1 Accounts

- **No passwords** to steal or reuse: sign-in is Apple, Google or Discord (OpenID Connect, ID
  tokens verified against the provider's keys, PKCE for every public client), an email code, or
  the user's own signed-in phone.
- Email codes: 6 digits, valid 10 minutes, at most 5 sends per hour per address and 10 wrong tries
  before a 15-minute lock; the magic link is single-use.
- Phone hand-off: the approval screen names the computer, its platform and approximate location
  (city from IP), so a request the user did not make is noticed.
- Device codes (fallback): 8 characters without look-alikes, valid 10 minutes.
- New accounts may not message strangers for 24 hours.
- Sessions listed in settings with device and last use; any can be signed out.
- Refresh tokens rotate on every use; reuse of an old one revokes the session.
- Passkeys (WebAuthn) as an additional way in later.

## 8.2 Transport and storage

- TLS everywhere (Cloudflare to the browser, Cloudflare to our origin with an origin certificate,
  authenticated origin pulls so only Cloudflare reaches the origin).
- Voice, share play and pads are **end-to-end encrypted** between the players (WebRTC's
  DTLS-SRTP); they go direct, and when they must go through our TURN relay it only forwards
  encrypted packets it cannot read. The server never hears or sees a call.
- A direct connection reveals each player's IP address to the other. Calls are only possible
  between friends or party members; a setting **Always use the relay** hides the IP address at the
  cost of a little delay.
- Database disk encrypted; backups encrypted before upload (age or restic) to R2.
- Secrets (database password, JWT signing key, TURN secret, OAuth client secrets, APNs key) in environment files
  readable only by the services, never in the repository; rotated yearly or on any suspicion.
- R2 buckets private except `cdn` (avatars, previews, downloads); uploads only by presigned URLs
  limited in size and content type, valid 10 minutes.

## 8.3 Abuse and moderation

- **Report** on every user, message, activity, theme and game name; reports go to a moderator
  queue in an admin page (`/admin`, roles `moderator`, `admin`).
- **Block**: a blocked user cannot see your presence, profile (beyond name), activity, or send you
  requests or messages; you do not see theirs.
- **Automatic checks**: avatars and theme pictures through a nudity classifier before others see
  them; links in messages checked against a deny list (piracy sites, known malware); repeated
  identical messages throttled.
- **Actions**: warn, remove content, mute (no messages for a time), suspend, ban; each logged in
  `audit_log` with the moderator and reason; the user is told and can appeal by mail.
- **Leaderboard integrity**: impossible trophy patterns flagged automatically, reviewed by a
  moderator.

## 8.4 What may never be on AnyTogether

This rule is in the terms, enforced by moderation, and built into the product:

- **No game files of any kind**: dumps, PKGs, game data, updates or DLC files, save files of
  others, firmware, keys, decryption tools, or links or instructions for getting them.
- **No account or key trading.**
- AnyTogether stores about games only: the title ID, the name, the icon (scaled down) and trophy
  texts and icons, as the launcher reads them from the user's own game. These are used to show
  the game in profiles and libraries.
- Share play streams the host's own session to friends they invited; it is not public
  broadcasting. Streaming is the host's responsibility, like any screen sharing.
- A takedown address (`abuse@kodla.agency` or similar) and a process to answer within 48 hours.

## 8.5 Privacy (KVKK and GDPR)

AnyTogether is run from Türkiye and will have users in the EU: both KVKK (Law No. 6698) and GDPR
apply.

| What we collect | Why | Basis |
|---|---|---|
| Email, password hash, handle, display name | the account | contract |
| Avatar, bio, country (optional) | the profile | contract / consent for optional fields |
| Games played, sessions, trophies | the features the user signs in for | contract |
| Presence (online, game) | friends' presence | contract, can be hidden |
| Messages | delivering them | contract |
| Compatibility reports (platform, machine, OS, engine, FPS) | helping others | consent (opt-in) |
| IP addresses, device names | security, abuse | legitimate interest, kept 30 days in logs |
| Voice and share play media | carried live, **never recorded** by the server | contract |

- **No ads, no selling or sharing data**, no third-party trackers on the website (privacy-friendly
  analytics only, e.g. self-hosted Plausible, without cookies).
- **Export**: settings → "Download my data" makes a zip (JSON and the user's files) within 48 h.
- **Delete**: settings → "Delete account"; 14 days to change your mind, then everything is
  removed; messages you sent are deleted, reports you made are anonymised; backups expire within
  30 days.
- **Age**: 13 and older (16 where the law asks, for consent); no account for younger users.
- A clear privacy notice and KVKK disclosure text (aydınlatma metni) in Turkish and English on the
  website and linked from the launcher and the phone app.
- Data stored on our server in the EU or Türkiye (to decide with the server's location) and
  Cloudflare R2 (EU jurisdiction bucket).

## 8.6 Security work

- Dependencies: Renovate or Dependabot; `npm audit`/`osv-scanner` in CI.
- Code: CodeQL in CI for the TypeScript code; the launcher's existing review habits for Swift.
- Pen test before opening sign-ups to the public (self-run with OWASP ASVS level 2 as checklist).
- A `security.txt` and a responsible disclosure page.
