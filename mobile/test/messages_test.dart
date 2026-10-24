import 'dart:io';

import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

Map<String, dynamic> message(
  String conversation,
  int seq, {
  String author = 'ece',
  String? id,
  String text = 'hi',
}) => {
  'id': id ?? '0190a000-0000-7000-8000-${seq.toString().padLeft(12, '0')}',
  'conversationId': conversation,
  'seq': seq,
  'authorId': author,
  'text': text,
  'replyTo': null,
  'editedAt': null,
  'deletedAt': null,
  'createdAt': DateTime.utc(2026, 10, 24, 12, seq).toIso8601String(),
};

Map<String, dynamic> conversation(
  String id,
  String with_, {
  int lastSeq = 3,
  int readSeq = 1,
}) => {
  'id': id,
  'kind': 'direct',
  'title': null,
  'createdBy': 'me',
  'members': [card('me'), card(with_)],
  'lastSeq': lastSeq,
  'readSeq': readSeq,
  'unread': lastSeq - readSeq,
  'lastMessage': message(id, lastSeq, author: with_),
  'updatedAt': DateTime.utc(2026, 10, 24, 12, lastSeq).toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a message id is a UUIDv7', () {
    final id = uuidv7();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
      reason: id,
    );
    expect(uuidv7(), isNot(id));
  });

  group('messages', () {
    late FakeServer server;
    late TogetherHub hub;
    var failSend = false;

    setUp(() async {
      HttpOverrides.global = null;
      failSend = false;
      server = FakeServer();
      server.answer = (method, path, body) {
        if (path == '/api/v1/me/conversations') {
          return (
            200,
            {
              'conversations': [
                conversation('c1', 'ece'),
                conversation('c2', 'ali', lastSeq: 5, readSeq: 5),
              ],
            },
          );
        }
        if (path == '/api/v1/me/conversations/unread') {
          return (200, {'conversations': 1, 'messages': 2});
        }
        if (path.startsWith('/api/v1/conversations/c1/messages?')) {
          return (
            200,
            {
              'messages': [message('c1', 2), message('c1', 3)],
              'more': true,
            },
          );
        }
        if (method == 'POST' && path == '/api/v1/conversations/c1/messages') {
          if (failSend) return (503, {'code': 'internal', 'title': 'down'});
          return (
            201,
            message('c1', 4, author: 'me', id: body!['clientId'] as String),
          );
        }
        if (method == 'POST' && path == '/api/v1/conversations') {
          return (200, conversation('c2', 'ali', lastSeq: 5, readSeq: 5));
        }
        return (204, null);
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Messages messages() => hub.messages;

    test('the list and the unread count come once live', () async {
      await until(() => messages().loaded && messages().unread == 2);
      expect(messages().conversations.map((c) => c.id), ['c1', 'c2']);
      expect(messages().conversations.first.name('me'), 'ECE');
      expect(messages().conversations.first.unread, 2);
      expect(hub.badge, 2);
    });

    test('opening a conversation shows its messages and reads them', () async {
      await until(() => messages().unread == 2);
      await messages().show('c1');
      expect(messages().thread.map((m) => m.seq), [2, 3]);
      expect(messages().more, isTrue);
      expect(messages().unread, 0);
      expect(server.requests.last.$2, '/api/v1/conversations/c1/read');
      expect(server.requests.last.$3, {'upToSeq': 3});
    });

    test('a sent message shows at once, then settles with its seq', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      final sending = messages().send('  selam  ');
      expect(messages().thread.last.pending, isTrue);
      expect(messages().thread.last.text, 'selam');
      await sending;
      final sent = server.requests.lastWhere((r) => r.$1 == 'POST').$3!;
      expect(sent['text'], 'selam');
      expect(messages().thread.last.seq, 4);
      expect(messages().thread.last.id, sent['clientId']);
      expect(messages().thread.last.pending, isFalse);
      // The gateway's copy of it does not show twice.
      server.push(
        'message.created',
        message('c1', 4, author: 'me', id: sent['clientId'] as String),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(messages().thread.where((m) => m.seq == 4), hasLength(1));
      expect(messages().conversations.first.lastMessage?.text, 'hi');
    });

    test('a message that did not go is sent again with the same id', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      failSend = true;
      await messages().send('selam');
      expect(messages().thread.last.failed, isTrue);
      final first = server.requests.lastWhere((r) => r.$1 == 'POST').$3!;
      failSend = false;
      await messages().retry(messages().thread.last);
      final again = server.requests.lastWhere((r) => r.$1 == 'POST').$3!;
      expect(again['clientId'], first['clientId']);
      expect(messages().thread.last.failed, isFalse);
      expect(messages().thread.last.seq, 4);
    });

    test(
      'a live message counts as unread unless its conversation is open',
      () async {
        await until(() => messages().unread == 2);
        server.push('message.created', message('c2', 6, author: 'ali'));
        await until(() => messages().unread == 3);
        expect(messages().conversations.first.id, 'c2');
        expect(messages().conversations.first.unread, 1);
        await messages().show('c1');
        server.push('message.created', message('c1', 4, text: 'naber'));
        await until(() => messages().thread.length == 3);
        expect(messages().thread.last.text, 'naber');
        await until(() => server.requests.any((r) => r.$3?['upToSeq'] == 4));
        messages().hide();
        expect(messages().openId, isNull);
      },
    );

    test('writing to a friend opens their conversation', () async {
      await until(() => messages().loaded);
      await messages().withFriend('ali');
      expect(
        server.requests.firstWhere((r) => r.$2 == '/api/v1/conversations').$3,
        {
          'members': ['ali'],
        },
      );
      expect(messages().openId, 'c2');
    });
  });

  /// An iPhone 14 Pro on its side, the keyboard up: the composer stays above it.
  testWidgets('a thread with its composer fits a phone held sideways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final hub = TogetherHub(
      account: TogetherAccount(
        preferences: await SharedPreferences.getInstance(),
        clientName: 'test',
      ),
    );
    addTearDown(hub.dispose);
    final ece = Conversation.fromJson(conversation('c1', 'ece'));
    hub.messages
      ..conversations = [ece]
      ..loaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TogetherScreen(hub: hub, tab: TogetherTab.messages),
      ),
    );
    await tester.pumpAndSettle();
    hub.messages
      ..openId = 'c1'
      ..thread = [
        for (var seq = 1; seq <= 12; seq++)
          ChatMessage.fromJson(
            message('c1', seq, author: seq.isEven ? 'me' : 'ece'),
          ),
      ]
      ..notifyListeners();
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(screen.height),
    );
    // The keyboard of a phone on its side takes about half the height.
    tester.view.viewInsets = const FakeViewPadding(bottom: 560);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(screen.height - 560 / 3),
    );
    expect(find.textContaining('ECE'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(Person.fromJson(card('ece')).initials, 'E');
  });
}
