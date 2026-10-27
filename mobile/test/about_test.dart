import 'package:anyps5_remote/ui/about_sheet.dart';
import 'package:anyps5_remote/ui/welcome_screen.dart';
import 'package:anyps5_remote/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the welcome screen names the author and opens About', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(onStart: () {})));
    await tester.tap(find.textContaining('Made by Utku Halis'));
    await tester.pumpAndSettle();
    expect(find.text('AnyPS5 Remote  ·  v$appVersion'), findsOneWidget);
    expect(find.text('Utku Halis'), findsOneWidget);
    expect(find.text('github.com/AnyTogether/AnyPS5-ARM'), findsOneWidget);
    expect(find.text('github.com/boykopovar/AnyPS5'), findsOneWidget);
  });

  /// An iPhone 14 Pro on its side, with every switch shown: the links stay on the screen.
  testWidgets('About with its switches fits a phone held sideways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAbout(
              context,
              vibration: true,
              onVibration: (_) {},
              motion: true,
              onMotion: (_) {},
              remotePlay: false,
              onRemotePlay: (_) {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final text in ['github.com/boykopovar/AnyPS5', 'Remote Play']) {
      final box = tester.getRect(find.text(text));
      expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
    }
  });

  testWidgets('Test plays the vibration, and only while it is on', (
    tester,
  ) async {
    var tested = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAbout(
              context,
              vibration: true,
              onVibration: (_) {},
              onTestVibration: () => tested++,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    expect(tested, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'), warnIfMissed: false);
    expect(tested, 1);
  });
}
