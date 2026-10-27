import 'dart:convert';

import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/ui/handoff_card.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:anyps5_remote/ui/together_sheet.dart';
import 'package:anyps5_remote/ui/update_required_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the Mac asking shows a card, and Allow answers it', (
    tester,
  ) async {
    final asked = ValueNotifier<TogetherHandoff?>(null);
    final answers = <(String, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HandoffCard(
            asked: asked,
            handle: 'utku',
            onAnswer: (ask, approve) async => answers.add((ask.id, approve)),
          ),
        ),
      ),
    );
    expect(find.text('Allow'), findsNothing);
    asked.value = const TogetherHandoff(id: 'h1', deviceName: 'MacBook');
    await tester.pumpAndSettle();
    expect(
      find.text('MacBook wants to sign in to AnyTogether as @utku'),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(answers, [('h1', true)]);
  });

  testWidgets(
    'AnyTogether retiring this version shows Update required, Later hides it',
    (tester) async {
      final tooOld = ValueNotifier<ClientTooOld?>(null);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateRequiredCard(
              tooOld: tooOld,
              open: (page) async => opened.add(page),
            ),
          ),
        ),
      );
      expect(find.text('Update required'), findsNothing);
      tooOld.value = ClientTooOld(
        minimum: '1.17.0',
        current: '1.16.0',
        downloadUrl: Uri.parse('https://anytogether.test/download'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(
        find.textContaining(
          'needs AnyPS5 Remote 1.17.0 or newer; this is 1.16.0',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://anytogether.test/download')]);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsNothing);
      // A newer minimum asks again.
      tooOld.value = const ClientTooOld(minimum: '1.18.0');
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  /// An iPhone 14 Pro on its side: the Mac's way and the email way side by side, on the screen.
  testWidgets('signed out, the sheet offers the Mac first and fits sideways', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final account = TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      clientName: 'test',
    );
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var used = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTogether(
              context,
              account: account,
              macName: 'MacBook',
              onUseMac: () async => used++,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final text in ["Use MacBook's account", 'Email me a code']) {
      expect(
        tester.getRect(find.text(text)).bottom,
        lessThanOrEqualTo(screen.height),
        reason: text,
      );
    }
    await tester.tap(find.text("Use MacBook's account"));
    await tester.pump();
    expect(used, 1);
  });

  testWidgets('without a Mac only the email way shows', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final account = TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      clientName: 'test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTogether(
              context,
              account: account,
              macName: null,
              onUseMac: null,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('account'), findsNothing);
    expect(find.text('Email me a code'), findsOneWidget);
  });

  testWidgets('signed in, the sheet goes on to the friends', (tester) async {
    SharedPreferences.setMockInitialValues({
      'together.session': jsonEncode({
        'accessToken': 'a',
        'accessExpiry': DateTime.now()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
        'refreshToken': 'r',
        'user': {'id': 'me', 'handle': 'utku', 'displayName': 'Utku'},
      }),
    });
    final account = TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      clientName: 'test',
    );
    final opened = <TogetherTab>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTogether(
              context,
              account: account,
              macName: null,
              onUseMac: null,
              onOpen: opened.add,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('@utku'), findsOneWidget);
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(opened, [TogetherTab.friends]);
    expect(find.text('@utku'), findsNothing);
  });

  testWidgets('the server can be changed, and the launcher\'s is offered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final account = TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      clientName: 'test',
    );
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTogether(
              context,
              account: account,
              macName: 'MacBook',
              onUseMac: () async {},
              launcherServer: Uri.parse('https://home.example.org'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('anytogether.net'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Server'),
      'http://together.example.org',
    );
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(
      find.text('An https:// address, or http:// on your home network'),
      findsOneWidget,
    );
    expect(account.base.host, 'anytogether.net');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MacBook uses home.example.org'));
    await tester.pumpAndSettle();
    expect(account.base, Uri.parse('https://home.example.org'));
    expect(find.text('home.example.org'), findsOneWidget);
    expect(find.text('MacBook uses home.example.org'), findsNothing);
  });
}
