# 3. Features

Each feature: what the user sees, in the launcher (L), the phone app (P) and the website (W);
how it works; and what it needs from the rest of the system.

---

## 3.1 Profiles

**What the user sees**

- A **gamer card**: avatar, display name, @handle, bio (160 characters), country flag (optional),
  "member since", and four numbers: games played, hours played, trophies, platinums.
- The card **wears the owner's theme** (from the Theme Studio): its colors behind the card, its
  picture or video as the banner, its accent on the numbers.
- **Showcase**: up to six chosen games or trophies pinned to the top of the profile.
- L: the profile name in the top bar becomes the avatar; choosing it opens your card, edit it
  there. P: the same card under the computer's name. W: `anytogether.kodla.agency/u/<handle>`, a public
  page with link previews (Open Graph image rendered from the card).

**How it works**

- The account (sign-in) and the profile (what others see) are separate tables; a profile can be
  renamed without touching sign-in.
- Handles: 3-20 characters, `a-z 0-9 _ .`, unique without regard to case, changeable once every
  30 days; the old handle redirects for 30 days.
- Avatars: uploaded straight to R2 with a presigned URL (PNG/JPEG/WebP up to 5 MB); the worker
  makes 64, 128 and 512 px WebP versions and checks for nudity with a small classifier before the
  avatar shows to anyone else (the owner sees it at once).
- The four numbers are counted by the worker when trophies or sessions change, not on every view.
- Visibility per item (see 3.5): everyone, friends, only me.

---

## 3.2 Trophies

**What the user sees**

- Per game: the trophy list as the launcher shows it today, plus **when** each one was earned,
  **rarity** (the share of AnyTogether players with this game who have it: "Ultra rare 2.1 %"),
  and progress for trophies that have it.
- A **trophy timeline** on the profile; **platinum** cards that stand out.
- When a friend earns a rare trophy, it can appear in the feed (3.8).
- L: the trophy screen gets the dates and rarity; the trophy banner says "Rare" when it is.
  P: the trophy card that drops in today shows rarity too. W: profile tab "Trophies".

**How it works**

- The launcher already knows a game's trophy set (names, grades, hidden ones) from the dump's
  trophy files, and notices earned trophies from the game's save data while playing.
- On first sign-in the launcher uploads the **trophy sets it knows** (title ID, trophy IDs,
  grades, names and descriptions in the user's language, icons as small WebP) unless the server
  already has that set, then the **earned trophies** with their times.
- Trophy sets are shared: the first player to sign in with a game teaches the server its set;
  others only send what they earned. Sets carry a hash of the trophy file, so a different version
  of a set is stored beside the old one, not over it.
- Hidden trophies stay hidden (name and description) to people who have not earned them.
- **Rarity** = players who earned it ÷ players who have played the game at least once, counted by
  the worker for games that changed, at most every 10 minutes per game; cached in the trophy row.
  Labels: Common > 50 %, Uncommon 20-50 %, Rare 5-20 %, Very rare 1-5 %, Ultra rare < 1 %.
- Integrity: a trophy is believed as the launcher reports it. Obviously impossible patterns (all
  trophies of a game earned in the same second, earned before the game was first played) are
  flagged and kept off leaderboards until a moderator looks. These are AnyTogether trophies; they
  never go to PlayStation Network.

---

## 3.3 Voice chat

**What the user sees**

- Inside a party (3.4), everyone's voice, with a speaking ring around their avatar, their own
  volume each, mute, deafen, push-to-talk (a key on the computer, a button on the phone).
- Voice keeps going while a game is in front: the launcher stays in the background and still
  carries the party; a small overlay card can show who is talking (like the trophy banner today).
- **The phone as a headset**: the party's voice can go through the phone (its mic and speaker or
  headphones) instead of the computer, while the phone is also the pad. Useful when the computer's speakers
  carry the game.
- W: join the party's voice from a browser, no install.

**How it works**

- Voice goes **directly between the members** (WebRTC, each member connected to each other one;
  up to 8 talking members). The server only introduces them (signalling over the gateway) and
  hands out relay credentials for the pairs whose networks cannot connect directly.
- Audio: Opus, 48 kHz, 24-48 kbit/s, with the platforms' echo cancellation, noise suppression and
  automatic gain (Apple's voice processing on macOS/iOS, WebRTC's on Android and the web).
- In every launcher (macOS, Windows, Linux): the launcher's WebRTC; the game's own sound is not sent (the
  launcher captures the microphone only). The launcher must ask for the microphone permission.
- Target: mouth-to-ear under 200 ms on the same continent; a direct path adds nothing on top of
  the network itself.

---

## 3.4 Parties

**What the user sees**

- **Start a party** from the launcher, the phone or the web; invite friends (they get a push
  notification and a card in the launcher); up to 8 members.
- The party shows **what each member is playing** and offers **"Play the same game"**: on a
  member's launcher it selects that game if they have it, or says they do not.
- A party has a text chat beside the voice (3.6 group chat tied to the party).
- From a party, the host can start **share play** (3.11) for the others.
- Party privacy: invite only (default), friends can join, or anyone with the link.

**How it works**

- A party is a database row (owner, privacy, created) plus a call set up on demand when the
  first member opens voice.
- Membership changes go through the API and are pushed by the gateway (`party.member_joined`,
  `party.member_left`, `party.updated`).
- A party with no member connected for 10 minutes ends by itself.
- "Play the same game" sends `party.play_request {title_id}`; each launcher looks up the title ID
  in its own library. Games themselves are never involved.

---

## 3.5 Friends

**What the user sees**

- Add by @handle, by a QR code shown on the other person's phone, or from a party; requests can be
  accepted or declined; friends can be removed and users blocked.
- A **friends list** with presence: online, away, offline, and **what they are playing** (the
  game's name and icon, and for how long), in a party or not.
- L: a Friends panel (a new item in the top bar, with a count of who is online); the home screen
  can show a small row of online friends. P: a Friends tab. W: the friends page.

**How it works**

- A friendship is one row per pair, with a state (pending, accepted) and who asked.
- **Presence**: each client sends a heartbeat over the gateway every 25 s with its state
  (`online`, `away` after 10 min idle, `in_game` with the title ID and when it started). The
  gateway writes it to Valkey with a 60 s expiry; on change it publishes to the user's friends.
  Several devices merge: in-game wins over online wins over away.
- Presence of someone you blocked, or who set "appear offline", is never sent.
- Discord presence keeps working side by side; it does not depend on AnyTogether.

**Visibility settings** (per user, each with everyone / friends / only me):
profile details, game library, play time, trophies, activity, online status, who may send friend
requests (everyone / friends of friends / nobody), who may message (friends / everyone).

---

## 3.6 Messages

**What the user sees**

- **Direct** chats with a friend and **group** chats (up to 32 people), with text, emoji
  reactions, replies, links (with previews), images (up to 10 MB) and shared clips or
  screenshots from the gallery.
- Read receipts (can be turned off), typing indicator, unread counts.
- Messages follow you: the launcher (a Messages panel, and a toast while playing that does not
  take focus from the game), the phone app (a Messages tab, push notifications when the app is
  closed), the web.

**How it works**

- Messages are stored in PostgreSQL (not end-to-end encrypted at first; see open questions), in
  conversations with members. Each message has a server-assigned increasing ID per conversation;
  clients keep the last ID they have and ask for newer ones on reconnect
  (`GET /v1/conversations/{id}/messages?after=...`), so nothing is lost or duplicated.
- Sending: `POST /v1/conversations/{id}/messages` with a client-made ID (UUIDv7) so a retry does
  not send twice; the gateway pushes `message.created` to members' sockets; members not connected
  get a push notification (APNs/FCM) via the worker, at most one per conversation per minute.
- Images go to R2 via presigned URL; the message holds the file's key, size and dimensions.
- Moderation: report a message; blocked users cannot message you; links to known piracy sites
  are refused (see rules).

---

## 3.7 Game library

**What the user sees**

- Every game you played: name, icon, **total play time**, **last played**, first played, trophy
  progress (bar and percent), on which computers. Sort by recent, time, name, completion.
- Per game page on the web (`/g/<title id>`): who among your friends plays it, their progress,
  the community's compatibility verdict (see below), global trophy rarity.
- L: the existing library and home screen get "Friends playing" and play time from all your computers.

**How it works**

- The launcher records **sessions**: title ID, start, end, computer (a stable random ID per computer, named
  by the user). Sessions go through the outbox like trophies. Play time = sum of sessions.
- **Game catalogue**: one row per title ID with the name in each language and the icon, taught by
  the first launcher that has the game (name from `param.json`, icon from `icon0.png` scaled to
  256 px). Moderators can fix names. Only the title ID, name and icon: never other game files.
- **Compatibility** (the old idea 6, now here): after a session the launcher may ask "How did it
  run?" with four answers (didn't start, menus only, playable with problems, plays well), plus
  automatic facts it already knows: the engine version, the platform, the machine (Mac model or CPU/GPU), OS version, average FPS
  (from the overlay's counters) and how the game ended (normal exit or the launcher's diagnosis of
  a crash). Off unless the user turns on "Help others: report how games run". The game page shows
  the latest verdict per engine version.

---

## 3.8 Activity feed

**What the user sees**

- A stream of what friends did: earned a trophy (rare ones and platinums stand out), started
  playing a new game, played for a long session, reached 100 %, shared a clip or screenshot,
  made a theme, joined AnyTogether.
- Like (a single reaction) and comment (opens a small chat thread).
- L: a Feed panel; P: a Feed tab; W: the home page when signed in.

**How it works**

- Events are written as rows when their cause happens (`activity` table: actor, kind, payload,
  visibility), respecting the actor's visibility settings at write time.
- The feed is read with a query over friends' activities, newest first, with keyset pagination
  (`before=<id>`); a materialized "fan-out on read" is fast enough at our scale with an index on
  `(actor_id, id desc)`. If it grows, move to fan-out on write for users with many friends.
- Noise control: consecutive trophies in one game within an hour fold into one item ("earned 5
  trophies in Silksong"); sessions shorter than 10 minutes are not shown.
- Clips and screenshots appear only when the user shares them explicitly (from the gallery:
  "Share to AnyTogether"); never automatically.

---

## 3.9 Themes

**What the user sees**

- The **Theme Hub** moves from the GitHub folder to AnyTogether: browse themes with live previews,
  sort by new, popular, liked; one press installs and applies (as today in the launcher's Themes
  screen); like a theme; see its maker's profile.
- **Publish** straight from the Theme Studio ("Share on the Hub" uploads instead of opening a
  GitHub issue). Updates to your own theme raise its version; people who installed it are
  offered the update.
- **Profile theme**: your profile wears a theme you choose (yours or one you installed).
- Later in the same shelf: **pad layouts** for the phone per game, **per-game settings presets**
  (resolution, frame generation, input tuning), shared **shader caches** (the old idea 7).

**How it works**

- A theme is the same `.anyps5theme` file the launcher already makes (theme.json plus an optional
  picture/video and music). Upload: the launcher asks `POST /v1/themes` for a presigned R2 URL,
  uploads the file, then confirms; the worker unpacks it in a sandbox, checks the same rules the
  launcher's installer checks (plain file names, size limits, only the named files), makes a
  preview image (1280x720 WebP) and a short preview video if there is one, and publishes.
- Moderation queue for new makers' first theme (pictures can be anything); trusted makers publish
  at once.
- The launcher's existing `ThemeHub` client points at the new index endpoint
  (`GET /v1/themes?sort=popular`) instead of the GitHub raw URL; the GitHub folder stays as a
  fallback for old launchers.

---

## 3.10 Downloads

**What the user sees**

- One page with the **official** AnyPS5 launchers for macOS, Windows and Linux (each from its own project's releases), the phone app (APK; IPA with the
  sideloading guide; later the stores), release notes, and tools the project makes.
- Version checks: the launcher's "Check for Updates" may ask AnyTogether as well as GitHub.

**How it works**

- Files are mirrored from GitHub releases to R2 by a GitHub Action on each release (the release
  stays the source), with SHA-256 checksums shown next to each file and in the API.
- `GET /v1/releases/latest?product=launcher` returns version, notes, URL and checksum.
- **Strict rule:** only AnyPS5's own software and community-made content (themes, layouts).
  Never game files, dumps, firmware, keys, or links to them. Uploads of anything else are refused
  and reported.

---

## 3.11 Share play

**What the user sees**

- In a party or a direct chat, the host presses **Share play**: friends see the host's game live
  (picture and sound), on the phone app, the web or their own launcher.
- **Watch** mode (default): friends watch and talk.
- **Take over** / **Play together**: the host hands the controller to a friend (the friend's pad
  drives player 1) or adds them as player 2 (the friend's pad becomes a second DualSense in the
  host's game, exactly like a second phone on the same Wi-Fi today). The host can take it back
  at any time with their own pad's PS button.
- The latency is shown to both sides, as Remote Play shows it today.

**How it works** (details in [Realtime, voice and share play](06-realtime-voice-shareplay.md))

- The macOS launcher already captures the game (ScreenCaptureKit) and encodes it with low latency
  (`StreamEncoder`: H.264, no reordering); the Windows/Linux launcher does the same with its
  platform's capture and hardware encoder. For share play it publishes that video and the game's
  sound over a direct WebRTC connection to each viewer instead of (or as well as) sending them to a phone
  on the local network.
- The friend's client subscribes to the tracks. A friend allowed to play sends pad state over a
  WebRTC data channel (unreliable, unordered, 120 packets/s, the same 80-byte packet the phone
  sends today); the host's launcher feeds it into a free remote-pad bridge (`ANYPS5_REMOTE_PAD_2`
  etc.) so the game sees another DualSense.
- Same-network friends keep using the local path. Over the internet the connection is direct
  between host and viewer, with our relay only when the networks cannot reach each other.
  Every launcher can host: macOS with ScreenCaptureKit, Windows with Windows.Graphics.Capture,
  Linux with PipeWire (see [Platforms](12-platforms.md)).
- Targets: glass-to-glass under 120 ms within ~1000 km; 720p60 at 6-10 Mbit/s, dropping to 540p
  or 30 fps when the network says so.

---

## 3.12 Leaderboards

**What the user sees**

- **Friends** and **global** boards: trophy points (bronze 15, silver 30, gold 90, platinum 300,
  as PlayStation counts them), platinums, hours played, completion percent; all time, this month,
  this week.
- **Per game** boards: completion and time to 100 %, among friends and globally.
- Your rank and the people just above and below you.

**How it works**

- The worker rebuilds the boards every 10 minutes from trophies and sessions into Valkey sorted
  sets (`lb:global:points:all`, `lb:game:<title>:completion`, ...), and stores a nightly snapshot
  in PostgreSQL for history.
- Friends boards are computed on request from the friends' rows (a few hundred at most).
- Flagged trophies (see 3.2) and private profiles stay off global boards; private players see
  their own rank only.
