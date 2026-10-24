import 'dart:io';

import 'package:anyps5_remote/social_strings.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/notifications.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/notifications_view.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

String noteId(int n) =>
    '0190b000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> note(
  int n,
  String kind, {
  bool read = false,
  Map<String, dynamic> data = const {},
  bool actor = true,
}) => {
  'id': noteId(n),
  'kind': kind,
  'actor': actor ? card('ece', name: 'Ece') : null,
  'subjectId': data['conversationId'],
  'data': data,
  'read': read,
  'createdAt': DateTime.now()
      .subtract(Duration(minutes: n))
      .toUtc()
      .toIso8601String(),
  'updatedAt': DateTime.now()
      .subtract(Duration(minutes: n))
      .toUtc()
      .toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the notifications', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/notifications/unread') => (200, {'unread': 2}),
        ('GET', '/api/v1/me/notifications?limit=30') => (
          200,
          {
            'notifications': [
              note(1, 'friend_request'),
              note(
                2,
                'message',
                data: {
                  'conversationId': 'c1',
                  'title': null,
                  'group': false,
                  'count': 3,
                  'text': 'gg',
                },
              ),
              note(3, 'missed_call', read: true),
              note(4, 'something_new'),
            ],
            'unread': 2,
            'more': true,
          },
        ),
        ('GET', final p) when p.contains('before=') => (
          200,
          {
            'notifications': [
              note(3, 'missed_call', read: true),
              note(5, 'warning', actor: false, data: {'reason': 'spam'}),
            ],
            'unread': 2,
            'more': false,
          },
        ),
        ('POST', '/api/v1/me/notifications/read-all') => (200, {'unread': 0}),
        ('POST', final p) when p.endsWith('/read') => (200, {'unread': 1}),
        ('GET', '/api/v1/me/notifications/settings') => (
          200,
          {
            'settings': {
              'friend_request': true,
              'message': false,
              'digest': false,
            },
            'push': null,
            'canMail': true,
          },
        ),
        ('PATCH', '/api/v1/me/notifications/settings') => (
          200,
          {
            'settings': {'message': false, 'digest': true},
            'push': null,
            'canMail': true,
          },
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
      // Live, and the bell counted: nothing else asks the server meanwhile.
      await until(() => hub.notifications.unread == 2);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Notifications notes() => hub.notifications;

    test('the bell counts as soon as the socket is live', () async {
      expect(notes().unread, 2);
      expect(notes().loaded, isFalse);
      expect(
        server.requests.where((r) => r.$2 == '/api/v1/me/notifications/unread'),
        hasLength(1),
      );
    });

    test('the list, newest first, a page at a time', () async {
      await notes().refresh();
      // The kind this app does not know is left out.
      expect(notes().items.map((n) => n.kind), [
        NoticeKind.friendRequest,
        NoticeKind.message,
        NoticeKind.missedCall,
      ]);
      expect(notes().items[1].count, 3);
      expect(notes().items.first.actor!.displayName, 'Ece');
      expect(notes().more, isTrue);
      await notes().older();
      expect(notes().items.length, 4);
      expect(notes().items.last.kind, NoticeKind.warning);
      expect(notes().items.last.actor, isNull);
      expect(notes().more, isFalse);
    });

    test('reading one, or all, here and on the server', () async {
      await notes().refresh();
      await notes().read(notes().items.first);
      expect(
        server.requests.last.$2,
        '/api/v1/me/notifications/${noteId(1)}/read',
      );
      expect(notes().items.first.read, isTrue);
      expect(notes().unread, 1);
      await notes().readAll();
      expect(server.requests.last.$2, '/api/v1/me/notifications/read-all');
      expect(notes().items.every((n) => n.read), isTrue);
      expect(notes().unread, 0);
    });

    test(
      'live: a new one on top, one gathering moves up, read elsewhere',
      () async {
        await notes().refresh();
        server.push('notification', {
          'notification': note(
            9,
            'party_invite',
            data: {'partyId': 'p1', 'size': 2},
          ),
          'unread': 3,
        });
        await until(() => notes().items.first.kind == NoticeKind.partyInvite);
        expect(notes().unread, 3);
        server.push('notification', {
          'notification': note(
            2,
            'message',
            data: {'conversationId': 'c1', 'count': 4, 'text': 'again'},
          ),
          'unread': 3,
        });
        await until(() => notes().items.first.id == noteId(2));
        expect(notes().items.first.count, 4);
        expect(notes().items.where((n) => n.id == noteId(2)).length, 1);
        server.push('notification.read', {
          'ids': [noteId(9)],
          'unread': 2,
        });
        await until(() => notes().unread == 2);
        expect(notes().items.firstWhere((n) => n.id == noteId(9)).read, isTrue);
        expect(
          notes().items.firstWhere((n) => n.id == noteId(1)).read,
          isFalse,
        );
        server.push('notification.read', {'ids': null, 'unread': 0});
        await until(() => notes().unread == 0);
        expect(notes().items.every((n) => n.read), isTrue);
      },
    );

    test('what to be told about, one kind at a time', () async {
      final settings = await notes().settings();
      expect(settings.kinds[NoticeKind.message], isFalse);
      expect(settings.kinds[NoticeKind.missedCall], isTrue);
      expect(settings.canMail, isTrue);
      final saved = await notes().setting('digest', true);
      expect(server.requests.last.$1, 'PATCH');
      expect(server.requests.last.$3, {'digest': true});
      expect(saved.digest, isTrue);
    });
  });

  group('on the phone held sideways', () {
    late TogetherHub hub;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      hub = TogetherHub(
        account: TogetherAccount(
          preferences: await SharedPreferences.getInstance(),
          clientName: 'test',
        ),
      );
    });

    tearDown(() => hub.dispose());

    testWidgets('the list reads well, and a tap leads to the conversation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2556, 1179);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      hub.notifications
        ..items = [
          Notice.fromJson(note(1, 'friend_request'))!,
          Notice.fromJson(
            note(
              2,
              'message',
              data: {
                'conversationId': 'c1',
                'group': true,
                'title': 'Raid night',
                'count': 3,
                'text': 'gg',
              },
            ),
          )!,
          Notice.fromJson(note(3, 'missed_call', read: true))!,
        ]
        ..unread = 2
        ..loaded = true;
      final opened = <NoticeKind>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationsPane(
              hub: hub,
              onOpen: (n) => opened.add(n.kind),
            ),
          ),
        ),
      );
      await tester.pump();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in [
        'Ece wants to be your friend.',
        'Ece and others wrote 3 messages in Raid night.',
        'Missed call from Ece.',
        'Mark all read',
      ]) {
        final found = find.textContaining(text, findRichText: true).first;
        final box = tester.getRect(found);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
      }
      expect(find.text('gg'), findsOneWidget);
      await tester.tap(
        find.textContaining('Raid night', findRichText: true).first,
      );
      await tester.pump();
      expect(opened, [NoticeKind.message]);
      // Read at once, even signed out here, where the server is not reached.
      expect(hub.notifications.items[1].read, isTrue);
      expect(hub.notifications.unread, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a looking-for-group ask and a yes read well, in both languages',
      (tester) async {
        tester.view.physicalSize = const Size(2556, 1179);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        const game = {
          'postId': 'l1',
          'titleId': 'PPSA01234',
          'gameNames': {'en': 'Astro Bot', 'tr': 'Astro Bot TR'},
          'purpose': 'coop',
        };
        hub.notifications
          ..items = [
            Notice.fromJson(
              note(1, 'lfg_request', data: {...game, 'count': 1}),
            )!,
            Notice.fromJson(
              note(2, 'lfg_request', data: {...game, 'count': 3}),
            )!,
            Notice.fromJson(
              note(
                3,
                'lfg_accepted',
                data: {
                  ...game,
                  'invite': {'kind': 'party', 'id': 'p1'},
                },
              ),
            )!,
            Notice.fromJson(
              note(
                4,
                'lfg_accepted',
                data: {
                  ...game,
                  'invite': {'kind': 'share_play', 'id': 's1'},
                },
              ),
            )!,
          ]
          ..unread = 4
          ..loaded = true;
        final opened = <NoticeKind>[];
        Widget pane(Strings strings) => MaterialApp(
          home: Texts(
            strings: strings,
            child: Scaffold(
              body: NotificationsPane(
                hub: hub,
                onOpen: (n) => opened.add(n.kind),
              ),
            ),
          ),
        );
        await tester.pumpWidget(pane(Strings.english));
        await tester.pump();
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (final text in [
          'Ece wants in on your Astro Bot post.',
          'Ece and 2 more want in on your Astro Bot post.',
          'Ece let you in for Astro Bot.',
          'Your party invite is waiting.',
          'Watch and play along.',
        ]) {
          final found = find.textContaining(text, findRichText: true).first;
          final box = tester.getRect(found);
          expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
          expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
        }
        await tester.tap(
          find.textContaining('Ece wants in', findRichText: true).first,
        );
        await tester.pump();
        expect(opened, [NoticeKind.lfgRequest]);
        await tester.pumpWidget(pane(Strings.turkish));
        await tester.pump();
        expect(
          find.textContaining(
            'Ece, Astro Bot TR ilanına katılmak istiyor.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Ece seni Astro Bot TR için kabul etti.',
            findRichText: true,
          ),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      },
    );

    test('the looking-for-group kinds can be turned off', () {
      expect(optionalNoticeKinds, contains(NoticeKind.lfgRequest));
      expect(optionalNoticeKinds, contains(NoticeKind.lfgAccepted));
      expect(
        Strings.english.noticeKind(NoticeKind.lfgRequest),
        'People asking in on your posts',
      );
      expect(
        Strings.turkish.noticeKind(NoticeKind.lfgAccepted),
        'Bir ilan sahibi seni kabul ettiğinde',
      );
    });

    testWidgets('the rail has the bell, which opens the list', (tester) async {
      tester.view.physicalSize = const Size(2556, 1179);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'together.session': '{"accessToken":"a","accessExpiry":"2999-01-01T00:00:00.000","refreshToken":"r","user":{"id":"me","handle":"utku","displayName":"Utku"}}',
      });
      final signedIn = TogetherHub(
        account: TogetherAccount(
          preferences: await SharedPreferences.getInstance(),
          clientName: 'test',
          base: Uri.parse('http://127.0.0.1:9'),
        ),
      );
      addTearDown(signedIn.dispose);
      signedIn.socket.stop();
      signedIn.notifications
        ..unread = 4
        ..loaded = true;
      await tester.pumpWidget(MaterialApp(home: TogetherScreen(hub: signedIn)));
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      final title = tester.getRect(find.text('AnyTogether'));
      expect(title.height, lessThan(30));
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mark all read'), findsOneWidget);
      signedIn.socket.stop();
      // Requests this test never answers run out.
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
    });
  });
}
