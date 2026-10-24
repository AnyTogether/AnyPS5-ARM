# 7. Clients

The three doors. The launcher and the phone app live in AnyPS5-ARM; the website lives in the
AnyTogether repository.

## 7.1 The launcher (macOS, Swift)

### New code

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (testable, no UI):

| File | Job |
|---|---|
| `TogetherClient.swift` | HTTP calls to `/v1`, token refresh with a single in-flight refresh, problem-details errors, the `AnyTogether-Client` header |
| `TogetherAuth.swift` | device link (RFC 8628): request a code, poll, store the refresh token in the Keychain |
| `TogetherSocket.swift` | the realtime gateway: hello, heartbeats with presence, resume, reconnect with backoff (1, 2, 4 … 30 s, with jitter) |
| `TogetherOutbox.swift` | an append-only queue in SQLite (`Application Support/AnyPS5/Together/outbox.sqlite`) for sessions, trophies, catalogue entries, reports; sends in batches when online, keeps order per kind, drops nothing |
| `TogetherModels.swift` | types generated from the OpenAPI document |
| `TrophySync.swift` | turns the launcher's `TrophySet` into trophy-set uploads and earned trophies |
| `SessionRecorder.swift` | turns game start/stop (already tracked for Discord and save sync) into sessions |
| `PartyVoice.swift` | LiveKit Swift SDK: join a party room, mic, mute, push-to-talk, speaking events |
| `SharePlay.swift` | publishes `RemotePlay`'s frames and sound to LiveKit; receives pad packets from the data channel into a `RemoteServer` bridge slot |

App target (`Sources/AnyPS5/`):

| Screen | What it is |
|---|---|
| Top bar | the profile chip becomes the avatar with a status dot; a Friends button with the online count; a Messages button with unread count |
| Sign-in panel | "Sign in to AnyTogether": the code, a QR, "Open on this Mac" (opens the web link page) |
| Profile overlay | your card (wearing your theme), edit name/bio/avatar/showcase, privacy |
| Friends panel | list with presence and games; requests; add by handle or QR; per friend: profile, message, invite to party |
| Messages panel | conversations and a chat view, usable with a controller (the on-screen keyboard is the macOS one; a pad user can send quick replies) |
| Party card | a floating card at the side: members, speaking rings, mute, push-to-talk hint, Share play button; stays as a small overlay above a game (like the trophy banner) |
| Feed panel | friends' activity |
| Theme Hub | the existing Themes screen reads AnyTogether's index; "Share on the Hub" uploads |
| Game page | friends who play it, rarity on trophies, community compatibility, "How did it run?" prompt after a session (opt-in) |

### Rules for the launcher

- **Nothing blocks playing.** Every call is async with a timeout; failures go to the outbox or
  are shown as a quiet status, never a modal.
- **Signed out is a full experience.** No AnyTogether item appears in a way that nags; one row in
  Settings → AnyTogether, one card on first start after the update ("New: AnyTogether", dismissed
  forever with one press).
- **Permissions asked when used**: microphone at the first party voice, screen recording at the
  first share play (already asked by Remote Play/Clips).
- **Tests** like the phone server's: a fake API and gateway in-process; outbox tested against
  offline/online flips; device link tested with a fake approval.
- **Signing**: to keep the microphone and screen recording permissions across updates, release
  builds need a stable signature (Developer ID Application), see open questions.

## 7.2 The phone app (Flutter)

### New code

`mobile/lib/together/`: `together_client.dart`, `together_socket.dart`, `auth.dart` (email,
Apple, Discord; device-link approval), `party_voice.dart` (LiveKit Flutter), `share_play_view.dart`.

### Screens

| Screen | What it is |
|---|---|
| Account | sign in / sign up; or "Use the launcher's account": the phone, paired with the launcher, asks it to approve a session for the phone (no password typed) |
| Approve | scanning the launcher's QR or typing its code approves the Mac in one tap |
| Friends, Messages, Feed | tabs beside the existing launcher mode; push notifications for messages, invites, friend requests |
| Party | members, voice (the phone can carry it while being the pad), share play viewer |
| Share play viewer | the stream full screen with the pad over it, the same as Remote Play's pad over the picture today; works from anywhere |
| Profile | your card and others' |

### Rules for the phone

- The pad over the local network stays exactly as it is; AnyTogether never sits between the
  phone and the Mac when they are together.
- Push: APNs (iOS) and FCM (Android) tokens registered per session; notifications carry only
  IDs and a short text; content is fetched when opened.
- Battery: the gateway socket is closed in the background (push takes over), opened on resume.

## 7.3 The website (Next.js)

| Page | Path |
|---|---|
| Landing (replaces "Coming soon") | `/` |
| Sign in / up / link a device | `/login`, `/signup`, `/link` |
| Profile (public, SSR, Open Graph image) | `/u/<handle>` |
| Library, trophies of a profile | `/u/<handle>/games`, `/u/<handle>/trophies/<title id>` |
| Game page | `/g/<title id>` |
| Friends, messages, feed, party (signed in) | `/friends`, `/messages`, `/feed`, `/party/<id>` |
| Theme Hub | `/themes`, `/themes/<id>` |
| Leaderboards | `/leaderboards` |
| Downloads | `/download` |
| Settings, privacy, data export, delete account | `/settings/...` |
| Rules, privacy policy, terms, KVKK notice | `/rules`, `/privacy`, `/terms`, `/kvkk` |

The look follows the coming-soon page (dark, `#07080c`, the blue/violet/teal accents, Space
Grotesk and JetBrains Mono) and the launcher's console style. A signed-in user's own pages wear
their profile theme. English and Turkish, by the browser's language and a switch.

## 7.4 Shared pieces

- **Types**: generated from the OpenAPI document for Swift (swift-openapi-generator) and Dart
  (openapi-generator dart-dio or a small hand generator), so the three clients agree.
- **Strings**: the error `code`s and event names translated in each client (English, Turkish).
- **Assets**: the AnyTogether mark (the two rings of the favicon) in the launcher, the phone and
  the web.
