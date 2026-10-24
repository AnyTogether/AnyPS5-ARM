# 7. Clients

Four doors: the launcher on macOS (AnyPS5-ARM, Swift), the launcher on Windows and Linux
([AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), Flutter), the phone app (Flutter,
in AnyPS5-ARM's `mobile/`) and the website (in the AnyTogether repository). Every one of them is a
full AnyTogether client; none is second. [Platforms](12-platforms.md) lists what each platform
does differently.

Status on 2026-10-25: AnyPS5-ARM 0.2.15 (the macOS launcher), phone app 1.11.0 and AnyPS5
Desktop 0.1.1 are released; the website is released as it is built. Everything marked built
below is in those releases.

| | Sign-in | Friends | Profiles | Play time, trophies | Messages | Parties, voice, calls | Join a friend's game | Activity, leaderboards, notifications | Share play | Theme Hub | Compatibility |
|---|---|---|---|---|---|---|---|---|---|---|---|
| macOS launcher | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | hosts, watches, plays along | ✓ (lists, installs, shares) | ✓ (asks after a session) |
| Phone app | ✓ | ✓ | ✓ (edit yours) | - | ✓ | ✓ | - | ✓ | watches, plays along | wears the launcher's theme | - |
| Website | ✓ (with passkeys) | ✓ | ✓ | on profiles | ✓ | ✓ | - | ✓ (with browser push) | watches, plays along | ✓ | ✓ |
| AnyPS5 Desktop | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | planned | planned | planned | planned |

Finding players (the looking-for-group board, Live now, people, game hubs) and the admin page
are on the website only for now. Every client can point at another AnyTogether server, for one
someone runs themselves (the launcher tells a paired phone which server it uses).

## 7.0 Tested together

Each client is tested against a pretend server of its own, and all of them together against one
real local stack (`e2e/` in the AnyTogether repository): a driver in each client's repository runs
the client's real code, and the website is driven through its real pages in headless Chrome. Last
run 2026-10-24, every check passed:

| Scenario | macOS launcher | Phone | AnyPS5 Desktop | Website |
|---|---|---|---|---|
| 1 Sign-in: email codes; hand-off phone → Mac, Mac → phone, phone → AnyPS5 Desktop; device codes approved on the website | ✓ | ✓ | ✓ | ✓ |
| 2 Friends: a request accepted on the website; presence on the others; unfriending; blocking | ✓ | ✓ | ✓ | ✓ |
| 3 Messages: a direct message with live unread badge and read state; a group of four, typing, unread counts | ✓ | ✓ | ✓ | ✓ |
| 4 Parties: started on the website, joined by the three apps, the lead handed over, a member removed | ✓ | ✓ | ✓ | ✓ |
| 5 Calls: party voice and a 1:1 call, signalling through the gateway, relay credentials, mute both ways | ✓ | ✓ | built, not yet in the run | ✓ |
| 6 Sync: play time and trophies on the website's profile, leaderboard and feed; privacy hiding them | ✓ | - | ✓ | ✓ |
| 7 Game sessions: the Mac hosts, AnyPS5 Desktop joins after the version guard, properties and signals | ✓ | - | ✓ | - |

Share play, the Theme Hub, notifications and finding players are not in the cross-client run yet;
share play is tested in the launcher with host and viewer in one process.

## 7.1 The macOS launcher (Swift)

### The code

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (testable, no UI), built:

| File | Job |
|---|---|
| `TogetherClient.swift` | who is signed in; HTTP calls to `/api/v1`, token refresh with a single in-flight refresh, problem-details errors, the `AnyTogether-Client` header; sign-in by email code, phone hand-off and device code; refresh token in the Keychain |
| `TogetherServer.swift` | which AnyTogether the launcher talks to: AnyTogether's own by default, another one from Settings (https only, http for this Mac) or `ANYTOGETHER_URL` |
| `TogetherSocket.swift` | the realtime gateway: hello, heartbeats with presence, resume, reconnect with backoff |
| `TogetherSync.swift` | play sessions and trophy sets with earned trophies, kept in an outbox on disk and sent in the order the server needs, each once; a trophy earned while playing goes up at once |
| `TogetherAccount.swift`, `TogetherProfile.swift` | your profile, others' profiles, privacy |
| `TogetherFriends.swift` | friends with what they are doing now, requests, blocks |
| `TogetherMessages.swift` | conversations, groups, typing |
| `TogetherParties.swift`, `TogetherCalls.swift` | parties with their voice call, 1:1 calls, mute, ICE servers, signalling |
| `TogetherGameSessions.swift` | game sessions for joining a friend's game |
| `TogetherSharePlay.swift` | share play's calls and signals, and the pad router that lets only a viewer holding pad 2-4 reach the game |
| `TogetherFeed.swift`, `TogetherLeaderboards.swift`, `TogetherNotifications.swift` | the activity feed and reactions, leaderboards, notifications |
| `TogetherThemes.swift`, `TogetherCompat.swift` | the Theme Hub, compatibility reports and verdicts |

`Sources/AnyPS5SharePlay/` holds share play's WebRTC: `SharePlayHost` (one H.264 track per viewer,
the "audio" and "pad" data channels), `SharePlayWatcher` and `SharePlaySpeaker` (a viewer's side).

### Screens

| Screen | What it is |
|---|---|
| Settings → AnyTogether | sign in with an email code, the website's device code or the paired phone, sign out; your name, bio, country, handle and who sees what; "Let friends join my game"; the Server row |
| Friends panel | list with presence and games; requests; add by handle; per friend: profile, message, call, invite to party, **Play with** a joinable game, **Watch** a share play; while a game runs, **Share play** |
| Profile view | your card and friends': games, hours, trophies and points, the latest trophies with their rarity, recent activity |
| Activity | friends' trophies, first plays, long sessions and milestones, with reactions |
| Leaderboard | trophy points overall, a game's points, play time or completion; friends or everyone; your rank |
| Notifications | a bell with the unread count in the top bar, the list, a toast for new ones |
| Messages | conversations, groups, typing |
| Party panel | members, invites, leader actions, **voice**: microphone on and off, push-to-talk on ⌥V (a global key, so it works over a game), a ring around whoever speaks |
| Share play (host) | who watches, the link of each (direct or relayed, round trip, picture size and rate), **Let … play as player N**, take a pad back, take someone out, invite, "Friends can walk in", viewers at most, stop |
| Share play (viewer) | the friend's game full screen with its sound; the controller is their player 2-4 once they hand a pad; the PS button leaves |
| Themes | the Hub on AnyTogether (the GitHub folder while a server has none), **Share on the Hub** when signed in, `anyps5://theme/<id>` links |
| How did it run? | after a session, one tap for a compatibility report; the community's verdict in the game's info |
| Sign-in with Apple, Google, Discord | planned |

Voice and share play use Google's WebRTC (the prebuilt `stasel/WebRTC` package, BSD-3-Clause),
carried in the app with its licence. The app has the microphone usage string; share play, Remote
Play and clips ask for the screen recording permission once.

While a game runs with joining allowed, the launcher opens a game session for it (title, game
version, engine build) and writes the session, the user and their role for the engine's online
bridge; `ANYPS5_TOGETHER_SESSION` tells the game where (see
[Realtime](06-realtime-voice-shareplay.md) 6.7). The bridge itself is on the `online-play` branch,
off by default.

### Beside AnyTogether: engines and crash reports

Two launcher features that are not AnyTogether's but matter to everyone who reports a game:

- **Engine picker** (Settings → Engine, and per game): the engine builds attached to AnyPS5-ARM's
  releases (`AnyPS5-toolkit-macos-<version>.zip`) are listed with their date and notes, downloaded
  with progress, checked against GitHub's SHA-256 and their own manifest (and again before each
  unlock), and kept side by side in Application Support; one is chosen for every game or for one
  game. A folder of your own build can be used too. A game unlocked with another engine than the
  chosen one offers **Update and Play**; saves and trophies stay. The engine version goes with each
  compatibility report and each game session (the version guard).
- **Crash reports**: when a game stops on an error, a crash or before its window appears, the
  launcher waits a few seconds for macOS's crash report and opens a panel: the reason in plain
  words, the Mac, the engine, the end of the log. **Export Report** saves the log, the crash
  report, the last unlock's output and the game's settings in one file; **Open Issue** shows what
  will be shared and opens a pre-filled GitHub issue (AnyPS5-ARM's, or the engine's form upstream).
  The home folder, names, email addresses and AnyTogether tokens are taken out first. **Detailed
  logging (trace)** and a one-shot **Play with Detailed Logging** record more for a hard bug.

### Rules for the launcher

- **Nothing blocks playing.** Every call is async with a timeout; failures go to the outbox or
  are shown as a quiet status, never a modal.
- **Signed out is a full experience.** No AnyTogether item appears in a way that nags; one row in
  Settings → AnyTogether.
- **Permissions asked when used**: microphone the first time voice is joined, screen recording at
  the first share play (already asked by Remote Play and clips).
- **Tests** like the phone server's: a fake API and gateway in-process; the outbox tested against
  offline/online flips; the cross-client run against the real server.
- **Signing**: release builds are signed with Developer ID, which keeps the microphone and screen
  recording permissions across updates.

## 7.2 The Windows and Linux launcher (AnyPS5 Desktop)

[AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) is the launcher's port to Windows and
Linux, a public project (GPL-2.0) written in Flutter: the same PS5-style home screen, library,
unlocking, controls, trophies, saves and phone controller. It connects to AnyTogether itself, from
the same API and gateway the other clients use; nothing on the server is specific to macOS. 0.1.1
is an early preview.

**Installing**: a Windows installer (Inno Setup, `AnyPS5-Desktop-Setup-<version>-x64.exe`: per user
by default, no admin, Start menu shortcut, an uninstaller, a running launcher closed before an
upgrade) or a portable zip; on Linux an AppImage, a `.deb` (`/opt/anyps5-desktop`) or a tar.gz,
built on Ubuntu 22.04. The builds are not code-signed yet, so SmartScreen may warn.

**The engine downloads itself**: the first start's last step offers **Download the AnyPS5 engine**.
The launcher reads the latest release of upstream [AnyPS5](https://github.com/boykopovar/AnyPS5),
downloads the relinker and system libraries for the system (resumable, each file checked against
the SHA-256 GitHub publishes; a file without one only on a second, explicit choice), unpacks them
without letting any name or link leave the folder, and keeps one folder per version. Settings →
AnyPS5 Engine shows the engine in use, checks for updates, lists the versions, deletes others, or
takes a folder of your own. When a newer engine is out, installed games offer **Update and Play**.
The engine build a game was installed with is what the game-session version guard compares.

Its AnyTogether part (`lib/core/together/`), built and released:

| Part | What it does |
|---|---|
| Sign-in | an email code, a code approved on the website (passkeys and the website's other ways in work there), or the paired phone in one tap, both ways; another server in Settings or `ANYTOGETHER_URL` |
| Live | the gateway socket, presence (in a game, with its title ID, while one runs), friends |
| Sync | play sessions and trophies through an outbox on disk (`Together/outbox.json`): offline loses nothing, nothing counts twice |
| Friends, messages, party | requests, adding by handle, what each friend plays; conversations with quick replies a controller can send and typing both ways; parties with voice |
| Voice | the website's protocol through `flutter_webrtc`, Opus tuned for voice; a talk key (V by default) that works over a game: `GetAsyncKeyState` on Windows, `XQueryKeymap` on X11 |
| Profiles | yours and a friend's: games with play time and trophy progress, recent trophies with rarity |
| Join a friend's game | a game session while a game runs; Join checks the game is installed, the game version and the engine build, joins and starts it; the session for the engine's online bridge in `Together/game-session.json` |
| Tokens | Windows: a file sealed with DPAPI for the current user; Linux: the Secret Service through `secret-tool` when a keyring answers, else a 0600 file in a 0700 folder |

Planned: share play (host and viewer), the feed, leaderboards, notifications, the Theme Hub,
compatibility reports, provider sign-in through the browser. What the launcher needs from its
platform for share play:

| Need | Windows | Linux |
|---|---|---|
| Game capture | Windows.Graphics.Capture (the game window) | PipeWire screencast through xdg-desktop-portal (asks the user once) |
| Game sound | WASAPI process loopback (the game's process only) | PipeWire stream of the game's node |
| H.264 low latency | Media Foundation hardware MFT, or NVENC / AMF / Quick Sync directly | VA-API (Intel, AMD) or NVENC |

The phone app (7.3) works with this launcher as it does with the macOS one: AnyPS5 Desktop speaks
the phone protocol (pairing on WebSocket port 47700, pad by UDP, the cable paths), written down in
[Platforms](12-platforms.md) 12.4. The pad reaching a game needs the engine's remote pad bridge,
which is POSIX-only in the engine today (Linux works; a Winsock port for Windows is on AnyPS5-ARM's
`remotepad-winsock` branch).

## 7.3 The phone app (Flutter)

### The code

`mobile/lib/together/`, built: `together_account.dart` (sign-in by email code or with the Mac's
account through the hand-off, approving a launcher's hand-off, another server),
`together_socket.dart`, `together_hub.dart`, `people.dart`, `friends.dart`, `profiles.dart`,
`messages.dart`, `groups.dart`, `typing.dart`, `parties.dart`, `calls.dart`, voice in `voice.dart`,
`voice_mesh.dart` and `voice_webrtc.dart`, `feed.dart` and `activity.dart`, `leaderboards.dart`,
`notifications.dart`, and share play in `share_play.dart` and `share_play_webrtc.dart`
(`flutter_webrtc`, relay credentials renewed before they run out).

### Screens (1.11.0)

| Screen | What it is |
|---|---|
| Account | an email code, or the Mac's account in one tap; edit your profile and picture |
| Approve | "Sign in <Mac/PC name>?" when a launcher asks (hand-off): one tap |
| Friends | presence, requests, profiles; opens without a computer nearby too |
| Messages | conversations and groups, typing |
| Party and calls | members, invites, voice; 1:1 calls with a friend, mute everyone sees |
| Activity, leaderboards | the feed with reactions; boards overall and per game |
| Notifications | the bell and its list |
| Share play | **Watch** from Friends or an invite: the picture on a receive-only WebRTC connection, the sound through Remote Play's speaker; when the host hands a pad, the Remote Play pad lies over the picture and plays as their player 2-4, with rumble and light bar; a chip with whose game, which player, round trip, fps and height |
| Push notifications for messages, invites, friend requests | planned |

### Rules for the phone

- The pad over the local network stays exactly as it is; AnyTogether never sits between the
  phone and the computer when they are together.
- Push (planned): APNs (iOS) and FCM (Android) tokens registered per session; notifications carry
  only IDs and a short text; content is fetched when opened.
- Battery: the gateway socket is closed in the background (push takes over once it exists),
  opened on resume.

## 7.4 The website (Next.js)

All built unless marked.

| Page | Path |
|---|---|
| Home: what AnyTogether is; signed in, the friends' feed with reactions | `/` |
| Sign in (email code or link, passkey; the first time creates the account) | `/login`, `/login/email` |
| Approve a launcher's device code | `/link` |
| Profile (public, SSR) with games, play time, trophies and recent activity; report someone from it | `/u/<handle>` |
| Friends, messages and groups, party with voice; calls to a friend from any page | `/friends`, `/messages`, `/party` |
| Watch a friend's share play, and play along with a controller or the keyboard when handed a pad | `/watch/<id>` |
| Find players: the looking-for-group board; Live now with public parties and share plays; people | `/find`, `/find/live`, `/find/people` |
| Game hub: who plays it now, posts, public parties and share plays, top players, how it runs, themes | `/games/<title id>` |
| Leaderboards | `/leaderboards` |
| Theme Hub, a theme, sharing one, your themes | `/themes`, `/themes/<id>`, `/themes/new`, `/themes/mine` |
| Compatibility list and a game's reports; sending a report | `/compatibility`, `/compatibility/<title id>` |
| Downloads: the macOS launcher, the phone app, AnyPS5 Desktop, from their latest releases | `/download` |
| Notifications, and browser push turned on per device | `/notifications` |
| Settings: profile, avatar, privacy, discovery, notifications and the mail digest, passkeys, signed-in devices, sign out everywhere, download my data, delete the account | `/settings` |
| The moderators' page: reports with their verdicts, accounts, bans, the audit log (admins only; others get "not found") | `/admin` |
| Rules, privacy policy, terms, KVKK notice | planned |
| Open Graph images for profiles and game hubs | planned |

The look follows the launcher's console style (dark, the blue/violet/teal accents, Space Grotesk
and JetBrains Mono), on phones too. English by default, Turkish with a switcher. The browser never
holds a token: the site's server keeps them in HttpOnly cookies and asks the API for a one-time
ticket when the page opens the gateway socket. Every page carries security headers (no framing,
a strict referrer policy, the microphone only for the site itself), and the site's own routes
refuse changes sent from other sites' pages.

## 7.5 Shared pieces

- **Types**: today each client writes its types from the Zod schemas in `packages/shared`;
  generating Swift and Dart types from an OpenAPI document is planned.
- **Strings**: the error `code`s and event names translated in each client (English, Turkish).
- **The phone protocol** (pairing, pad, cable, the AnyTogether hand-off) and the **pad packet** are
  specified once, so the macOS launcher, AnyPS5 Desktop, the phone app and share play's pad
  channel all interoperate.
- **Assets**: the AnyTogether mark (the two rings of the favicon) in the launcher, the phone and
  the web.
