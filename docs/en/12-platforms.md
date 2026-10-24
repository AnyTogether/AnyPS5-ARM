# 12. Platforms

AnyTogether is for **every AnyPS5 launcher**: the macOS launcher (AnyPS5-ARM, Swift), the Windows
and Linux launcher ([AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), Flutter), the
phone app (iOS and Android) and the web. This document
lists what is the same everywhere, what each platform does its own way, and writes down the
phone protocol so any launcher can talk to the phone app.

## 12.1 The same everywhere (the contracts)

| Contract | Defined in | Used by |
|---|---|---|
| REST API `/api/v1` | the Zod schemas in `packages/shared` of the public repository; an OpenAPI 3.1 document generated from them is planned | all clients |
| Realtime gateway `/rt` | `packages/shared` event and signalling types; [API](04-api.md) 4.8 | all clients |
| Sign-in | email codes, passkeys (WebAuthn, the website), hand-off, device code (RFC 8628), OpenID Connect with PKCE (RFC 7636) and native-app redirect rules (RFC 8252) | all clients |
| Calls | WebRTC: Opus voice (built) | every launcher, the phone, the web |
| Share play | WebRTC from the host to each viewer: an H.264 video track (no B-frames), the game's sound as Remote Play's PCM packets on a lossy data channel `audio`, a viewer's pad as 80-byte packets on a lossy data channel `pad` (built); the host always offers | the hosting launcher, every viewer |
| Online play | data channels for the game's own traffic (planned) | every launcher |
| Pad packet | the 80-byte input packet below (12.4) | phone → launcher, share play viewer → host |
| Game sessions | [API](04-api.md) 4.6: title ID, game version, engine build, the version guard | every launcher |
| Trophy and session data | [Data model](05-data-model.md) | every launcher |
| Theme file | `.anyps5theme` (zip: `theme.json` + optional picture/video and music) | every launcher, the Hub |

## 12.2 What each platform does its own way

| Need | macOS launcher | Windows launcher | Linux launcher | Phone | Web |
|---|---|---|---|---|---|
| Language | Swift | Dart (Flutter, AnyPS5-Desktop) | the same | Dart (Flutter) | TypeScript |
| AnyTogether client | `AnyPS5Core/Together`, `AnyPS5SharePlay` | AnyPS5 Desktop's own, `lib/core/together` (built) | the same | `mobile/lib/together` | `apps/web` |
| Sign-in | email code, phone hand-off, device code (built); Apple native, `ASWebAuthenticationSession` (planned) | email code, the website's device code, phone hand-off (built); providers through the default browser + loopback (planned) | the same | email code, the Mac's account by hand-off (built); native Apple/Google, Discord (planned) | email code or link, passkeys (built) |
| Secure token store | Keychain | a file sealed with DPAPI for the current user | Secret Service through `secret-tool` (GNOME Keyring, KWallet), else a 0600 file | Keychain / Keystore | HttpOnly cookie |
| WebRTC | Google WebRTC framework | `flutter_webrtc` | the same | `flutter_webrtc` | the browser |
| Game capture (share play host) | ScreenCaptureKit, without the title bar (built) | Windows.Graphics.Capture (planned) | PipeWire via xdg-desktop-portal (planned) | - (viewer only) | - (viewer only) |
| Game sound capture | ScreenCaptureKit audio (built) | WASAPI process loopback (planned) | PipeWire node of the game (planned) | - | - |
| Hardware H.264 | VideoToolbox through WebRTC (built) | Media Foundation, NVENC, AMF, Quick Sync | VA-API, NVENC | decoders: VideoToolbox, MediaCodec | the browser |
| Share play viewer's pad | the controller | (planned) | (planned) | the on-screen pad | a controller (Gamepad API) or the keyboard |
| Microphone processing | Apple voice processing | WebRTC APM | WebRTC APM | platform | the browser |
| Global push-to-talk | Carbon hot key (⌥V) | `GetAsyncKeyState` (a key of your choice, V by default) | `XQueryKeymap` on X11; on Wayland only while an X11 window or the launcher has the keyboard | button (planned) | key while focused |
| Permissions to ask | Microphone, Screen Recording | Microphone | Microphone; the portal's screen share prompt (share play, planned) | Microphone, notifications | Microphone, notifications |
| Notifications | in the app (the bell, a toast) | (planned) | (planned) | in the app (the bell); APNs / FCM (planned) | the bell; Web Push (built) |
| Engine | toolkits from AnyPS5-ARM's releases, picked in Settings → Engine (or one built in) | upstream AnyPS5's release, downloaded on first start | the same | - | - |
| Install and signing | Developer ID + notarization (keeps permissions across updates); a one-line install | an Inno Setup installer or a zip, not code-signed yet (SmartScreen may warn) | AppImage, `.deb`, tar.gz | sideload: APK, IPA through AltStore and the like | - |

**The engine**: every launcher starts games with an AnyPS5 engine, so features that live in the
engine work everywhere once the launcher passes the same settings and the engine has them. The
macOS launcher uses AnyPS5-ARM's engine (a toolkit per release, chosen in Settings → Engine);
AnyPS5 Desktop downloads upstream AnyPS5's release for its system. The phone's pads and share
play's pads use the engine's **remote pad bridges** (`ANYPS5_REMOTE_PAD`, `ANYPS5_REMOTE_PAD_2` …
`_4`: a loopback UDP address per pad), which also read the share play player number in byte 13
(below). These are in AnyPS5-ARM's engine today, POSIX only (a Winsock port is on the
`remotepad-winsock` branch); with upstream's libraries the variables are ignored. Online play needs
the engine's online bridge (`ANYPS5_ONLINE`, designed on AnyPS5-ARM's `online-play` branch) the
same way. The engine build is part of a game session's version guard and of each compatibility
report.

## 12.3 Feature parity

Every platform gets every feature; the table shows where each stands on 2026-10-25: **✓** built
and released (macOS launcher 0.2.15, phone 1.11.0, AnyPS5 Desktop 0.1.1 on Windows and Linux),
**○** planned, **-** not for this platform.

| Feature | macOS | Windows | Linux | Phone | Web |
|---|---|---|---|---|---|
| Sign-in | ✓ | ✓ | ✓ | ✓ | ✓ (with passkeys) |
| Profiles | ✓ | ✓ | ✓ | ✓ (edit yours) | ✓ |
| Trophies and library | ✓ | ✓ | ✓ | - | ✓ (on profiles) |
| Friends and presence | ✓ | ✓ | ✓ | ✓ | ✓ |
| Activity feed, leaderboards | ✓ | ○ | ○ | ✓ | ✓ |
| Notifications | ✓ (bell) | ○ | ○ | ✓ (bell; push ○) | ✓ (bell, browser push) |
| Messages | ✓ | ✓ | ✓ | ✓ | ✓ |
| Parties, voice, 1:1 calls | ✓ | ✓ | ✓ | ✓ (as the computer's headset ○) | ✓ |
| Join a friend's game | ✓ | ✓ | ✓ | - | - |
| Online play | ○ (in design) | ○ | ○ | - | - |
| Share play as host | ✓ | ○ | ○ | - | - |
| Share play as viewer, with a pad when handed one | ✓ | ○ | ○ | ✓ | ✓ |
| Finding players (board, Live now, people, game hubs) | ○ | ○ | ○ | ○ | ✓ |
| Themes and the Hub | ✓ | ○ (once the launcher reads `.anyps5theme`) | ○ | wears the launcher's theme | ✓ |
| Compatibility reports | ✓ | ○ | ○ | - | ✓ |
| Another server | ✓ | ✓ | ✓ | ✓ | (it is the server) |

The contracts (OpenAPI document, gateway and signalling messages, pad packet, phone protocol) are
versioned and published, so a launcher can connect without our help; a breaking change goes to a
new version while the old one keeps working.

## 12.4 The phone protocol

How a launcher and the AnyPS5 Remote phone app talk on the same network or on a cable. A launcher
that implements this works with the phone app as the macOS launcher does.

### Finding and pairing

- The launcher advertises Bonjour/mDNS service `_anyps5-remote._tcp` with its name, and listens
  for WebSockets on **TCP 47700** (another port if busy; the phone's manual address field assumes
  47700).
- Messages are JSON text frames, `{"type": "...", ...}`.

| Direction | type | Fields |
|---|---|---|
| phone → launcher | `hello` | `protocol` (1), `deviceID`, `deviceName`, `key` (null the first time) |
| launcher → phone | `pairing` | `code`: 4 digits, shown on both; the user allows it on the computer |
| launcher → phone | `welcome` | `session` (64-bit, as a decimal string), `udpPort`, `macName` (the computer's name), `key` (to send next time), `togetherServer` (optional: the AnyTogether server the launcher uses, so the phone can say when it is not its own) |
| launcher → phone | `rejected` | `reason`: `denied`, `busy`, `protocol` |
| phone → launcher | `latency` | `milliseconds` |
| launcher → phone | `library` | `games` [`id`, `name`, `state`, `trophies`, `art`, `layout`], `selected`, `running`, `language` |
| phone → launcher | `wantArt` | `id` → launcher answers `art` {`id`, `icon`, `background`: base64 JPEG} |
| phone → launcher | `select`, `launch`, `close`, `home`, `command` {`name`: left, right, up, down, select, back, options, l1, r1, capture} | the launcher mode |
| phone → launcher | `saveLayout` | `id`, `layout` (the phone's own JSON, kept per game) |
| launcher → phone | `trophy` | `name`, `detail`, `grade`, `icon` |
| launcher → phone | `activity` | what the launcher is doing with a game, or null |
| launcher → phone | `look` | `deep`, `middle`, `accent` (#RRGGBB): the launcher's theme |
| phone → launcher | `stream` | `on`, `width`, `height`: Remote Play wanted or not |
| phone → launcher | `keyFrame` | the phone lost part of the picture |
| launcher → phone | `streaming` | `state`: on, off, noPermission, noGame |
| either way | `togetherHandoff` | `id`, `deviceName`: sign me in to AnyTogether; `id` is the hand-off the asker started with the API ([API](04-api.md) 4.1) |
| either way | `togetherHandoffAnswer` | `id`, `approved`: approved on the server, or turned down |

Up to four phones at once, one per player; one new phone is asked about at a time.

### The pad (UDP)

The phone sends its pad to `udpPort` on the launcher; the launcher relays it to the game's bridge
of that phone's slot and relays the game's answers back. All little-endian.

**Input, 80 bytes** (phone → launcher → game):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `0x49525041` ("APRI") |
| 4 | 2 | version 1 |
| 6 | 2 | size 80 |
| 8 | 4 | sequence |
| 12 | 1 | flags: 1 = motion present |
| 13 | 1 | share play: the player the host handed this viewer (2-4), written by the host's launcher; 0 from a phone. The engine seats such a pad as that player, or the lowest free one after the first, never as player 1 |
| 14 | 2 | reserved, 0 |
| 16 | 8 | sent time, microseconds on the sender's clock |
| 24 | 8 | session (from `welcome`) |
| 32 | 4 | buttons (libScePad bits: L3 0x2, R3 0x4, Options 0x8, Up 0x10, Right 0x20, Down 0x40, Left 0x80, L2 0x100, R2 0x200, L1 0x400, R1 0x800, Triangle 0x1000, Circle 0x2000, Cross 0x4000, Square 0x8000, Touchpad 0x100000) |
| 36 | 4 | sticks: left x, left y, right x, right y (0-255, 128 centre, up is 0) |
| 40 | 1 | L2 (0-255) |
| 41 | 1 | R2 (0-255) |
| 44 | 6 × 2 | two touches: active, id, x (0-1919, u16), y (0-1079, u16) |
| 56 | 6 × 4 | motion: accelerometer x y z (m/s², float), gyroscope x y z (rad/s, float); without motion, accel y = 9.80665 |

**Output, 32 bytes** (game → launcher → phone):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `0x4F525041` ("APRO") |
| 4 | 2 | version 1 |
| 6 | 2 | size 32 |
| 8 | 4 | the input sequence it answers |
| 12 | 4 | how long the input waited in the engine, microseconds |
| 16 | 8 | the input's sent time, echoed (the phone measures latency from it) |
| 24 | 1 | large motor |
| 25 | 1 | small motor |
| 26 | 1 | light bar valid |
| 27 | 3 | light bar R, G, B |
| 30 | 1 | L2 trigger effect fallback strength |
| 31 | 1 | R2 trigger effect fallback strength |

**Game hello, 16 bytes** (game → launcher bridge): magic `0x48525041` ("APRH"), version 1, size
16, byte 8 = the player number the game gave this pad (0 = none yet).

A phone on a cable has no UDP path: it sends the same input packets as **binary WebSocket
frames** on the control connection, and gets outputs back the same way. A share play viewer sends
the same input packets on the WebRTC data channel `pad` and gets the outputs back on it.

### Remote Play (local network)

Launcher → phone, by UDP to where the pad comes from (or binary frames on a cable):

- **Video piece**, header 24 bytes: magic `0x56525041` ("APRV"), version 1, header size 24, frame
  number (u32), piece index (u16), piece count (u16), flags (u16, 1 = key frame), reserved (u16),
  milliseconds since the stream began (u32); then up to 1176 bytes of the frame. A frame is H.264
  in start-code (Annex B) form, a key frame with its SPS and PPS first.
- **Sound**, header 16 bytes: magic `0x41525041` ("APRA"), version 1, header size 16, number
  (u32), milliseconds (u32); then 16-bit stereo PCM at 48 kHz (5 ms per packet). Share play sends
  these same packets on the WebRTC data channel `audio`.

### Cable

- **iPhone**: the phone app listens on TCP **47702** on the phone. The launcher connects to it
  through Apple's USB multiplexer (usbmuxd on macOS; on Windows the one Apple's mobile device
  service runs; on Linux `usbmuxd`) and joins that connection to its own WebSocket port; the phone
  then speaks the protocol above over it, pad as binary frames.
- **Android**: with adb and USB debugging, the launcher runs `adb forward tcp:0 tcp:47702` and
  does the same.
