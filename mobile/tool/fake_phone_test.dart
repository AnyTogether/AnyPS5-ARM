// A phone without a phone, for checking the launcher and a game end to end:
//
//     ANYPS5_E2E_PORT=<launcher control port> flutter test tool/fake_phone_test.dart
//
// It pairs (the launcher must allow it), presses ✕ for 200 ms every second for five seconds
// and prints the latency it measures. Without ANYPS5_E2E_PORT it does nothing.
//
// It runs under flutter test, whose mock preferences it uses on purpose.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final port = int.tryParse(Platform.environment['ANYPS5_E2E_PORT'] ?? '');
  test('fake phone', () async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(preferences: await SharedPreferences.getInstance(), deviceName: 'Fake phone');
    await session.connect(InternetAddress.loopbackIPv4, port!);
    while (session.status != ConnectionStatus.connected) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    stdout.writeln('connected to ${session.macName}');
    for (var press = 0; press < 5; press++) {
      session.update(PadState()..buttons = PadButton.cross);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      session.update(PadState());
      await Future<void>.delayed(const Duration(milliseconds: 800));
      stdout.writeln('latency ${session.latencyMs?.toStringAsFixed(2)} ms');
    }
    expect(session.latencyMs, isNotNull);
    await session.close();
  }, skip: port == null ? 'set ANYPS5_E2E_PORT' : false, timeout: const Timeout(Duration(seconds: 30)));
}
