# 3. Features

Each feature: what the user sees, in the launcher (L), the phone app (P) and the website (W);
how it works; and what it needs from the rest of the system. Each one starts with its status on
2026-10-25. "Released" means in AnyPS5-ARM 0.2.15 (the macOS launcher), phone app 1.11.0 or
AnyPS5 Desktop 0.1.1 (the Windows/Linux launcher); the website and the server are released as
they are built.

| # | Feature | Status |
|---|---|---|
| 3.1 | Profiles | built in part: handle, name, bio, country, avatar, privacy, recent activity; theme and showcase planned |
| 3.2 | Trophies | built: sets, earned trophies, rarity; dates and rarity on the launcher's own trophy screen planned |
| 3.3 | Voice chat | built: parties and 1:1 calls on the web, the macOS launcher, the phone and AnyPS5 Desktop |
| 3.4 | Parties | built, with joining a friend's game and public parties; party chat planned |
| 3.5 | Friends | built, with finding people beyond your friends; QR codes planned |
| 3.6 | Messages | built for text, with typing and groups; images and reactions planned |
| 3.7 | Game library | built: sessions, catalogue, play time, game hubs on the web |
| 3.8 | Activity feed | built: items and reactions on the web, the macOS launcher and the phone |
| 3.9 | Themes | built: the Theme Hub on AnyTogether; profile themes planned |
| 3.10 | Downloads | built: the website's download page and the releases API |
| 3.11 | Share play | built: the macOS launcher hosts; viewers on the web, the phone and the macOS launcher play along on pads 2-4 |
| 3.12 | Leaderboards | built: trophy points overall, points, play time and completion per game |
| 3.13 | Notifications | built: the bell everywhere, browser push, a mail digest; phone push planned |
| 3.14 | Finding players | built on the web: the looking-for-group board, public parties and share plays, discovery, game hubs |
| 3.15 | Compatibility list | built: reports from the macOS launcher and the web, verdicts per platform |

---

## 3.1 Profiles

**Status:** built in part. Built: the handle, display name, bio, country, avatar and privacy per
section; the public page `/u/<handle>` on the web with games, play time, trophies and recent
activity; your own card and your friends' in the macOS launcher and on the phone (editing your
profile and picture on the phone since 1.11.0) and in AnyPS5 Desktop, with games, hours, trophies
and points and the latest trophies' rarity. Planned: the theme on the card, the showcase, the
numbers kept on the server, Open Graph images, checking avatars.

**What the user sees**

- A **gamer card**: avatar, display name, @handle, bio (160 characters), country flag (optional),
  "member since", and four numbers: games played, hours played, trophies, platinums.
- The card **wears the owner's theme** (from the Theme Studio): its colors behind the card, its
  picture or video as the banner, its accent on the numbers (planned).
- **Showcase**: up to six chosen games or trophies pinned to the top of the profile (planned).
- L: the profile name in the top bar becomes the avatar; choosing it opens your card, edit it
  there. P: the same card, editable. W: `anytogether.kodla.agency/u/<handle>`, a public page.

**How it works**

- The account (sign-in) and the profile (what others see) are separate tables; a profile can be
  renamed without touching sign-in.
- Handles: 3-20 characters, `a-z 0-9 _ .`, unique without regard to case, changeable once every
  30 days; the old handle is held for its owner and still leads to the profile for 30 days.
- Avatars: sent to the API (PNG or JPEG up to 5 MB), re-encoded to a 256 px JPEG without
  metadata and served by the hash of its bytes; kept in PostgreSQL for now, R2 later. A moderator
  can reset an avatar or a bio from a report.
- Visibility per section (see 3.5): everyone, friends, nobody.

---

## 3.2 Trophies

**Status:** built in the API, in the macOS launcher and AnyPS5 Desktop (play time and trophies go
up through an outbox) and on web profiles. Rarity is counted when trophies arrive; friends hear of
a trophy as it is earned (a hidden one without its name), and trophies become feed items (3.8).
Planned: dates and rarity on the launcher's own trophy screen and banner, the timeline, flagging
impossible patterns.

**What the user sees**

- Per game: the trophy list as the launcher shows it today, plus **when** each one was earned,
  **rarity** (the share of AnyTogether players with this game who have it: "Ultra rare 2.1 %"),
  and progress for trophies that have it.
- A **trophy timeline** on the profile; **platinum** cards that stand out (planned).
- When a friend earns a trophy, it appears in the feed (3.8), rare ones and platinums marked.

**How it works**

- The launcher already knows a game's trophy set (names, grades, hidden ones) from the dump's
  trophy files, and notices earned trophies from the game's save data while playing.
- On first sign-in the launcher uploads the **trophy sets it knows** (title ID, trophy IDs,
  grades, names and descriptions in the user's language) unless the server already has that set,
  then the **earned trophies** with their times.
- Trophy sets are shared: the first player to sign in with a game teaches the server its set;
  others only send what they earned. Sets carry a hash, so a different version of a set is stored
  beside the old one, not over it.
- Hidden trophies stay hidden (name and description) to people who have not earned them.
- **Rarity** = players who earned it ÷ players who have played the game at least once, counted
  again for a game whenever trophies for it arrive; cached in the trophy row.
  Labels: Common > 50 %, Uncommon 20-50 %, Rare 5-20 %, Very rare 1-5 %, Ultra rare < 1 %.
- Integrity: a trophy is believed as the launcher reports it. Obviously impossible patterns (all
  trophies of a game earned in the same second, earned before the game was first played) are to
  be flagged and kept off leaderboards until a moderator looks (planned). These are AnyTogether
  trophies; they never go to PlayStation Network.

---

## 3.3 Voice chat

**Status:** built in parties and in calls between two friends, on the web, in the macOS launcher,
in the phone app and in AnyPS5 Desktop (its voice is built, but not yet part of the cross-client
run): a peer-to-peer mesh, microphone on and off with a mute everyone sees, a ring around whoever
speaks, push-to-talk on ⌥V in the macOS launcher and on a key of your choice (V by default) in
AnyPS5 Desktop, both read over a game; relay credentials renewed before they run out; a device
whose socket goes leaves its calls. A call to a friend can start from any page of the website.
Planned: volume per person, deafen, the overlay card, the phone as the computer's headset.

**What the user sees**

- Inside a party (3.4), everyone's voice, with a speaking ring around their avatar, mute, and
  push-to-talk (a key on the computer). Their own volume each and deafen are planned.
- A **call** to one friend: it rings on all their devices, stops ringing on the others when one
  answers, and becomes a missed-call notification when nobody does.
- Voice keeps going while a game is in front: the launcher stays in the background and still
  carries the party.
- **The phone as a headset** (planned): the party's voice through the phone while it is also the
  pad.
- W: join the party's voice from a browser, no install.

**How it works**

- Voice goes **directly between the members** (WebRTC, each member connected to each other one;
  up to 8 talking members). The server only introduces them (signalling over the gateway) and
  hands out relay credentials for the pairs whose networks cannot connect directly.
- Audio: Opus, 48 kHz, tuned for voice, with the platforms' echo cancellation, noise suppression
  and automatic gain (Apple's voice processing on macOS/iOS, WebRTC's on Windows, Linux, Android
  and the web).
- The game's own sound is not sent (the launcher captures the microphone only). The launcher asks
  for the microphone permission the first time.
- Target: mouth-to-ear under 200 ms on the same continent.

---

## 3.4 Parties

**Status:** built: parties of up to 8 with a leader who invites, kicks and hands over, on the web,
in the macOS launcher, in the phone app and in AnyPS5 Desktop; **joining a friend's game** in both
launchers; **public parties** on the web, which others ask to join or walk into (3.14). Planned:
the party's text chat, push notifications for invites on the phone.

**What the user sees**

- **Start a party** from the launcher, the phone or the web; invite friends (they get a card and
  a notification); up to 8 members.
- The party shows **what each member is playing**, and friends see in presence that you are in a
  party.
- **List it in public** (off unless the leader turns it on): with a game and a language, either
  "ask to join" (the leader lets people in) or "open" (anyone walks in). It then shows under
  Find players and on the game's hub.
- **Join a friend's game**: while a game runs, the launcher opens a game session for it, unless
  "Let friends join my game" is off. Friends see the game as joinable and get **Play with** in the
  Friends panel; the host can invite them too. Joining starts the same game, after checking the
  host's game version and engine build, with a clear message when they differ. With online play
  ([6.7](06-realtime-voice-shareplay.md)) the two copies then play together.
- A party has a text chat beside the voice (3.6 group chat tied to the party; planned).

**How it works**

- A party is a database row (leader, privacy, and its public listing when it has one) with its
  members (someone is in one party at a time), invites and requests to join, plus a call set up on
  demand when the first member opens voice.
- Membership changes go through the API and are pushed by the gateway (`party.member_joined`,
  `party.member_left`, `party.updated`, `party.request`).
- A party ends when its last member leaves; when the leader leaves, the next member leads.
- A game session is a row too: host, title ID, game version, engine build, capacity (2-16),
  joinable or not, and up to 4 KB of properties the launchers define, plus each player's own
  properties; its players are listed, and a join with another game version or engine build is
  refused (`version_mismatch`). Players can signal each other through the gateway and get relay
  credentials for the session, for online play. The host's presence shows the game and whether
  there is room.

---

## 3.5 Friends

**Status:** built: requests by handle or from search, accept, decline, remove, block; presence
with the game being played and the party, game session or share play; privacy settings; finding
people beyond your friends (3.14). On the web, in the macOS launcher, in the phone app and in
AnyPS5 Desktop. Planned: QR codes, a friends row on the home screen, the setting for who may send
requests.

**What the user sees**

- Add by @handle, from search, from the people one may know (3.14), or by a QR code shown on the
  other person's phone (planned); requests can be accepted or declined; friends can be removed and
  users blocked.
- A **friends list** with presence: online, away, offline, and **what they are playing** (the
  game's name and icon, and for how long), in a party or not, sharing their game or not.
- L: a Friends panel (in the top bar, with a count of who is online). P: a Friends screen. W: the
  friends page.

**How it works**

- A friendship is one row per pair, with a state (pending, accepted) and who asked.
- **Presence**: each client sends a heartbeat over the gateway every 25 s with its state
  (`online`, `away` after 10 min idle, `in_game` with the title ID and when it started). The
  gateway writes it to Valkey with a 60 s expiry; on change it publishes to the user's friends.
  Several devices merge: in-game wins over online wins over away.
- Presence of someone you blocked, or who set presence to "nobody", is never sent.
- Discord presence keeps working side by side; it does not depend on AnyTogether.

**Visibility settings** (per user, each with everyone / friends / nobody), as built: the game
library and play time, trophies, the friends list, presence, and who finds you in search (a
request to your exact handle always works). The defaults are friends, and everyone for search.
Activity follows the setting of what it is about (a trophy item follows trophies). **Discovery**
(shown in "Players of", suggestions and game hubs) follows the library setting unless chosen.
Planned: who may send friend requests, who may message (today: friends only).

---

## 3.6 Messages

**Status:** built for text: direct and group conversations (up to 32 people, between friends; a
group can be made from the website), messages up to 4000 characters, replies, editing within 15
minutes, deleting, read state and unread counts, the typing indicator, reporting a message, and a
deny-list of link domains (IP loggers by default). On the web, in the macOS launcher, in the phone
app and in AnyPS5 Desktop. Messages to someone with no device connected become a notification
(3.13). Planned: reactions, link previews, images and clips, read receipts as a setting.

**What the user sees**

- **Direct** chats with a friend and **group** chats (up to 32 people), with text, replies, the
  typing indicator and unread counts; emoji reactions, links with previews, images (up to 10 MB)
  and shared clips are planned.
- Messages follow you: the launcher (a Messages panel), the phone app, the web; while you are
  away, the bell, a browser push and, if you want it, a mail digest.

**How it works**

- Messages are stored in PostgreSQL (not end-to-end encrypted; see open questions), in
  conversations with members. Each message has a server-assigned increasing number per
  conversation; clients keep the last one they have and ask for newer ones on reconnect
  (`GET /api/v1/conversations/{id}/messages?after=...`), so nothing is lost or duplicated.
- Sending: `POST /api/v1/conversations/{id}/messages` with a client-made ID so a retry does not send
  twice; the gateway pushes `message.created` to members' sockets. "Typing" goes over the gateway
  only, at most every two seconds, and is never stored.
- Moderation: report a message; blocked users cannot message you; links to domains on the
  deny-list are refused (the operator can replace the list).

---

## 3.7 Game library

**Status:** built: sessions, the catalogue taught by launchers, computers registered by the
launcher, the library with play time and trophy progress, shown on web profiles; **game hubs** on
the web at `/games/<title id>`. Planned: sorting, play time from all your computers in the
launcher's own library.

**What the user sees**

- Every game you played: name, icon, **total play time**, **last played**, first played, trophy
  progress (bar and percent), on which computers.
- A **game hub** on the web (`/games/<title id>`): who plays it right now (people whose presence is
  public), open looking-for-group posts, public parties and share plays, the top players, how it
  runs (3.15), players who show it in their library, and themes named after it.

**How it works**

- The launcher records **sessions**: title ID, start, end, computer (a stable random ID per
  computer, named by the user). Sessions go through the outbox like trophies. Play time = sum of
  sessions.
- **Game catalogue**: one row per title ID with the name in each language and the icon, taught by
  the first launcher that has the game. Moderators can lock a name. Only the title ID, name and
  icon: never other game files. Icon URLs are kept only from hosts the operator lists.
- Who plays a game now comes from the gateway: a heartbeat that says "in game" keeps the player in
  that game's set for a little longer than two heartbeats.

---

## 3.8 Activity feed

**Status:** built: the feed on the website's home page, in the macOS launcher (an Activity panel
and recent activity on profiles) and on the phone, with reactions. Planned: comments, clips and
screenshots shared from the gallery, themes made.

**What the user sees**

- A stream of what friends did: earned a trophy (several in one game within an hour fold into one
  item; rare ones and platinums stand out), earned a platinum, played a game for the first time,
  played for two hours or more, became friends with someone, reached a round number (trophies,
  platinums, games, hours).
- One reaction per person per item, from four: 🔥 👏 😮 ❤️.
- L: an Activity panel and "Recent activity" on profiles; P: a feed screen; W: the home page when
  signed in, and the profile.

**How it works**

- Items are rows written when their cause happens (`activities`: actor, kind, game, payload), and
  only for what happened in the last 24 hours, so a launcher's first upload of years of trophies
  stays out of friends' feeds.
- Who may see an item is worked out when the feed is read, from the actor's privacy setting for
  what it is about (library or trophies; for a friendship, both people's friends-list setting), so
  changing a setting hides or shows old items at once.
- The feed is a query over friends' items, newest first, 30 a page by the last ID. A new item, or
  one that folded in more trophies, reaches friends' sockets as `feed.item`.
- Milestones: trophies 10, 50, 100, 250 … 5000; platinums 5, 10, 25, 50, 100; games 5 … 100; hours
  10 … 2500. Only the highest one crossed at once is written.

---

## 3.9 Themes

**Status:** built: the **Theme Hub** on AnyTogether. The macOS launcher lists and installs from it,
shares to it when signed in, and opens `anyps5://theme/<id>` links; the website has the Hub, a
theme's page, sharing and your own themes; old launchers read the same themes through the old
index. The GitHub folder stays as the fallback while a server has no themes. Planned: profile
themes, pad layouts and per-game presets on the same shelf.

**What the user sees**

- Browse themes with previews, sort by new, popular (downloads) or liked; search by name or
  maker; one press installs and applies (as in the launcher's Themes screen); like a theme; see
  its maker.
- **Share on the Hub** from the launcher (signed in) uploads the theme in use; sharing the same
  theme again sends it as its next version. On the web, a theme file can be shared with a picture.
- **Profile theme** (planned): your profile wears a theme you choose.

**How it works**

- A theme is the same `.anyps5theme` file the launcher already makes (`theme.json` plus an
  optional picture or video and music). It goes up in one request (up to 50 MB, with a still of
  at most 8 MB); the API unpacks it with the same rules the launcher's installer checks (plain
  file names, size limits, only the named files, 80 MB unpacked), repacks it, makes a preview and
  a thumbnail as WebP, and publishes it at once.
- Files live in the blob store (PostgreSQL today); downloads carry the version and SHA-256, and
  each person (or address) counts once a day per theme.
- Moderation: anyone signed in can report a theme; three people's open reports put it back in
  review (hidden from everyone but its maker) until a moderator shows it again or hides it.

---

## 3.10 Downloads

**Status:** built: the website's `/download` page and the releases API, read from each project's
latest GitHub release.

**What the user sees**

- One page with the **official** AnyPS5 launchers: macOS (the zip and the one-line install), the
  phone app (APK; IPA with the sideloading guide), Windows and Linux (AnyPS5 Desktop: the
  installer, the AppImage, the .deb), each with its version, size, release notes and checksum.

**How it works**

- The API asks GitHub for each project's latest release (AnyPS5-ARM for the Mac and the phone,
  AnyPS5-Desktop for Windows and Linux), keeps the answer ten minutes and the last good one for a
  week. GitHub stays the source; the SHA-256 GitHub publishes for each file is shown beside it.
- `GET /api/v1/releases/latest?product=launcher|phone|phone-ios|desktop` returns version, notes,
  URL, size and checksum.
- **Strict rule:** only AnyPS5's own software and community-made content (themes). Never game
  files, dumps, firmware, keys, or links to them.

---

## 3.11 Share play

**Status:** built: the macOS launcher hosts (0.2.15); friends watch in the browser, on the phone
(1.11.0) or in their own macOS launcher, and the host can let up to three of them play as
**player 2, 3 or 4**, each with their own pad. The host's own controller stays **player 1**,
always: the host never hands it over, and a viewer's pad can never take it. Planned: hosting from
AnyPS5 Desktop on Windows and Linux.

**What the user sees**

- While a game runs, the host opens the **Friends** panel and starts **Share play**: friends can
  walk in (or only invited ones), up to 4 viewers (2 by default). Friends see in presence that the
  host is sharing, with **Watch**; invites reach them as a card and a notification.
- Viewers see and hear the host's game live: full screen in the launcher, on the phone, or on the
  website's watch page with fullscreen, volume and a quality line.
- For each viewer the host chooses **Let … play as player N**, takes the pad back (every button
  is let go first), or takes the viewer out. A viewer with a pad plays with their controller (the
  launcher, the website), the keyboard (the website) or the phone's on-screen pad; the game's
  rumble and light bar come back to them.
- Both sides see whether the link is direct or through the relay, its round trip, and the
  picture's size and frame rate.
- A share play can be **listed in public** (off unless the host turns it on): "ask to join" or
  "open", and an open one can also appear under **Live now** for anyone to watch (3.14). Only the
  host ever hands out a pad.

**How it works** (details in [Realtime, voice and share play](06-realtime-voice-shareplay.md))

- The macOS launcher captures the game window without its title bar (ScreenCaptureKit) and sends
  it as one H.264 video track (WebRTC's VideoToolbox encoder, 720p60, following WebRTC's bandwidth
  estimate; 540p30 to each viewer from the third viewer on), on a peer connection per viewer. The
  game's sound goes on a lossy data channel as Remote Play's PCM packets.
- A viewer's pad goes back on another data channel as the same 80-byte packets the phone sends.
  The host's launcher lets a viewer's packets reach the game only while that viewer holds a pad,
  through a pad bridge of its own, and writes the granted player number into each packet so the
  engine seats them as that player and never as player 1.
- The API keeps who watches, on which device, and who holds which pad; share plays live only in
  Valkey and last as long as the game. Signals go only between the host and a viewer, never from
  viewer to viewer.
- Targets: glass-to-glass under 120 ms within ~1000 km; the picture steps down when the network
  says so.

---

## 3.12 Leaderboards

**Status:** built: overall **trophy points**, and per game **points**, **play time** and
**completion**, among **friends** or **everyone**, on the website, in the macOS launcher and on the
phone. Planned: this month and this week, platinum counts, time to 100 %.

**What the user sees**

- Trophy points (bronze 15, silver 30, gold 90, platinum 300, as PlayStation counts them) among
  friends or everyone; per game: points, hours played or completion percent.
- Up to 100 entries, ties sharing a rank; your rank, the people just above and below you when you
  are further down, and how many are on the board.
- Not on a global board (your trophies or library are not public)? It says so, and where you
  would be.

**How it works**

- Boards are counted on request from the library rows: global boards are kept in Valkey for a
  minute, a reader's friends board for half a minute.
- Global boards list only people whose trophies (and, per game, library) are public; friends
  boards only people who do not hide them from friends. Flagged trophies (3.2, planned) will stay
  off global boards.

---

## 3.13 Notifications

**Status:** built: a stored list with an unread count, the bell on the website, in the macOS
launcher (with a toast for new ones) and on the phone; Web Push to browsers when none of the
person's devices is connected; a mail digest. Planned: push to the phone (APNs, FCM).

**What the user sees**

- Notifications for a friend request or its acceptance, messages (while away), a party or game
  invite, a missed call, someone asking to join your looking-for-group post or accepting you on
  one, and a moderator's warning.
- Each kind can be turned off in the settings, except a moderator's warning; the mail digest is off
  unless turned on.
- W: the bell and `/notifications`; browser notifications are turned on per device.

**How it works**

- A notification is a row: kind, who did it, what it is about. Messages gather in the one unread
  notification of their conversation, counting how many came. Reading on one device marks it read
  on the others; when something stops being true (a request withdrawn, a party that ended) an
  unread notification is taken back.
- Messages become notifications only while none of the person's devices has a gateway socket
  open; a connected client shows them itself.
- **Web Push** with the server's own VAPID keys (no push service account needed); a subscription is
  tied to its sign-in, so signing out ends it. Texts in the device's language.
- **Digest**: at most one mail per 6 hours, of messages and friend requests that waited unread for
  a while; each notification is mailed once.
- Read notifications go after 90 days, every one after 180.

---

## 3.14 Finding players

**Status:** built on the website: the looking-for-group board (`/find`), Live now with public
parties and share plays (`/find/live`), people (`/find/people`) and game hubs (`/games/<title id>`).
In the launchers and the phone: planned.

**What the user sees**

- **Looking for group**: a post for a game says what for (co-op over share play, an online game, a
  party to talk in, help with trophies), when (now or later today), languages, a rough region, how
  many players and a short note. Others press **I'm in**; the poster accepts or declines. On yes,
  the player is invited into the poster's share play (co-op) or party. A post closes when full,
  when its poster closes it, or by itself within a day.
- **Live now**: open share plays anyone may watch, and the parties and share plays their hosts
  listed in public, by game and language.
- **People**: by handle or name, people you may know (friends in common, games you both play, a
  shared language), and who plays one of your games.
- **Game hubs**: see 3.7.

**How it works**

- Who sees whom always follows blocks (either way) and each person's privacy settings; discovery
  shows only people who chose it or whose library is public.
- The board and the public lists update live: a socket watches topics (`lfg`, `lfg:<title>`,
  `discover`, `discover:<title>`) that say only "changed", never who posted, so the client reads
  the list again and blocks are applied on the server.
- At most 3 open posts per person; new accounts (under a day old or with few trophies) may post
  and ask to join less often. Posts can be reported, and a moderator can take one off the board.

---

## 3.15 Compatibility list

**Status:** built: reports from the macOS launcher ("How did it run?" after a session, and from a
game's options) and from the website; the list at `/compatibility` with a page per game; the
community's verdict in the launcher's game info.

**What the user sees**

- After a session the launcher may ask **How did *game* run?** with five answers: Nothing, Boots,
  Menus, In game, Playable. "Don't ask after games" turns the question off; a report can still be
  sent from the game's options.
- The list: each game with its verdict per platform (macOS, Windows, Linux), the version tested
  and how many reports; a game's page lists the reports with machine, OS, engine and FPS.

**How it works**

- A report carries the title ID, platform, status, the launcher's and the engine's versions, and
  what the launcher knows (the machine, the OS, the average FPS, the game's version), plus an
  optional note without links. The launcher shows what it sends with it.
- The verdict per game and platform: of the reports on the newest launcher version anyone tested
  (each person's latest only), the status most of them gave; a tie goes to the better one. It is
  worked out again whenever a report arrives.
- You can delete your own reports; when an account is deleted its reports stay without who sent
  them.
