import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/ui/setup_screen.dart';
import 'package:anyps5_remote/ui/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Session> session() async {
  SharedPreferences.setMockInitialValues({});
  return Session(
    preferences: await SharedPreferences.getInstance(),
    deviceName: 'Pixel 8',
  );
}

Future<void> show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(2400, 1080);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
}

void main() {
  testWidgets('the welcome screen starts the setup', (tester) async {
    var started = false;
    await show(tester, WelcomeScreen(onStart: () => started = true));
    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.text('Start'));
    expect(started, isTrue);
  });

  testWidgets('setup shows each step as it happens', (tester) async {
    final link = await session();
    await show(
      tester,
      SetupScreen(
        session: link,
        foundMac: null,
        showManual: false,
        onAddress: (_) {},
        onRetry: () {},
      ),
    );
    expect(find.text('Looking for AnyPS5 on the Mac'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi'), findsWidgets);
    expect(find.textContaining('with a cable'), findsWidgets);

    await show(
      tester,
      SetupScreen(
        session: link,
        foundMac: 'Utku MacBook',
        showManual: false,
        onAddress: (_) {},
        onRetry: () {},
      ),
    );
    expect(find.text('Utku MacBook found'), findsOneWidget);

    link
      ..status = ConnectionStatus.pairing
      ..code = '4821';
    await show(
      tester,
      SetupScreen(
        session: link,
        foundMac: 'Utku MacBook',
        showManual: false,
        onAddress: (_) {},
        onRetry: () {},
      ),
    );
    for (final digit in ['4', '8', '2', '1']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.textContaining('press Allow'), findsOneWidget);
  });

  testWidgets('setup offers the address and tips when no Mac is found', (
    tester,
  ) async {
    final link = await session();
    await show(
      tester,
      SetupScreen(
        session: link,
        foundMac: null,
        showManual: true,
        onAddress: (_) {},
        onRetry: () {},
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('phone support'), findsOneWidget);
  });

  testWidgets('a refusal offers to try again', (tester) async {
    final link = await session();
    var retried = false;
    link
      ..status = ConnectionStatus.rejected
      ..rejectedReason = 'denied';
    await show(
      tester,
      SetupScreen(
        session: link,
        foundMac: 'Mac',
        showManual: false,
        onAddress: (_) {},
        onRetry: () => retried = true,
      ),
    );
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
  });
}
