# 7. Clients

Four doors: the launcher on macOS (AnyPS5-ARM, Swift), the launcher on Windows and Linux
([AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), Flutter), the phone app (Flutter,
in AnyPS5-ARM's `mobile/`) and the website (in the AnyTogether repository). Every one of them is a
full AnyTogether client; none is second. [Platforms](12-platforms.md) lists what each platform
does differently.

Status on 2026-10-24. "Next release" means on AnyPS5-ARM's `main` but not yet released (the last
release is v0.2.13-arm).

| | Sign-in | Friends | Profiles | Play time, trophies | Messages | Parties, voice | Join a friend's game |
|---|---|---|---|---|---|---|---|
| macOS launcher | released (0.2.13) | released | next release | released | next release | next release | next release |
| Phone app | released (1.9.1) | next release | - | - | next release | next release | - |
| Website | built | built | built | shown on profiles | built | built | - |
| AnyPS5-Desktop | planned | planned | planned | planned | planned | planned | planned |

Every client can also point at another AnyTogether server, for one someone runs themselves
(macOS launcher and phone: next release; the launcher tells a paired phone which server it uses).

## 7.1 The macOS launcher (Swift)

### The code

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (testable, no UI), built:

| File | Job |
|---|---|
| `TogetherClient.swift` | who is signed in; HTTP calls to `/api/v1`, token refresh with a single in-flight refresh, problem-details errors, the `AnyTogether-Client` header; sign-in by email code, phone hand-off and device code; refresh token in the Keychain |
| `TogetherServer.swift` | which AnyTogether the launcher talks to: AnyTogether's own by default, another one from Settings (https only, http for this Mac) or `ANYTOGETHER_URL` |
| `TogetherSocket.swift` | the realtime gateway: hello, heartbeats with presence, resume, reconnect with backoff |
| `TogetherSync.swift` | play sessions and trophy sets with earned trophies, kept in an outbox on disk and sent in the order the server needs (this Mac registered, the game taught, the set uploaded, then sessions and trophies), each once; a trophy earned while playing goes up at once |
| `TogetherAccount.swift`, `TogetherProfile.swift` | your profile, others' profiles, privacy |
| `TogetherFriends.swift` | friends with what they are doing now, requests, blocks |
| `TogetherMessages.swift` | conversations and messages |
| `TogetherParties.swift` | parties: up to eight friends with a leader and, while one runs, a voice call |
| `TogetherCalls.swift` | calls, ICE servers from the API, WebRTC signalling through the socket |
| `TogetherGameSessions.swift` | game sessions for joining a friend's game |

App target (`Sources/AnyPS5/`):

| Screen | What it is | Status |
|---|---|---|
| Settings → AnyTogether | sign in with an email code or with the paired phone ("Sign in with my phone"), sign out; your name, bio, country, handle and who sees what; "Let friends join my game"; the Server row | sign-in released; the rest next release |
| Friends panel | list with presence and games; requests; add by handle; per friend: profile, message, invite to party, **Play with** a joinable game | released; profiles, messages, parties, Play with next release |
| Profile view | your card and friends': avatar, name, handle, bio; games, hours, trophies and points; the games with play time and progress; the latest trophies with their rarity | next release |
| Messages | conversations and a chat view | next release |
| Party panel | members, invites, leader actions, **voice**: microphone on and off, push-to-talk on ⌥V (a global key, so it works over a game), a ring around whoever speaks, also on the top bar's party button | next release |
| Game invites | cards and banners for invitations to a friend's game, with Decline | next release |
| Sign-in with Apple, Google, Discord | the buttons for the providers the API already checks | planned |
| Feed panel, Theme Hub on AnyTogether, game page, share play | | planned |

Voice uses Google's WebRTC (the prebuilt `stasel/WebRTC` package, BSD-3-Clause, arm64 and x86_64),
carried in the app with its licence. The app has the microphone usage string, and the Developer
ID signature gives it the audio input entitlement under the hardened runtime.

While a game runs with joining allowed, the launcher opens a game session for it (title, game
version, engine build) and writes the session, the user and their role for the engine's online
bridge; `ANYPS5_TOGETHER_SESSION` tells the game where (see
[Realtime](06-realtime-voice-shareplay.md) 6.7). The bridge itself is on the `online-play` branch,
off by default.

### Rules for the launcher

- **Nothing blocks playing.** Every call is async with a timeout; failures go to the outbox or
  are shown as a quiet status, never a modal.
- **Signed out is a full experience.** No AnyTogether item appears in a way that nags; one row in
  Settings → AnyTogether, one card on first start after the update ("New: AnyTogether", dismissed
  forever with one press).
- **Permissions asked when used**: microphone the first time voice is joined, screen recording at
  the first share play (already asked by Remote Play/Clips).
- **Tests** like the phone server's: a fake API and gateway in-process; the outbox tested against
  offline/online flips; sync tested against the real API too.
- **Signing**: release builds are signed with Developer ID, which keeps the microphone and screen
  recording permissions across updates.

## 7.2 The Windows and Linux launcher (AnyPS5-Desktop)

[AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) is the launcher's port to Windows and
Linux, a public project (GPL-2.0) written in Flutter: the same PS5-style home screen, library,
unlocking, controls, trophies, saves and phone controller. It connects to AnyTogether itself, from
the same API and gateway the other clients use; nothing on the server is specific to macOS.
Status: the launcher is in development; its AnyTogether part is planned. Being Dart like the phone
app, it can share most of the phone's AnyTogether client (`mobile/lib/together/`): REST and token
refresh, the socket, friends, messages, parties and voice with `flutter_webrtc`.

What the launcher needs from its platform:

| Need | Windows | Linux |
|---|---|---|
| Secure token store | Credential Manager | Secret Service (GNOME Keyring, KWallet) |
| Sign-in with providers | the default browser and a loopback redirect (`127.0.0.1:<random port>`, RFC 8252) | the same |
| Microphone with echo cancellation | WebRTC's audio processing | WebRTC's audio processing (PipeWire/PulseAudio input) |
| Push-to-talk key | `RegisterHotKey` | the desktop's global shortcut portal |
| Trophies, play sessions | as the launcher already reads them per game | the same |
| Game capture (share play) | Windows.Graphics.Capture (the game window) | PipeWire screencast through xdg-desktop-portal (asks the user once) |
| Game sound (share play) | WASAPI process loopback (the game's process only) | PipeWire stream of the game's node |
| H.264 low latency (share play) | Media Foundation hardware MFT, or NVENC / AMF / Quick Sync directly | VA-API (Intel, AMD) or NVENC |

The screens are the same as the macOS launcher's (7.1), in its own PS5-style interface, with the
same strings (English, Turkish) taken from the shared error codes and event names.

The phone app (7.3) works with this launcher as it does with the macOS one: AnyPS5-Desktop already
speaks the phone protocol (pairing on WebSocket port 47700, pad by UDP, the cable paths), written
down in [Platforms](12-platforms.md) 12.4.

## 7.3 The phone app (Flutter)

### The code

`mobile/lib/together/`, built: `together_account.dart` (sign-in by email code or with the Mac's
account through the hand-off, approving the Mac's hand-off, another server), `together_socket.dart`
(the realtime socket, online while signed in), `together_hub.dart`, `people.dart`, `friends.dart`,
`messages.dart`, `parties.dart`, and voice in `voice.dart`, `voice_mesh.dart` and
`voice_webrtc.dart` (`flutter_webrtc`, relay credentials renewed before they run out).

### Screens

| Screen | What it is | Status |
|---|---|---|
| Account | an email code, or the Mac's account in one tap; the first sign-in creates the account | released (1.9.1) |
| Approve | "Sign in <Mac/PC name>?" when a launcher asks (hand-off): one tap | released |
| Friends | from a people button on the home screen | next release |
| Messages | side by side with the conversations | next release |
| Party | members, invites, voice | next release |
| Push notifications for messages, invites, friend requests | | planned |
| Feed, profiles, share play viewer | | planned |

### Rules for the phone

- The pad over the local network stays exactly as it is; AnyTogether never sits between the
  phone and the computer when they are together.
- Push (planned): APNs (iOS) and FCM (Android) tokens registered per session; notifications carry
  only IDs and a short text; content is fetched when opened.
- Battery: the gateway socket is closed in the background (push takes over), opened on resume.

## 7.4 The website (Next.js)

| Page | Path | Status |
|---|---|---|
| Landing | `/` | built |
| Sign in (email code or link, passkey; the first time creates the account) | `/login`, `/login/email` | built |
| Approve a launcher's device code | `/link` | built |
| Profile (public, SSR) with games, play time and trophies; report someone from it | `/u/<handle>` | built; Open Graph image planned |
| Friends, messages, party with voice (signed in) | `/friends`, `/messages`, `/party` | built |
| Settings: profile, avatar, privacy, passkeys, signed-in devices, sign out everywhere, download my data, delete the account | `/settings` | built |
| Game page | `/g/<title id>` | planned |
| Feed | `/feed` | planned |
| Theme Hub | `/themes`, `/themes/<id>` | planned |
| Leaderboards | `/leaderboards` | planned |
| Downloads | `/download` | planned |
| Rules, privacy policy, terms, KVKK notice | `/rules`, `/privacy`, `/terms`, `/kvkk` | planned |

The look follows the coming-soon page (dark, `#07080c`, the blue/violet/teal accents, Space
Grotesk and JetBrains Mono) and the launcher's console style. English by default, Turkish with a
switcher. The browser never holds a token: the site's server keeps them in HttpOnly cookies and
asks the API for a one-time ticket when the page opens the gateway socket.

## 7.5 Shared pieces

- **Types**: today each client writes its types from the Zod schemas in `packages/shared`;
  generating Swift and Dart types from an OpenAPI document is planned.
- **Strings**: the error `code`s and event names translated in each client (English, Turkish).
- **The phone protocol** (pairing, pad, cable, the AnyTogether hand-off) and the **pad packet** are
  specified once, so the macOS launcher, AnyPS5-Desktop and the phone app all interoperate.
- **Assets**: the AnyTogether mark (the two rings of the favicon) in the launcher, the phone and
  the web.
