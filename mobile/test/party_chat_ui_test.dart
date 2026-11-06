import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'party_chat_test.dart' show chatView, party, said;
import 'support/scripted_hub.dart';

void main() {
  /// An iPhone 14 Pro on its side (wide enough for the voice and chat column), or an SE.
  void screen(WidgetTester tester, {bool small = false}) {
    tester.view.physicalSize = small
        ? const Size(1334, 750)
        : const Size(2556, 1179);
    tester.view.devicePixelRatio = small ? 2 : 3;
    addTearDown(tester.view.reset);
  }

  Future<ScriptedAccount> open(
    WidgetTester tester, {
    String? chat = 'pc1',
    List<Map<String, dynamic>>? history,
    int readSeq = 3,
    Strings strings = Strings.english,
  }) async {
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    final messages =
        history ??
        [
          said(1, text: 'one'),
          said(2, author: 'me', text: 'two'),
          said(3, text: 'three'),
        ];
    account.answer = (method, path, body) =>
        switch ((method, path.split('?').first)) {
          ('GET', 'me/party') => {
            'party': party('p1', members: ['me', 'ece'], chat: chat),
            'invites': <Object>[],
          },
          ('GET', 'conversations/pc1') => chatView(
            'pc1',
            lastSeq: messages.length,
            readSeq: readSeq,
          ),
          ('GET', 'conversations/pc1/messages') => {
            'messages': messages,
            'more': false,
          },
          ('POST', 'conversations/pc1/messages') => said(
            9,
            author: 'me',
            id: body!['clientId'] as String,
            text: body['text'] as String,
          ),
          ('POST', 'reports') => {'id': 'r1'},
          ('GET', 'me/friends') => {'friends': <Object>[]},
          _ => <String, dynamic>{},
        };
    await tester.pumpWidget(
      Texts(
        strings: strings,
        child: MaterialApp(
          home: TogetherScreen(hub: hub, tab: TogetherTab.party),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    return account;
  }

  testWidgets('beside the voice: the chat, read while shown, text only', (
    tester,
  ) async {
    screen(tester);
    final account = await open(tester, readSeq: 1);
    expect(find.text('CHAT'), findsOneWidget);
    expect(find.text('VOICE'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    expect(find.text('ECE'), findsWidgets);
    // No photos in a party's chat.
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    expect(account.paths('POST'), contains('conversations/pc1/read'));
    await tester.enterText(find.byType(TextField), 'on my way');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final sent = account.calls.lastWhere(
      (c) => c.$2 == 'conversations/pc1/messages' && c.$1 == 'POST',
    );
    expect(sent.$3?['text'], 'on my way');
    expect(sent.$3?.containsKey('attachments'), isFalse);
    expect(find.text('on my way'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty chat says who reads it, in Turkish too', (
    tester,
  ) async {
    screen(tester);
    await open(tester, history: const [], strings: Strings.turkish);
    expect(
      find.text(
        'Bunu yalnız parti okur. Katılan herkes o ana kadarki mesajları görür.',
      ),
      findsOneWidget,
    );
    expect(find.text('Partiye yaz'), findsOneWidget);
    expect(find.text('SOHBET'), findsOneWidget);
  });

  testWidgets('no chat from an older server: the party as before', (
    tester,
  ) async {
    screen(tester);
    await open(tester, chat: null);
    expect(find.text('CHAT'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('VOICE'), findsOneWidget);
    expect(find.text('INVITE FRIENDS'), findsOneWidget);
  });

  testWidgets('someone who left is a former member', (tester) async {
    screen(tester);
    await open(
      tester,
      history: [
        said(1, author: 'zed', text: 'bye all'),
        said(2),
      ],
    );
    // Above the newest, in the thread's short column.
    expect(find.text('Former member', skipOffstage: false), findsOneWidget);
    expect(find.text('bye all', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a message is reported with a reason', (tester) async {
    screen(tester);
    final account = await open(tester);
    await tester.longPress(find.text('three'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report this message'), findsOneWidget);
    expect(
      find.text(
        'A moderator reads it. Its author is not told who sent the report.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Spam or ads'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    final sent = account.calls.lastWhere((c) => c.$2 == 'reports');
    expect(sent.$3, {
      'targetKind': 'message',
      'targetId': said(3)['id'],
      'reason': 'spam',
    });
    expect(find.text('Thanks. A moderator will look at it.'), findsOneWidget);
    // One's own message has no report.
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.ensureVisible(find.text('two', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('two'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsNothing);
    expect(find.text('Unsend'), findsOneWidget);
  });

  testWidgets('a small phone: the party or the chat, a dot while unread', (
    tester,
  ) async {
    screen(tester, small: true);
    final account = await open(tester, readSeq: 1);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester
          .widget<AnimatedScale>(
            find.ancestor(
              of: find.byKey(const ValueKey('party-chat-unread')),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale,
      1,
    );
    expect(account.paths('POST'), isNot(contains('conversations/pc1/read')));
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(account.paths('POST'), contains('conversations/pc1/read'));
    // The keyboard of a phone on its side takes about half the height: the composer stays
    // above it.
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await tester.pumpAndSettle();
    final height = tester.view.physicalSize.height / 2;
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(height - 200),
    );
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Party').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('ECE'), findsWidgets);
  });

  testWidgets('wide, with the keyboard up the chat keeps its composer', (
    tester,
  ) async {
    screen(tester);
    await open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 560);
    await tester.pumpAndSettle();
    final height = tester.view.physicalSize.height / 3;
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(height - 560 / 3),
    );
    expect(tester.takeException(), isNull);
  });
}
