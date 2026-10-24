# 8. Security, privacy and rules

## 8.1 Accounts

Built unless marked planned.

- **No passwords** to steal or reuse: sign-in is an email code, a passkey, the user's own
  signed-in phone, or Apple, Google or Discord (OpenID Connect, ID tokens verified against the
  provider's keys, PKCE for every public client).
- Email codes: 6 digits, valid 10 minutes, at most 5 per hour per address; 10 wrong tries end the
  code; the link in the mail is single-use. Codes and links are kept only as hashes.
- **Passkeys** (WebAuthn): added in Settings on the website, up to 10 per account; signing in with
  one needs no email. A passkey holds the account's ID, never an email or handle; its challenge is
  used once and lasts 5 minutes; a signature counter that goes backwards (a cloned key) is refused.
  Passkeys belong to the site's host name, so moving a site to another name makes them useless.
- Phone hand-off: the approval screen names the computer; adding its platform and approximate
  location (city from IP) is planned.
- Device codes (fallback): 8 characters without look-alikes, valid 10 minutes; polling faster than
  every 4 seconds is told to slow down.
- Messages only between friends; calls only to friends and party members.
- Sessions listed in settings with device and last use; any can be signed out, or all at once.
- Refresh tokens rotate on every use; reuse of an old one revokes the session.
- A banned account is signed out everywhere at once and refused at every way in (email code,
  providers, passkeys, hand-offs); a ban on an email also stops new accounts with it.

## 8.2 Transport and storage

- TLS everywhere (Cloudflare to the browser, Cloudflare to our origin with an origin certificate,
  authenticated origin pulls so only Cloudflare reaches the origin). A self-hosted AnyTogether gets
  its certificates from Let's Encrypt through Caddy.
- Voice and share play are **end-to-end encrypted** between the players (WebRTC's
  DTLS-SRTP); they go direct, and when they must go through our TURN relay it only forwards
  encrypted packets it cannot read. The server never hears or sees a call.
- A direct connection reveals each player's IP address to the other. Calls are only possible
  between friends or party members; a setting **Always use the relay** (planned) hides the IP
  address at the cost of a little delay.
- Database disk encrypted; backups encrypted before upload (age or restic) to R2.
- Secrets (database password, JWT signing key, TURN secret, OAuth client secrets, APNs key) in environment files
  readable only by the services, never in the repository; rotated yearly or on any suspicion.
- Avatars are re-encoded on the server to a 256 px JPEG, which drops whatever metadata (such as
  location) the upload carried; only PNG and JPEG up to 5 MB and 25 megapixels are taken.
- R2 (planned) buckets private except `cdn` (avatars, previews, downloads); uploads only by
  presigned URLs limited in size and content type, valid 10 minutes.
- The website's browser never holds a token: they stay in HttpOnly cookies, and the gateway socket
  opens with a one-time ticket valid 30 seconds.
- Rate limits on every route, per address and per account ([API](04-api.md) 4.9).

## 8.3 Abuse and moderation

- **Report** (built for users and messages; activities, themes and game names planned): one open
  report per person and target; a reported message's text is kept with the report even if its
  author deletes it. Moderators work through reports with a command-line tool that runs beside the
  API (`admin reports`, `report <id> dismiss|action`, `ban`, `unban`, `user`); an admin page
  (`/admin`) is planned.
- **Block**: a blocked user cannot see your presence, profile (beyond name), activity, or send you
  requests or messages; you do not see theirs.
- **Automatic checks**: names and bios cannot carry links (built). Planned: avatars and theme
  pictures through a nudity classifier before others see them; links in messages checked against
  a deny list (piracy sites, known malware); repeated identical messages throttled.
- **Actions**: ban for a time or until lifted, on an account, an email or both (built); warn,
  remove content, mute (planned). Each logged in `audit_log` with the moderator and reason; the user
  is told and can appeal by mail.
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
- Share play streams the host's own session to friends they invited, to watch; control never
  passes to them, and it is not public broadcasting. Streaming is the host's responsibility, like
  any screen sharing.
- A takedown address (`abuse@kodla.agency` or similar) and a process to answer within 48 hours.

## 8.5 Privacy (KVKK and GDPR)

AnyTogether is run from Türkiye and will have users in the EU: both KVKK (Law No. 6698) and GDPR
apply.

| What we collect | Why | Basis |
|---|---|---|
| Email (when signed in with one), handle, display name; passkeys (public keys only) | the account | contract |
| Avatar, bio, country (optional) | the profile | contract / consent for optional fields |
| Games played, sessions, trophies | the features the user signs in for | contract |
| Presence (online, game) | friends' presence | contract, can be hidden |
| Messages | delivering them | contract |
| Compatibility reports (platform, machine, OS, engine, FPS) | helping others | consent (opt-in) |
| IP addresses, device names | security, abuse | legitimate interest, kept 30 days in logs |
| Voice and share play media | carried live, **never recorded** by the server | contract |

- **No ads, no selling or sharing data**, no third-party trackers on the website (privacy-friendly
  analytics only, e.g. self-hosted Plausible, without cookies).
- **Export**: settings → "Download my data" gives one JSON file at once (built).
- **Delete**: settings → "Delete account", confirmed with a code by mail (or the handle, for an
  account without email); every device is signed out and friends stop seeing the account at once;
  14 days to change your mind (signing in keeps the account), then everything is removed; messages
  you sent are deleted, reports you made are anonymised; backups expire within 30 days (built).
- **Age**: 13 and older (16 where the law asks, for consent); no account for younger users.
- A clear privacy notice and KVKK disclosure text (aydınlatma metni) in Turkish and English on the
  website and linked from the launcher and the phone app.
- Data stored on our server in the EU or Türkiye (to decide with the server's location) and
  Cloudflare R2 (EU jurisdiction bucket).

## 8.6 Security work

- The code is public and MIT licensed, so anyone can read what the server does with their data.
- CI on every push: lint, typecheck and the tests against PostgreSQL and Valkey (built).
- Dependencies: Renovate or Dependabot; `npm audit`/`osv-scanner` in CI.
- Code: CodeQL in CI for the TypeScript code; the launcher's existing review habits for Swift.
- Pen test before opening sign-ups to the public (self-run with OWASP ASVS level 2 as checklist).
- A `security.txt` and a responsible disclosure page.
