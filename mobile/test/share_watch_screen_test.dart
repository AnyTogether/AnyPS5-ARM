import 'dart:convert';

import 'package:anyps5_remote/feedback/haptics.dart';
import 'package:anyps5_remote/together/share_play.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_socket.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:anyps5_remote/ui/share_watch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'share_play_test.dart' show FakeShareEngine, FakeSound, view;

class QuietHaptics implements HapticsOutput {
  @override
  void set(Rumble rumble) {}
}

Future<SharePlays> plays({int? slot}) async {
  SharedPreferences.setMockInitialValues({
    'together.session': jsonEncode({
      'accessToken': 'access-1',
      'accessExpiry': DateTime.now()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'refreshToken': 'refresh-1',
      'user': {'id': 'me', 'handle': 'utku', 'displayName': 'Utku'},
    }),
  });
  final account = TogetherAccount(
    preferences: await SharedPreferences.getInstance(),
    base: Uri.parse('http://127.0.0.1:9'),
    clientName: 'test',
  );
  final plays = SharePlays(
    account: account,
    socket: TogetherSocket(account: account),
    engine: FakeShareEngine.new,
    sound: FakeSound.new,
  );
  plays.watching = SharePlayView.fromJson(view(slot: slot));
  plays.status = WatchStatus.watching;
  return plays;
}

void main() {
  Future<void> show(WidgetTester tester, SharePlays plays) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ShareWatchScreen(plays: plays, haptics: QuietHaptics()),
      ),
    );
    await tester.pump();
  }

  testWidgets('only watching: the picture and a chip, no pad', (tester) async {
    // The account reads its preferences before the first frame.
    final watching = await tester.runAsync(() => plays());
    await show(tester, watching!);
    expect(find.byType(PadScreen), findsNothing);
    expect(find.textContaining('Watching'), findsOneWidget);
    expect(find.textContaining('Ece'), findsOneWidget);
  });

  testWidgets('given a pad: the pad over the picture, as that player', (
    tester,
  ) async {
    final playing = await tester.runAsync(() => plays(slot: 3));
    await show(tester, playing!);
    expect(find.byType(PadScreen), findsOneWidget);
    expect(find.textContaining('Player 3'), findsOneWidget);
  });

  testWidgets('ended: why, and the way back', (tester) async {
    final ended = await tester.runAsync(() => plays());
    ended!
      ..status = WatchStatus.ended
      ..ended = WatchEnd.removed;
    await show(tester, ended);
    expect(find.text('Ece took you out'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });
}
