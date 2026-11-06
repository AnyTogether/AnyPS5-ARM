import 'dart:io';

import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/together/party_chat.dart';
import 'package:anyps5_remote/together/reports.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// A party as the API shows it to a member, with its chat when [chat] is given.
Map<String, dynamic> party(
  String id, {
  List<String> members = const ['me', 'ece'],
  String leader = 'me',
  String? chat,
}) => {
  'id': id,
  'leaderId': leader,
  'privacy': 'invite',
  'members': [
    for (final member in members)
      {...card(member), 'joinedAt': '2026-11-06T12:00:00Z'},
  ],
  'invited': <Object>[],
  'call': null,
  'public': null,
  'conversationId': ?chat,
  'createdAt': '2026-11-06T12:00:00Z',
};

Map<String, dynamic> said(
  int seq, {
  String chat = 'pc1',
  String author = 'ece',
  String? id,
  String? text = 'hi',
  int? replyTo,
  bool deleted = false,
}) => {
  'id': id ?? '0190b000-0000-7000-8000-${seq.toString().padLeft(12, '0')}',
  'conversationId': chat,
  'seq': seq,
  'authorId': author,
  'text': deleted ? null : text,
  'replyTo': replyTo,
  'editedAt': null,
  'editCount': 0,
  'reactions': <Object>[],
  'deletedAt': deleted ? '2026-11-06T12:40:00Z' : null,
  'createdAt': DateTime.utc(2026, 11, 6, 12, seq).toIso8601String(),
};

/// The party's chat as GET /conversations/{id} answers it.
Map<String, dynamic> chatView(
  String id, {
  List<String> members = const ['me', 'ece'],
  int lastSeq = 3,
  int readSeq = 1,
}) => {
  'id': id,
  'kind': 'group',
  'title': null,
  'createdBy': 'me',
  'partyId': 'p1',
  'members': [for (final m in members) card(m)],
  'lastSeq': lastSeq,
  'readSeq': readSeq,
  'unread': lastSeq - readSeq,
  'muted': true,
  'lastMessage': null,
  'updatedAt': '2026-11-06T12:03:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the party', () {
    test('brings its chat, and keeps it as the party changes', () {
      final with_ = Party.fromJson(party('p1', chat: 'pc1'));
      expect(with_.conversationId, 'pc1');
      expect(
        with_.copyWith(members: with_.members.take(1).toList()).conversationId,
        'pc1',
      );
      // An older server, or someone only looking at a public party: no chat.
      expect(Party.fromJson(party('p1')).conversationId, isNull);
    });
  });

  group('party chat', () {
    late FakeServer server;
    late TogetherHub hub;
    late Map<String, dynamic>? current;
    var history = <Map<String, dynamic>>[];
    var refusal = (0, '');

    setUp(() async {
      HttpOverrides.global = null;
      current = party('p1', chat: 'pc1');
      history = [said(1), said(2, author: 'me'), said(3, text: 'ready?')];
      refusal = (0, '');
      server = FakeServer();
      server.answer = (method, path, body) {
        switch ((method, path.split('?').first)) {
          case ('GET', '/api/v1/me/party'):
            return (200, {'party': current, 'invites': <Object>[]});
          case ('GET', '/api/v1/me/conversations'):
            return (200, {'conversations': <Object>[]});
          case ('GET', '/api/v1/me/conversations/unread'):
            return (200, {'conversations': 0, 'messages': 0});
          case ('GET', '/api/v1/conversations/pc1'):
            return (200, chatView('pc1'));
          case ('GET', '/api/v1/conversations/pc1/messages'):
            if (path.contains('before=')) {
              return (
                200,
                {
                  'messages': [said(0, text: 'first')],
                  'more': false,
                },
              );
            }
            if (path.contains('after=')) {
              return (
                200,
                {
                  'messages': [said(4, text: 'while away')],
                  'more': false,
                },
              );
            }
            return (200, {'messages': history, 'more': true});
          case ('POST', '/api/v1/conversations/pc1/messages'):
            if (refusal.$1 != 0) {
              return (
                refusal.$1,
                {'status': refusal.$1, 'code': refusal.$2, 'title': 'no'},
              );
            }
            return (
              201,
              said(
                9,
                author: 'me',
                id: body!['clientId'] as String,
                text: body['text'] as String,
                replyTo: body['replyTo'] as int?,
              ),
            );
          case ('POST', '/api/v1/reports'):
            return (201, {'id': 'r1'});
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

    PartyChat chat() => hub.partyChat;

    int asked(String method, String path) => server.requests
        .where((r) => r.$1 == method && r.$2.split('?').first == path)
        .length;

    test('comes with the party: its newest page, unread until shown', () async {
      await until(() => chat().loaded);
      expect(chat().id, 'pc1');
      expect(chat().thread.map((m) => m.seq), [1, 2, 3]);
      expect(chat().more, isTrue);
      expect(
        server.requests.any(
          (r) => r.$2 == '/api/v1/conversations/pc1/messages?limit=40',
        ),
        isTrue,
      );
      expect(chat().unread, 2);
      chat().show();
      await until(() => asked('POST', '/api/v1/conversations/pc1/read') == 1);
      expect(server.requests.lastWhere((r) => r.$1 == 'POST').$3, {
        'upToSeq': 3,
      });
      expect(chat().unread, 0);
    });

    test('older messages come above with before=', () async {
      await until(() => chat().loaded);
      await chat().older();
      expect(
        server.requests.any((r) => r.$2.endsWith('messages?limit=40&before=1')),
        isTrue,
      );
      expect(chat().thread.first.text, 'first');
      expect(chat().more, isFalse);
    });

    test('a message is sent as text only, with the seq it answers', () async {
      await until(() => chat().loaded);
      final sending = chat().send('  go go  ', replyTo: chat().thread.last);
      expect(chat().thread.last.pending, isTrue);
      await sending;
      final sent = server.requests.lastWhere((r) => r.$1 == 'POST').$3!;
      expect(sent.keys.toSet(), {'clientId', 'text', 'replyTo'});
      expect(sent['text'], 'go go');
      expect(sent['replyTo'], 3);
      expect(chat().thread.last.seq, 9);
      expect(chat().thread.last.pending, isFalse);
      // The gateway's copy of it does not show twice.
      server.push(
        'message.created',
        said(9, author: 'me', id: sent['clientId'] as String, text: 'go go'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chat().thread.where((m) => m.seq == 9), hasLength(1));
    });

    test('a refusal stays on the message: muted or too many', () async {
      await until(() => chat().loaded);
      refusal = (403, 'account_muted');
      await chat().send('hey');
      expect(chat().thread.last.failed, isTrue);
      expect(chat().thread.last.problem?.code, 'account_muted');
      expect(chat().thread.last.refused, isTrue);
      refusal = (429, 'rate_limited');
      await chat().send('hey again');
      expect(chat().thread.last.problem?.code, 'rate_limited');
      expect(chat().thread.last.refused, isFalse);
      refusal = (0, '');
      await chat().retry(chat().thread.last);
      expect(chat().thread.last.failed, isFalse);
    });

    test('live messages land here, never in the inbox or its badge', () async {
      await until(() => chat().loaded && hub.messages.loaded);
      final lists = asked('GET', '/api/v1/me/conversations');
      server.push('message.created', said(4, text: 'hello party'));
      await until(() => chat().thread.length == 4);
      expect(chat().unread, 3);
      server.push('message.created', said(5, author: 'can'));
      await until(() => chat().thread.length == 5);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(hub.messages.unread, 0);
      expect(hub.messages.conversations, isEmpty);
      expect(hub.badge, 0);
      expect(asked('GET', '/api/v1/me/conversations'), lists);
      // Shown, what comes is read at once.
      chat().show();
      server.push('message.created', said(6));
      await until(
        () => server.requests.any(
          (r) =>
              r.$2 == '/api/v1/conversations/pc1/read' && r.$3?['upToSeq'] == 6,
        ),
      );
      expect(chat().unread, 0);
      chat().hide();
    });

    test(
      'a message for a conversation the list lacks loads the list once',
      () async {
        await until(() => hub.messages.loaded);
        final lists = asked('GET', '/api/v1/me/conversations');
        server.push('message.created', said(1, chat: 'elsewhere'));
        await until(() => asked('GET', '/api/v1/me/conversations') > lists);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        server.push('message.created', said(2, chat: 'elsewhere'));
        server.push('message.created', said(3, chat: 'elsewhere'));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(asked('GET', '/api/v1/me/conversations'), lists + 1);
      },
    );

    test('edits, unsends and reactions follow live', () async {
      await until(() => chat().loaded);
      server.push('message.updated', {...said(3, text: 'ready??')});
      await until(() => chat().thread.last.text == 'ready??');
      server.push('message.reactions', {
        'conversationId': 'pc1',
        'seq': 3,
        'reactions': [
          {
            'reaction': 'gg',
            'count': 1,
            'userIds': ['me'],
          },
        ],
      });
      await until(() => chat().thread.last.reactions.isNotEmpty);
      server.push('message.deleted', said(3, deleted: true));
      await until(() => chat().thread.last.deleted);
      expect(chat().thread.last.reactions, isEmpty);
      // Another conversation's events are not this chat's.
      server.push('message.updated', said(1, chat: 'c9', text: 'other'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chat().thread.first.text, 'hi');
    });

    test('edit, unsend and react call the message routes', () async {
      await until(() => chat().loaded);
      final mine = chat().thread[1];
      await chat().edit(mine, 'new words').catchError((_) {});
      await chat().unsend(mine).catchError((_) {});
      await chat()
          .react(chat().thread.last, MessageReaction.fire)
          .catchError((_) {});
      final paths = [
        for (final r in server.requests)
          if (r.$1 != 'GET') '${r.$1} ${r.$2}',
      ];
      expect(paths, contains('PATCH /api/v1/conversations/pc1/messages/2'));
      expect(paths, contains('DELETE /api/v1/conversations/pc1/messages/2'));
      expect(
        paths,
        contains('PUT /api/v1/conversations/pc1/messages/3/reactions/fire'),
      );
    });

    test('a message is reported for a moderator to read', () async {
      await until(() => chat().loaded);
      await chat().report(
        chat().thread.last,
        ReportReason.harassment,
        note: '  rude  ',
      );
      final sent = server.requests.lastWhere((r) => r.$2 == '/api/v1/reports');
      expect(sent.$3, {
        'targetKind': 'message',
        'targetId': chat().thread.last.id,
        'reason': 'harassment',
        'note': 'rude',
      });
    });

    test('after a reconnect it catches up with after=', () async {
      await until(() => chat().loaded);
      server.push('live.ready', <String, dynamic>{});
      await until(() => chat().thread.any((m) => m.text == 'while away'));
      expect(
        server.requests.any((r) => r.$2.endsWith('messages?limit=100&after=3')),
        isTrue,
      );
    });

    test(
      'who wrote: a member, someone seen in the party, or a former member',
      () async {
        await until(() => chat().loaded);
        expect(chat().author('ece')?.displayName, 'ECE');
        current = party('p1', members: ['me'], chat: 'pc1');
        server.push('party.member_left', {
          'partyId': 'p1',
          'userId': 'ece',
          'reason': 'left',
          'leaderId': 'me',
        });
        await until(() => hub.parties.party?.members.length == 1);
        // Seen in this party: still named.
        expect(chat().author('ece')?.displayName, 'ECE');
        expect(chat().author('zed'), isNull);
      },
    );

    test('leaving the party ends the chat here', () async {
      await until(() => chat().loaded);
      server.push('party.ended', {'partyId': 'p1'});
      await until(() => chat().id == null);
      expect(chat().thread, isEmpty);
      expect(chat().loaded, isFalse);
      // A late message for the chat that ended does not reach the inbox.
      final lists = asked('GET', '/api/v1/me/conversations');
      server.push('message.created', said(7));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(asked('GET', '/api/v1/me/conversations'), lists);
    });
  });

  group('no party chat', () {
    late FakeServer server;
    late TogetherHub hub;

    setUp(() async {
      HttpOverrides.global = null;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/party') => (
          200,
          {'party': party('p1'), 'invites': <Object>[]},
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    test('an older server sends none: nothing is asked for', () async {
      await until(() => hub.parties.loaded);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(hub.partyChat.id, isNull);
      expect(
        server.requests.where((r) => r.$2.startsWith('/api/v1/conversations/')),
        isEmpty,
      );
    });
  });
}
