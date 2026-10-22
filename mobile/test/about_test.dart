import 'package:anyps5_remote/ui/welcome_screen.dart';
import 'package:anyps5_remote/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the welcome screen names the author and opens About', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WelcomeScreen(onStart: () {})));
    await tester.tap(find.textContaining('Made by Utku Halis'));
    await tester.pumpAndSettle();
    expect(find.text('AnyPS5 Remote  ·  v$appVersion'), findsOneWidget);
    expect(find.text('Utku Halis'), findsOneWidget);
    expect(find.text('github.com/utkuhalis/AnyPS5-ARM'), findsOneWidget);
    expect(find.text('github.com/boykopovar/AnyPS5'), findsOneWidget);
  });
}
