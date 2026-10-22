# Phone Controller, Phase 1 (end-to-end skeleton) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Android phone on the same Wi-Fi finds the Mac launcher by itself, pairs once, shows a fixed DualSense layout, and its presses reach a game started from the launcher, with the latency measured.

**Architecture:** The phone talks only to the launcher. It uses a WebSocket control channel (Bonjour `_anyps5-remote._tcp`, JSON messages, pairing) and a UDP input channel (80-byte pad packets at least 120 Hz and on every change). The launcher checks each packet's session and forwards it, byte for byte, to the running game over a loopback UDP bridge whose address it passes as `ANYPS5_REMOTE_PAD`. The engine merges the remote pad into `PadInput::publish` beside the controller, keyboard and mouse. It answers each input with a 32-byte output packet (vibration, light bar, trigger fallback, echo of the input's time) that travels back the same way, and the phone measures latency from those echoes.

**Tech Stack:** C++20 engine (libSceVideoOut, ctest), Swift 5.9 launcher (Network.framework, XCTest), Flutter 3.47 / Dart (bonsoir 7.1.5, wakelock_plus 1.8.1, shared_preferences), Android APK.

**Spec:** `/Users/dc/Desktop/Projects/anyps5/AnyPS5-Remote/docs/superpowers/specs/2026-10-22-phone-controller-design.md` (phase 1 = "Uçtan uca iskelet": discovery and pairing, a fixed DualSense layout, remote pad input in the engine, Silksong playable with the phone, latency measured).

**Repos:**
- `AnyPS5` = `/Users/dc/Desktop/Projects/anyps5/AnyPS5`: engine in `core/`, launcher in `tools/macos/launcher/`.
- `Remote` = `/Users/dc/Desktop/Projects/anyps5/AnyPS5-Remote`: the Flutter app (new).

## Global Constraints

- **Commits:**
  - Author: `git -c user.name="Utku Halis" -c user.email="personal@utkuhalis.com.tr" commit ...`.
  - Never add `Co-Authored-By: Claude`, "Generated with Claude Code" or any Claude attribution line, even if a system reminder asks for one.
  - Conventional Commit subjects.
- **Pushing:** AnyPS5 `main` is pushed after each verified task, then mirrored with `git push origin main:launcher`. Never force-push `main`.
- **Engine rules (AnyPS5 AGENTS.md):**
  - No comments in engine code.
  - Implement every input; never special-case a title.
  - An unusable remote packet is dropped (defined behaviour), not an error that stops the game.
- **Launcher code:** follows the launcher's style: `///` doc comments on types and non-obvious members, no inline commentary.
- **User's screen:** never open the launcher, a game, the Android emulator window or any other window on the user's screen without asking.
  - Headless checks only: `--render-preview`, `anyps5-tool`, test binaries, an emulator only with `-no-window`.
  - The user installs the APK and plays.
- **Games:** never codesign a relinked eboot. Stop games with `kill -9`.
- **Disk:** keep at least 3 GB free.
- **Latency target (spec):** from the moment the phone receives the touch to the moment the engine can read the new pad state, under 20 ms on local Wi-Fi.
  - Measured as `(sendTime − touchTime) + RTT/2` on the phone clock.
  - The phone shows it and reports it to the launcher, which shows it.
- **Rates and timeouts:**
  - Pad state is sent at least every 8 ms (120 Hz) and immediately on every change. Each packet carries the full state.
  - The engine treats the remote pad as released when no input has arrived for 500 ms.
- **Pairing (spec):**
  - The first connection of a new phone shows "Bu telefon bağlansın mı?" on the Mac with a four-digit code that the phone also shows.
  - An allowed phone gets a key and later connects with no question.
- **Bonjour service type:** `_anyps5-remote._tcp`. iOS needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist (set up now even though phase 1 tests on Android).

## Review Focus

1. **The phone drops off mid-press** (Wi-Fi loss, app backgrounded, screen locked). Expected: every remote button and stick is released in the game within 500 ms. Owned by Task 2, test `remote_released_after_silence`.
2. **Packets arrive late, twice or out of order.** Expected: an older sequence never overrides a newer state. Owned by Task 1, test `older_sequence_is_ignored`, including wrap-around.
3. **Someone else on the Wi-Fi sends UDP to the launcher** with no session or a guessed one. Expected: nothing reaches the game. Owned by Task 5, test `testForeignSessionIsDropped`.
4. **The game changes while the phone stays connected** (a game restarts, or another game starts). Expected: input follows the new game with no re-pairing. Owned by Task 5, test `testNewGameHelloRedirectsBridge`.
5. **The launcher restarts** while the phone app stays open. Expected: the phone reconnects by itself with its stored key and no pairing question. Owned by Task 4 (`testKnownKeyIsWelcomedWithoutPrompt`) and Task 8 (`reconnects after the server restarts`).

---

## Wire format (shared by Tasks 1, 3, 5, 7, 8)

All integers are little-endian. Floats are IEEE-754 `float32`, little-endian.

**Input packet**: 80 bytes, phone → launcher → engine.

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | magic `0x49525041` (bytes `A P R I`) |
| 4 | u16 | version `1` |
| 6 | u16 | size `80` |
| 8 | u32 | sequence (+1 per packet, wraps) |
| 12 | u32 | flags: bit 0 = motion valid |
| 16 | u64 | sentMicros (phone monotonic clock) |
| 24 | u64 | session (from `welcome`; the engine ignores it) |
| 32 | u32 | buttons: `Pad::PadButton` bits; others are masked off |
| 36 | u8[4] | sticks lx, ly, rx, ry (0..255, centre 128, up = 0) |
| 40 | u8 | L2 analog |
| 41 | u8 | R2 analog |
| 42 | u16 | reserved (0) |
| 44 | 2 × {u8 active, u8 id, u16 x, u16 y} | touch points (x < 1920, y < 1080) |
| 56 | f32[3] | accel (m/s²) |
| 68 | f32[3] | gyro (rad/s) |

**Output packet**: 32 bytes, engine → launcher → phone.

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | magic `0x4F525041` (`A P R O`) |
| 4 | u16 | version `1` |
| 6 | u16 | size `32` |
| 8 | u32 | last applied input sequence |
| 12 | u32 | reserved (0) |
| 16 | u64 | that input's sentMicros, echoed |
| 24 | u8 | vibration large (max of game and audio haptics) |
| 25 | u8 | vibration small |
| 26 | u8 | light bar valid (0/1) |
| 27 | u8[3] | light bar r, g, b |
| 30 | u8 | L2 trigger fallback |
| 31 | u8 | R2 trigger fallback |

**Hello packet**: 16 bytes, engine → launcher. Sent every 1 s until the first input arrives, and once at start.

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | magic `0x48525041` (`A P R H`) |
| 4 | u16 | version `1` |
| 6 | u16 | size `16` |
| 8 | u64 | reserved (0) |

**Control messages**: WebSocket text frames, one JSON object each, key `type`.

- phone → Mac: `{"type":"hello","protocol":1,"deviceID":"<uuid>","deviceName":"<model>","key":"<base64>"|null}`
- Mac → phone: `{"type":"pairing","code":"4821"}` while the Mac asks the user.
- Mac → phone: `{"type":"welcome","session":"<u64 decimal>","udpPort":<u16>,"macName":"<host>","key":"<base64 32 bytes>"}`
- Mac → phone: `{"type":"rejected","reason":"denied"|"protocol"}`, then the socket closes.
- phone → Mac: `{"type":"latency","milliseconds":<double>}` every 2 s.

---

### Task 1: Engine remote pad codec, merge and channel

**Files:**
- Create: `AnyPS5/core/libs/prx/libSceVideoOut/include/RemotePad.hpp`
- Create: `AnyPS5/core/libs/prx/libSceVideoOut/src/RemotePad.cpp`
- Create: `AnyPS5/core/libs/prx/libSceVideoOut/tests/RemotePad.cpp`
- Modify: `AnyPS5/core/libs/prx/libSceVideoOut/CMakeLists.txt`: add `src/RemotePad.cpp` to the library sources next to `src/InputMapping.cpp` (line 13), and `add_test_executable(remote_pad_tests tests/RemotePad.cpp src/RemotePad.cpp)` next to `pad_input_mapping_tests` (line 142).

**Interfaces:**
- Produces (namespace `RemotePad`):
  - constants `InputMagic = 0x49525041u`, `OutputMagic = 0x4F525041u`, `HelloMagic = 0x48525041u`, `Version = 1`, `InputSize = 80`, `OutputSize = 32`, `HelloSize = 16`, and `Silence = std::chrono::milliseconds(500)`.
  - `struct Input { std::uint32_t sequence; std::uint64_t sentMicros; PadInputState state; };`
  - `std::optional<Input> DecodeInput(std::span<const std::uint8_t> bytes);`
  - `std::array<std::uint8_t, OutputSize> EncodeOutput(const Input& last, const PadOutputState& output);`
  - `std::array<std::uint8_t, HelloSize> EncodeHello();`
  - `bool IsNewer(std::uint32_t sequence, std::uint32_t than);` for serial-number order, where a difference below 2^31 counts as newer.
  - `PadInputState Merge(const PadInputState& controller, const PadInputState& remote);`
  - `class Channel`:
    - `explicit Channel(std::uint16_t launcherPort);` binds `127.0.0.1:0`;
    - `std::optional<Input> Poll(std::chrono::steady_clock::time_point now);` drains every pending datagram and returns the newest valid input, or nullopt;
    - `void Answer(const Input& last, const PadOutputState& output);`
    - `void Greet(std::chrono::steady_clock::time_point now);` sends a hello at start and every 1 s until the first input;
    - `std::uint16_t Port() const;`
  - `std::unique_ptr<Channel> OpenFromEnvironment();`: nullptr when `ANYPS5_REMOTE_PAD` is unset or empty. It throws `std::runtime_error` naming the variable when the value is not `127.0.0.1:<1..65535>`.

- [ ] **Step 1: Write the failing tests** in `tests/RemotePad.cpp`, in the style of `tests/InputMapping.cpp` (a `main` running named checks, `Require(bool, message)`):
  - `decodes_a_full_packet`: an 80-byte packet with sequence 7, sentMicros 123456, buttons `0x4000 | 0x0010 | 0x40000000`, sticks `{255, 0, 128, 64}`, L2 200, R2 0, touch 0 active id 3 at (1919, 1079), flags 1, accel `{0, 9.8, 0}`, gyro `{0.5, 0, 0}`. Decoded: `buttons == 0x4010` (the unknown bit is masked), the same sticks and analog values, `touch[0] == {true, 1919, 1079, 3}`, `hasMotion == true`.
  - `rejects_bad_packets`: wrong magic, version 2, size field 79, a 79-byte span, touch x 1920, and a NaN in gyro each give `nullopt`.
  - `older_sequence_is_ignored`:
    - `IsNewer(8, 7)` and `IsNewer(0, 0xFFFFFFFF)` are true;
    - `IsNewer(7, 8)` and `IsNewer(7, 7)` are false;
    - in the loopback below, sending sequences 5 then 4 makes `Poll` return 5 and then nullopt.
  - `merge_takes_the_stronger_input`:
    - controller `{buttons 0x4000, lx 128, L2 10}` merged with remote `{buttons 0x2000, lx 250, L2 200}` gives buttons `0x6000`, lx 250 and L2 200;
    - with controller lx 0 and remote lx 140, lx is 0 (furthest from 128 wins);
    - remote motion replaces the controller's only when `remote.hasMotion`.
  - `encodes_output`: from last `{sequence 9, sentMicros 555}` and output `{vibrationLarge 10, audioVibrationLarge 40, vibrationSmall 3, lightBarValid true, lightBar {1,2,3}, trigger fallback {7, 8}}`, the 32 bytes hold magic, version 1, size 32, sequence 9, echo 555, large 40, small 3, valid 1, rgb 1 2 3 and fallbacks 7 and 8.
  - `loopback_channel`:
    - a test UDP socket bound to `127.0.0.1:0` plays the launcher;
    - `Channel(port)` plus `Greet(now)` delivers a 16-byte hello there;
    - an input sent from the test socket to `Channel::Port()` comes back from `Poll`;
    - `Answer` delivers a 32-byte output to the test socket;
    - a second `Greet` 200 ms later sends nothing, and one 1100 ms later sends again.
  - `environment`: `ANYPS5_REMOTE_PAD` unset gives nullptr; `"127.0.0.1:0"`, `"10.0.0.1:5000"` and `"127.0.0.1:x"` throw.
- [ ] **Step 2: Run them to see them fail**: `ninja -C AnyPS5/build-mac remote_pad_tests` fails because `RemotePad.hpp` is missing.
- [ ] **Step 3: Implement** `RemotePad.hpp` and `RemotePad.cpp` with the interfaces above.
  - Use POSIX `socket(AF_INET, SOCK_DGRAM)`, `O_NONBLOCK`, `recvfrom` in a loop until `EWOULDBLOCK`, and send to `127.0.0.1:launcherPort`.
  - Decode with `std::memcpy` into fixed-width fields.
- [ ] **Step 4: Run the tests to see them pass**: `ninja -C AnyPS5/build-mac remote_pad_tests && ctest --test-dir AnyPS5/build-mac -R remote_pad -V` gives `100% tests passed`.
- [ ] **Step 5: Commit** in AnyPS5: `feat(videoout): remote pad packets, merge and loopback channel`.

### Task 2: Engine uses the remote pad

**Files:**
- Modify: `AnyPS5/core/libs/prx/libSceVideoOut/include/PadInput.hpp`: new members `std::unique_ptr<RemotePad::Channel> remote;`, `PadInputState remoteState{};`, `std::optional<RemotePad::Input> remoteLast;`, `std::chrono::steady_clock::time_point remoteSeen{};`.
- Modify: `AnyPS5/core/libs/prx/libSceVideoOut/src/PadInput.cpp`: the constructor, `Update` (line 309), `publish` (line 328) and `applyOutput` (line 145).
- Modify: `AnyPS5/core/libs/prx/libSceVideoOut/tests/RemotePad.cpp`: add the silence test.
- Modify: `AnyPS5/docs/user/USAGE.md`: a short `ANYPS5_REMOTE_PAD` paragraph beside the input variables.

**Interfaces:**
- Consumes (Task 1): `OpenFromEnvironment`, `Channel::Poll/Answer/Greet`, `Merge`, `Silence`.
- Produces: `PadInputState RemotePad::Current(const std::optional<Input>& last, std::chrono::steady_clock::time_point seen, std::chrono::steady_clock::time_point now);` returns `last->state` within `Silence` of `seen`, else a default (released) `PadInputState`.

- [ ] **Step 1: Write the failing test** `remote_released_after_silence`:
  - `Current(input with buttons 0x4000, seen = t, now = t + 499ms).buttons == 0x4000`;
  - at `t + 500ms` the result equals `PadInputState{}` (buttons 0, sticks 128);
  - with no input at all the result is also `PadInputState{}`.
- [ ] **Step 2: Run it to see it fail** (`Current` is undefined).
- [ ] **Step 3: Implement `Current` and wire `PadInput`:**
  - The constructor sets `remote = RemotePad::OpenFromEnvironment()`.
  - `Update`:
    - If `remote`, call `Greet(now)`.
    - If `Poll(now)` returns an input, store it in `remoteLast`, set `remoteSeen = now`, call `Answer(*remoteLast, outputState)` and publish.
    - If the merged remote state changed because of silence, publish once.
    - Remote input never depends on SDL keyboard focus, so a phone keeps working while the game window is not focused.
  - `publish` composes `keyboardMouse.Compose(RemotePad::Merge(controllerState, RemotePad::Current(remoteLast, remoteSeen, now)))`.
  - `applyOutput` calls `remote->Answer(*remoteLast, outputState)` when output changed and a remote input exists, before the `controller == nullptr` return, so a phone gets vibration with no controller attached.
- [ ] **Step 4: Run the tests**: `ctest --test-dir AnyPS5/build-mac -R "remote_pad|pad_input|pad_keyboard" -V` passes.
  - Also run the full suite: `ctest --test-dir AnyPS5/build-mac -j8 --timeout 300`.
  - The failure list equals the known pre-existing list in memory `macos-title-testing.md` and nothing else.
- [ ] **Step 5: Commit**: `feat(videoout): games read a remote pad from ANYPS5_REMOTE_PAD`.

### Task 3: Launcher protocol types and paired devices

**Files:**
- Modify: `AnyPS5/tools/macos/launcher/Package.swift`: add `.testTarget(name: "AnyPS5CoreTests", dependencies: ["AnyPS5Core"], path: "Tests/AnyPS5CoreTests")`.
- Create: `AnyPS5/tools/macos/launcher/Sources/AnyPS5Core/Remote/RemoteProtocol.swift`
- Create: `AnyPS5/tools/macos/launcher/Sources/AnyPS5Core/Remote/PairedDevices.swift`
- Test: `AnyPS5/tools/macos/launcher/Tests/AnyPS5CoreTests/RemoteProtocolTests.swift`

**Interfaces:**
- Produces:
  - `public enum RemoteMessage: Codable, Equatable, Sendable` with these cases, encoded with a `type` key as in the wire format:
    - `hello(protocol: Int, deviceID: String, deviceName: String, key: String?)`
    - `pairing(code: String)`
    - `welcome(session: UInt64, udpPort: UInt16, macName: String, key: String)` (session as a decimal string in JSON)
    - `rejected(reason: String)`
    - `latency(milliseconds: Double)`
  - `public enum RemotePacket`:
    - constants mirroring Task 1;
    - `static func inputSession(_ data: Data) -> UInt64?` returns nil unless the magic, version 1, size 80 and length are right;
    - `static func isOutput(_ data: Data) -> Bool`;
    - `static func isHello(_ data: Data) -> Bool`.
  - `public struct PairedDevice: Codable, Equatable, Sendable { public let id: String; public var name: String; public let key: String; public let added: Date }`
  - `public final class PairedDevices: @unchecked Sendable`:
    - `init(file: URL)`; the default file is `~/Library/Application Support/AnyPS5/RemoteDevices.json`;
    - `func device(id: String, key: String) -> PairedDevice?`;
    - `func add(id: String, name: String) -> PairedDevice` makes a 32-byte random key in base64 and saves;
    - `func remove(id: String)`;
    - `var all: [PairedDevice]`.
  - It is guarded by an `NSLock` and the file is written atomically.

- [ ] **Step 1: Write the failing tests:**
  - `testHelloRoundTrip`: `{"type":"hello","protocol":1,"deviceID":"A","deviceName":"Pixel","key":null}` decodes to `.hello(protocol: 1, deviceID: "A", deviceName: "Pixel", key: nil)` and re-encodes to an equal value.
  - `testWelcomeSessionIsDecimalString`: the encoded `welcome(session: 18446744073709551615, …)` JSON contains `"session":"18446744073709551615"`.
  - `testUnknownTypeFailsToDecode`.
  - `testInputSession`: a valid 80-byte packet with session 42 gives 42; one with size field 79 gives nil.
  - `testPairedDevicesPersist`:
    - `add` then a new `PairedDevices(file:)` on the same file finds it by `id` and `key`;
    - a wrong key gives nil;
    - `remove` makes it gone after reload.
- [ ] **Step 2: Run** `swift test --package-path AnyPS5/tools/macos/launcher --filter RemoteProtocolTests`: it fails to compile.
- [ ] **Step 3: Implement both files.**
- [ ] **Step 4: Run the same command**: all pass.
- [ ] **Step 5: Commit**: `feat(launcher): remote control messages and paired phones`.

### Task 4: Launcher control channel and pairing

**Files:**
- Create: `AnyPS5/tools/macos/launcher/Sources/AnyPS5Core/Remote/RemoteServer.swift`
- Test: `AnyPS5/tools/macos/launcher/Tests/AnyPS5CoreTests/RemoteServerTests.swift`

**Interfaces:**
- Consumes (Task 3): `RemoteMessage`, `PairedDevices`.
- Produces:
  - `public struct PairingRequest: Identifiable, Sendable { public let id: UUID; public let deviceName: String; public let code: String }`
  - `public final class RemoteServer: @unchecked Sendable`:
    - `public struct Events { public var pairing: @Sendable (PairingRequest) -> Void; public var connected: @Sendable (String) -> Void; public var disconnected: @Sendable () -> Void; public var latency: @Sendable (Double) -> Void }`
    - `public init(name: String, devices: PairedDevices, events: Events, advertise: Bool = true, controlPort: UInt16 = 0)`
    - `public func start() throws`: an `NWListener` with `NWProtocolWebSocket` on `controlPort` (0 = any); with `advertise`, a Bonjour service `_anyps5-remote._tcp`.
    - `public func stop()`
    - `public func respond(to id: UUID, allow: Bool)`
    - `public var controlPort: UInt16? { get }`
    - `public var connectedDevice: String? { get }`
  - Behaviour:
    - One phone at a time. A second hello while one is connected gets `rejected("busy")`.
    - The code is 4 random digits, `0000`–`9999`, zero-padded.
    - A known `deviceID` and `key` gets `welcome` with no `pairing` event.
    - An unknown one gets `pairing(code)` sent to the phone and an `Events.pairing` call. On `respond(allow: true)` it is added to the devices and welcomed with the new key; on false it gets `rejected("denied")` and the socket closes.
    - Protocol ≠ 1 gets `rejected("protocol")`.
    - A new `session` (random `UInt64`) per welcome.
    - The `udpPort` in welcome is the UDP listener from Task 5. Until Task 5 lands, send 0.

- [ ] **Step 1: Write the failing tests.** Each starts a server with `advertise: false` on port 0 and connects a `URLSessionWebSocketTask` to `ws://127.0.0.1:<controlPort>`.
  - `testUnknownPhoneIsAskedThenWelcomed`:
    - after hello with `key: nil`, the phone receives `pairing(code)` with a 4-digit code, and the `pairing` event fires with the same code and the phone's name;
    - after `respond(allow: true)`, the phone receives `welcome` whose `key` decodes to 32 bytes;
    - `devices.all.count == 1` and the `connected` event fires.
  - `testDeniedPhoneIsRejected`: `respond(allow: false)` gives `rejected("denied")`, then the socket closes.
  - `testKnownKeyIsWelcomedWithoutPrompt`: with a pre-added device and its key, the phone gets `welcome` directly and the pairing event never fires (wait 0.5 s).
  - `testSecondPhoneIsBusy`.
  - `testWrongProtocolIsRejected`.
  - `testLatencyIsReported`: a `latency(milliseconds: 9.5)` message from a welcomed phone fires the `latency` event with 9.5.
- [ ] **Step 2: Run** `swift test --package-path AnyPS5/tools/macos/launcher --filter RemoteServerTests`: it fails.
- [ ] **Step 3: Implement** `RemoteServer` (control part) on Network.framework, with all state on one private serial `DispatchQueue`.
- [ ] **Step 4: Run the tests**: they pass.
- [ ] **Step 5: Commit**: `feat(launcher): phones find and pair with the launcher`.

### Task 5: Launcher UDP relay between phone and game

**Files:**
- Modify: `AnyPS5/tools/macos/launcher/Sources/AnyPS5Core/Remote/RemoteServer.swift`
- Test: `AnyPS5/tools/macos/launcher/Tests/AnyPS5CoreTests/RemoteRelayTests.swift`

**Interfaces:**
- Consumes: Task 4's server; Task 3's `RemotePacket`.
- Produces on `RemoteServer`:
  - `public var udpPort: UInt16? { get }`: phone side, an `NWListener` UDP on any port, sent in welcome;
  - `public var bridgePort: UInt16? { get }`: game side, UDP bound to `127.0.0.1` only;
  - `public var bridgeEnvironment: [String: String] { get }`: `["ANYPS5_REMOTE_PAD": "127.0.0.1:<bridgePort>"]`, or empty before start.
- Behaviour:
  - A phone datagram is forwarded unchanged to the last game address that sent a hello. The address comes from the hello's source and is replaced by every new hello.
  - It is forwarded only when `RemotePacket.inputSession == current session` of the welcomed phone. The phone's UDP source address is learned from its first valid packet.
  - Output datagrams from the game's address are forwarded to the phone's address.
  - Everything else is dropped.
  - After the phone disconnects, the session is cleared, so its UDP stops passing.

- [ ] **Step 1: Write the failing tests** (a welcomed fake phone from the Task 4 helper, a fake game as a UDP socket on `127.0.0.1:0` that sends a hello to `bridgePort`, and a fake phone UDP socket):
  - `testInputReachesGame`: 80 bytes with the right session arrive byte-identical at the fake game.
  - `testForeignSessionIsDropped`: session+1, a wrong magic and a 79-byte datagram never arrive (wait 0.3 s).
  - `testOutputReachesPhone`: a 32-byte output from the game arrives at the phone's UDP socket.
  - `testNewGameHelloRedirectsBridge`: a second fake game sends a hello; the next input reaches only the second game.
  - `testSessionEndsWithControlSocket`: after the WebSocket closes, input with the old session is dropped.
  - `testBridgeEnvironment`: `bridgeEnvironment["ANYPS5_REMOTE_PAD"] == "127.0.0.1:\(bridgePort!)"`.
- [ ] **Step 2: Run** `swift test --package-path AnyPS5/tools/macos/launcher --filter RemoteRelayTests`: it fails.
- [ ] **Step 3: Implement the relay**; welcome now carries the real `udpPort`.
- [ ] **Step 4: Run** all launcher tests (`swift test --package-path AnyPS5/tools/macos/launcher`): everything passes.
- [ ] **Step 5: Commit**: `feat(launcher): relay pad packets between the phone and the game`.

### Task 6: `anyps5-tool remote` for headless end-to-end checks

**Files:**
- Modify: `AnyPS5/tools/macos/launcher/Sources/anyps5-tool/main.swift`

**Interfaces:**
- Consumes: `RemoteServer`, `PairedDevices`.
- Produces the command `anyps5-tool remote [--allow-all] [--devices <file>] [--port <control port>]`:
  - runs a server, advertising, until killed;
  - prints `control <port> udp <port> bridge 127.0.0.1:<port>` once started;
  - prints `pairing <name> <code>` and then reads `y`/`n` from stdin, unless `--allow-all`, which allows at once;
  - prints `connected <name>`, `latency <ms>` and `disconnected`.

- [ ] **Step 1: Implement** the command with the existing argument style of `main.swift`.
- [ ] **Step 2: Verify:**
  - Run `anyps5-tool remote --allow-all --devices <scratch>/devices.json &`; the `control … udp … bridge …` line appears within 2 s.
  - `dns-sd -B _anyps5-remote._tcp local.` lists the service within 5 s.
  - Kill both.
- [ ] **Step 3: Commit**: `feat(launcher): anyps5-tool remote runs the phone server headless`.

### Task 7: Launcher app: pairing prompt, phone indicator, bridge on Play

**Files:**
- Modify: `AnyPS5/tools/macos/launcher/Sources/AnyPS5/AppModel.swift`:
  - `@Published var pairing: PairingRequest?`, `@Published private(set) var phone: (name: String, latency: Double?)?`, `private var remote: RemoteServer?`;
  - start it in `init` when `persists` (not for previews);
  - `play()` adds `remote.bridgeEnvironment` to `configuration.environment`;
  - `func answerPairing(_ allow: Bool)`.
- Modify: `AnyPS5/tools/macos/launcher/Sources/AnyPS5/AnyPS5App.swift`: show the pairing card as an overlay above everything when `model.pairing != nil`.
- Create: `AnyPS5/tools/macos/launcher/Sources/AnyPS5/PhoneViews.swift`:
  - `PairingCard`: phone name, the code in large digits, the question, **İzin Ver** / **Reddet** as `ConsoleButton`s; Return allows, Esc denies.
  - `PhoneIndicator`: a green dot, the phone glyph and `"\(Int(ms)) ms"` when the latency is known.
- Modify: `HomeView.swift`: put `PhoneIndicator` in `TopBar` before the profile when `model.phone != nil`. In `handle(_:)`, route `.select` / `.back` to `answerPairing` while `pairing != nil`.
- Modify: `Panels.swift`: Settings → Advanced gets a "Telefonlar" info row and one row per paired phone, with a destructive action that removes it.
- Modify: `Localization.swift`: `phonePairingTitle` ("Bu telefon bağlansın mı?" / "Connect this phone?"), `phonePairingText` ("Telefonda da aynı kod görünüyor." / "The phone shows the same code."), `phoneAllow` ("İzin Ver" / "Allow"), `phoneDeny` ("Reddet" / "Deny"), `phoneConnected` ("%@ bağlandı" / "%@ connected"), `phones` ("Telefonlar" / "Phones"), `phoneRemove` ("Kaldır" / "Remove").
- Modify: `PreviewRenderer.swift`: `pairing.png` (a request with name "Pixel 8", code "4821") and `home-phone.png` (phone "Pixel 8", 9 ms).

**Interfaces:**
- Consumes: `RemoteServer` (Tasks 4 and 5), `PairedDevices.all/remove`.

- [ ] **Step 1: Implement.** Events arrive on the server queue, so hop to the main actor with `Task { @MainActor in … }`.
  - A pairing request while the launcher is not frontmost also shows a `TrophyBanner`-style non-activating card: "Telefon bağlanmak istiyor: launcher'ı aç". It must not take the game's focus (spec).
- [ ] **Step 2: Build and render the previews headless:**
  - `swift build -c release --package-path AnyPS5/tools/macos/launcher`.
  - `ANYPS5_PREVIEW_LANGUAGE=en ANYPS5_PREVIEW_SELECT=PPSA12544 .build/release/AnyPS5 --render-preview <scratch>/shots <scratch>/lib`.
  - Look at `pairing.png` and `home-phone.png`: the code is readable, the buttons and the indicator are there, and the look matches the launcher.
- [ ] **Step 3: Commit**: `feat(launcher): pair phones and show the connected one`.

### Task 8: Flutter app: protocol, connection and session

**Files (Remote repo):**
- Create the project: `flutter create --org org.anyps5 --project-name anyps5_remote --platforms android,ios .` in `Remote`.
  - Dependencies: `bonsoir: ^7.1.5`, `wakelock_plus: ^1.8.1`, `shared_preferences` (latest).
  - Android `AndroidManifest.xml`: `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_WIFI_STATE`, `VIBRATE`, and `android:screenOrientation="sensorLandscape"` on the activity.
  - iOS `Info.plist`: `NSLocalNetworkUsageDescription` ("Mac'teki AnyPS5'i bulmak için"), and `NSBonjourServices` with `_anyps5-remote._tcp`.
- Create: `lib/protocol/packets.dart`:
  - `class PadState { int buttons; List<int> sticks; int l2, r2; List<TouchPoint> touch; }` with a `copy()`;
  - `Uint8List encodeInput({required int sequence, required int sentMicros, required BigInt session, required PadState state})`;
  - `class Output { int sequence; int sentMicros; int large, small; bool lightValid; int r, g, b; int l2Fallback, r2Fallback; }`;
  - `Output? decodeOutput(Uint8List bytes)`.
  - `PadButton` constants with the engine values: L3 0x0002, R3 0x0004, Options 0x0008, Up 0x0010, Right 0x0020, Down 0x0040, Left 0x0080, L2 0x0100, R2 0x0200, L1 0x0400, R1 0x0800, Triangle 0x1000, Circle 0x2000, Cross 0x4000, Square 0x8000, TouchPad 0x100000.
- Create: `lib/protocol/messages.dart`: a sealed `Message` with `Hello`, `Pairing`, `Welcome`, `Rejected`, `Latency`, plus `toJson` and `Message? fromJson(String)`.
- Create: `lib/connection/session.dart`:
  - `class Session extends ChangeNotifier`, with a `ConnectionStatus { searching, connecting, pairing, connected, rejected }`, `String? code`, `String? macName`, `double? latencyMs`;
  - `Future<void> connect(InternetAddress host, int port)`;
  - `void update(PadState state, Duration touchTime)`: sends at once;
  - a 8 ms periodic sender;
  - it computes latency from outputs as `(sendMicros − touchMicros) + rtt/2`, with an exponential average (α = 0.2);
  - it reports `Latency` every 2 s;
  - it reconnects with a 1 s backoff when the socket drops;
  - it stores `deviceID` (a uuid made once) and `key` in shared_preferences.
- Create: `lib/connection/discovery.dart`: `Stream<(InternetAddress, int)> discover()` with bonsoir on `_anyps5-remote._tcp`.
- Test: `test/packets_test.dart`, `test/session_test.dart`.

**Interfaces:**
- Consumes: the wire format.
- Produces for Tasks 9 and 10: `PadState`, `PadButton`, `Session` (`status`, `code`, `macName`, `latencyMs`, `connect`, `update`, `dispose`), `discover()`.

- [ ] **Step 1: Write the failing tests:**
  - `packets_test.dart`:
    - `encodeInput` with the values of Task 1's `decodes_a_full_packet` (no unknown bit, no motion) gives exactly 80 bytes: bytes 0..3 = `41 50 52 49`, bytes 4..5 = `01 00`, 6..7 = `50 00`, 32..35 = buttons `10 40 00 00`, 36..39 = `FF 00 80 40`;
    - `decodeOutput` of the Task 1 `encodes_output` bytes gives `large 40, small 3, lightValid true, r 1, g 2, b 3, l2Fallback 7, r2Fallback 8, sequence 9, sentMicros 555`;
    - 31 bytes give null.
  - `session_test.dart`: a fake server in the test (`HttpServer.bind('127.0.0.1', 0)` with `WebSocketTransformer`, and a `RawDatagramSocket`):
    - `pairs on first connection`: the server answers hello with `pairing("4821")`, and `status == pairing`, `code == "4821"`; then with `welcome`, and `status == connected` and the key is stored.
    - `sends state at least every 8 ms`: the fake UDP socket receives ≥ 10 packets within 100 ms after `connect`, with increasing sequences.
    - `sends at once on update`: a packet arrives within 5 ms of `update` with the new buttons.
    - `measures latency from echoes`: the fake echoes each input as an output after 4 ms, and `latencyMs` lands between 1 and 15.
    - `reconnects after the server restarts`: close and rebind the same port; status goes back to `connected` within 3 s with no `pairing`, and the hello carries the stored key.
- [ ] **Step 2: Run** `flutter test`: it fails.
- [ ] **Step 3: Implement** `packets.dart`, `messages.dart`, `session.dart`, `discovery.dart`.
- [ ] **Step 4: Run** `flutter test`: all pass. `flutter analyze` shows no issues.
- [ ] **Step 5: Commit** in Remote: `feat: protocol, discovery and session`.

### Task 9: Flutter app: connect screen and the fixed DualSense layout

**Files (Remote repo):**
- Create: `lib/ui/connect_screen.dart`:
  - status colours: green connected, amber searching/connecting/pairing, red rejected or none;
  - when pairing, the code in large digits with "Mac'te izin ver";
  - a manual address field, shown after 5 s without discovery.
- Create: `lib/ui/pad_screen.dart`: the landscape DualSense layout. Positions are fractions of the screen size:
  - left stick centre (0.18, 0.62), radius 0.13 h;
  - right stick centre (0.68, 0.72), radius 0.13 h;
  - face buttons centre (0.86, 0.42), △ up, ○ right, ✕ down, □ left;
  - D-pad centre (0.14, 0.30);
  - L1 (0.08, 0.06), L2 (0.20, 0.06), R2 (0.80, 0.06), R1 (0.92, 0.06);
  - Options (0.62, 0.12), touchpad strip (0.50, 0.10), width 0.30, height 0.14;
  - L3 = double tap on the left stick, R3 = double tap on the right stick;
  - status dot and latency at the top centre.
- Create: `lib/ui/widgets/stick.dart` and `lib/ui/widgets/pad_button.dart`.
- Create: `lib/main.dart`: routes from connect to pad on `connected`, wakelock on in the pad screen.
- Test: `test/pad_screen_test.dart`.

**Interfaces:**
- Consumes: `Session`, `PadState`, `PadButton` (Task 8).
- Produces: `PadScreen({required void Function(PadState, Duration) onState})`, so tests capture the state without a session.

- [ ] **Step 1: Write the failing widget tests** (on an 800×400 surface):
  - `cross sets 0x4000 while held`: press at ✕'s centre and the last state has `buttons & 0x4000`; release and it clears.
  - `two buttons at once`: hold ✕ and R1 with two pointers, and `buttons == 0x4000 | 0x0800`.
  - `left stick full right`: drag from the left stick centre by `radius` to the right, and `sticks[0] == 255`, `sticks[1] == 128`; after release both are 128.
  - `stick up is 0`.
  - `L2 is analog full`: L2 pressed gives `l2 == 255` and `buttons & 0x0100`.
  - `touchpad reports a touch point`: a tap at the strip centre gives `touch[0].active` with `x == 960` (± 10) and `y == 540` (± 10), and `buttons & 0x100000` while pressed.
- [ ] **Step 2: Run** `flutter test test/pad_screen_test.dart`: it fails.
- [ ] **Step 3: Implement** the screens and widgets.
  - Multi-touch uses one `Listener` per control with pointer ids.
  - Every pointer down, move or up calls `onState(state.copy(), event.timeStamp)`.
  - Follow the launcher's look: dark glass controls, white focus, a soft accent. Design references are in the global CLAUDE.md.
- [ ] **Step 4: Run** `flutter test`: everything passes. `flutter analyze` is clean.
- [ ] **Step 5: Commit**: `feat: connect screen and DualSense layout`.

### Task 10: End-to-end check, APK and hand-off

**Files (Remote repo):**
- Create: `tool/fake_phone.dart`:
  - `dart run tool/fake_phone.dart --host 127.0.0.1 --port <control>` connects with `Session`;
  - after welcome it presses ✕ for 200 ms every second for 5 s;
  - it prints `latency <ms>` on each echo.
- Create: `README.md`: what the app is, building the APK, and that it needs the AnyPS5 launcher 0.2.3+.

**Interfaces:**
- Consumes: `Session` (Task 8), `anyps5-tool remote` (Task 6), `remote_pad_tests`' engine `Channel` (Task 1).

- [ ] **Step 1: Run the headless end-to-end check:**
  - Start `anyps5-tool remote --allow-all --devices <scratch>/devices.json`.
  - Start a scratch probe binary built like the earlier input-file checker, linking `RemotePad.cpp` with `ANYPS5_REMOTE_PAD` set to the printed bridge. It greets, prints each decoded state's buttons and answers.
  - Run `fake_phone.dart` against the printed control port.
  - Expected:
    - the probe prints `buttons 0x4000` and `buttons 0x0` alternating;
    - `fake_phone` prints latencies under 5 ms on loopback;
    - `anyps5-tool` prints `connected` and `latency`.
- [ ] **Step 2: Build the APK:**
  - Run `flutter build apk --release`. If the build stops on licences, first run `yes | flutter doctor --android-licenses`.
  - Expected: `build/app/outputs/flutter-apk/app-release.apk` exists.
- [ ] **Step 3: Release the launcher** that carries the remote server and the engine change as v0.2.3-arm, with the release flow in memory `launcher.md`: tag → `build_launcher_app.sh` → `ditto` → `gh release create --latest` with the zip and `install.sh`.
  - Ask the user before installing it into `/Applications` or opening it.
- [ ] **Step 4: Hand off to the user:**
  - Give the APK path. The user installs it and runs launcher 0.2.3. Silksong must first get **Unlock Again**, because the engine changed.
  - The user plays Silksong with the phone and reports the latency the phone and the launcher show.
  - Phase 1 is accepted when the user plays with the phone and the latency is under 20 ms.
  - If it is not, fix the connection before any phase 2 work (spec).
- [ ] **Step 5: Commit** in Remote and push the AnyPS5 changes (`main` and `main:launcher`).
