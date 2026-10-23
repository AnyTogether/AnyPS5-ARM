# AnyPS5 Remote

Use your phone as a DualSense for the PS5 games [AnyPS5-ARM](https://github.com/utkuhalis/AnyPS5-ARM) runs on a Mac. Android and iOS, from one Flutter code base.

| Launcher mode | The pad |
|---|---|
| ![The phone in launcher mode](../docs/screenshots/phone-launcher.jpg) | ![The phone pad](../docs/screenshots/phone-pad.jpg) |

## What it does

- **Connects by itself.** The phone finds AnyPS5.app on the same Wi-Fi. The first time, the Mac asks once whether to allow it and both show the same four-digit code; after that it connects with no question. When nothing is found, the Mac's address can be typed in.
- **Launcher mode.** The Mac's games, with their icons, over the selected one's background. Picking a game on the phone picks it on the Mac, and the other way round. **Play** does on the Mac what Play does there (unlock, update or start); **Back to Game** and **Close Game** work while one plays, and starting another game stops the one playing first. The arrows, ✕, ○ and ≡ at the bottom right move around the launcher's own screen: menus, settings, panels.
- **The pad.** Both sticks, ✕ ○ □ △, L1 R1, L2 R2, the D-pad, Options and the touchpad, any number of them held at once. A double tap on a stick holds L3 or R3. The latency from the touch to the game is shown on the phone and in the launcher. The pad takes over by itself when a game starts and gives the phone back to the launcher when it ends.
- **PS** takes the phone to the launcher and brings the launcher in front of the game on the Mac; the game gets nothing from the phone meanwhile.
- **Rumble, trigger effects and light.** The game's two motors are felt on the phone, the large one dull and the small one crisp (amplitude-controlled vibration on Android, Core Haptics on iPhone). While L2 or R2 is held, the phone pulses where the DualSense trigger would push back, and the pad glows with the game's light bar colour. About turns the vibration off.
- **Your own layout, per game.** The lock at the pad's bottom left opens the editor: drag a control to move it, tap it to size it, fade it, hide it, or make it a toggle (one tap presses it, the next lets go) or a turbo button. Reset and Reset All go back to the default. The layout is kept on the Mac with the game's settings and comes back whenever that game plays.
- **Language.** The phone uses the launcher's language: English by default, or Turkish.
- The version is shown faintly in the bottom right corner.

It needs AnyPS5.app with phone support, and games unlocked with it: a game unlocked before shows **Update available** and needs **Update and Play** once.

## Installing

- **Android:** open [AnyPS5-Remote.apk](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-Remote.apk) on the phone and allow installing from your browser when asked.
- **iPhone** (iOS 15 or newer): install [AnyPS5-Remote.ipa](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-Remote.ipa) with [AltStore](https://altstore.io) (or SideStore, or [Sideloadly](https://sideloadly.io) from a computer): it signs the app with your own Apple ID as it installs it. With a free Apple ID the app has to be refreshed every 7 days, which AltStore does by itself.

## Building

```sh
flutter build apk --release
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`. For the iPhone, `flutter build ios --release --no-codesign` makes an unsigned app; zipped as `Payload/Runner.app` it is the .ipa that AltStore or Sideloadly sign while installing.

## Testing

`flutter test` runs the protocol, session, pad and setup tests.

The whole flow, from the welcome screen to a game and back with PS, runs on a simulator or a device against the launcher's command-line phone server, which shows a games folder and only pretends to play:

```sh
anyps5-tool remote --allow-all --hidden --port 47790 --games <games folder>
ANYPS5_SHOTS=build/shots flutter drive -d <device> --driver test_driver/integration_test.dart \
    --target integration_test/flow_test.dart --dart-define=ANYPS5_LAUNCHER=127.0.0.1:47790
```

`--hidden` keeps that server off Bonjour and `ANYPS5_LAUNCHER` makes the app connect to it alone, so no other launcher on the network is reached. The screenshots land in `build/shots`.

To feel the rumble and the light bar without a game, with the app in front on a phone connected to AnyPS5.app, run `python3 tool/rumble_test.py`: it plays a pretend game on the launcher's bridge and sends the large motor, the small one, a ramp, pulses and a red light bar.

## Design

[Design](docs/superpowers/specs/2026-10-22-phone-controller-design.md) · [Phase 1 plan](docs/superpowers/plans/2026-10-22-phone-controller-phase1.md)
