# AnyPS5 Remote

Use your phone as a DualSense for PS5 games that [AnyPS5-ARM](https://github.com/utkuhalis/AnyPS5-ARM) runs on a Mac.

The phone finds AnyPS5.app on the same Wi-Fi by itself. The first time, the Mac asks once whether to allow it and both show the same four-digit code; after that it connects with no question. The pad has both sticks, ✕ ○ □ △, L1 R1, L2 R2, the D-pad, Options and the touchpad, and any of them can be held at once. A double tap on a stick holds L3 or R3. The latency from your touch to the game is shown on the phone and in the launcher.

It needs the AnyPS5 launcher with phone support (branch `mobile-controller` for now), and the game unlocked again with it.

## Building

```sh
flutter build apk --release
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`. iOS builds from the same code; installing on an iPhone needs an Apple developer account.

## Testing

`flutter test` runs the protocol, session and pad tests. To check a launcher and a game without a phone, start `anyps5-tool remote --allow-all` from the launcher and run `ANYPS5_E2E_PORT=<control port> flutter test tool/fake_phone_test.dart`.

## Design

[Design](docs/superpowers/specs/2026-10-22-phone-controller-design.md) · [Phase 1 plan](docs/superpowers/plans/2026-10-22-phone-controller-phase1.md)
