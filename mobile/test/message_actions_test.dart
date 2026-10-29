import 'dart:io';

import 'package:anyps5_remote/chat_strings.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/messages_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';
import 'support/scripted_hub.dart';

/// A message as the API sends it now: its edits, reactions and the one it answers.
Map<String, dynamic> message(
  String conversation,
  int seq, {
  String author = 'ece',
  String? id,
  String? text = 'hi',
  int? replyTo,
  int editCount = 0,
  List<Map<String, dynamic>> reactions = const [],
  DateTime? createdAt,
  bool deleted = false,
}) => {
  'id': id ?? '0190a000-0000-7000-8000-${seq.toString().padLeft(12, '0')}',
  'conversationId': conversation,
  'seq': seq,
  'authorId': author,
  'text': deleted ? null : text,
  'replyTo': replyTo,
  'editedAt': editCount > 0 ? '2026-10-24T12:30:00Z' : null,
  'editCount': editCount,
  'reactions': reactions,
  'deletedAt': deleted ? '2026-10-24T12:40:00Z' : null,
  'createdAt': (createdAt ?? DateTime.utc(2026, 10, 24, 12, seq))
      .toIso8601String(),
};

Map<String, dynamic> tally(String name, List<String> who) => {
  'reaction': name,
  'count': who.length,
  'userIds': who,
};

Map<String, dynamic> receipt(String user, {int? read, int? delivered}) => {
  'userId': user,
  'readSeq': read,
  'deliveredSeq': delivered,
};

Map<String, dynamic> conversation(
  String id,
  List<String> with_, {
  int lastSeq = 3,
  int readSeq = 1,
  int? unread,
  bool group = false,
  bool pinned = false,
  bool muted = false,
  List<Map<String, dynamic>>? receipts,
  int minute = 0,
}) => {
  'id': id,
  'kind': group ? 'group' : 'direct',
  'title': group ? 'Squad' : null,
  'createdBy': 'me',
  'members': [card('me'), for (final user in with_) card(user)],
  'lastSeq': lastSeq,
  'readSeq': readSeq,
  'unread': unread ?? lastSeq - readSeq,
  'pinned': pinned,
  'muted': muted,
  'receipts':
      receipts ??
      [for (final user in with_) receipt(user, read: 0, delivered: 0)],
  'lastMessage': message(id, lastSeq, author: with_.first),
  'updatedAt': DateTime.utc(
    2026,
    10,
    24,
    12,
    minute == 0 ? lastSeq : minute,
  ).toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decoding', () {
    test(
      'a message brings its edits, reactions in their order and its reply',
      () {
        final decoded = ChatMessage.fromJson(
          message(
            'c1',
            4,
            replyTo: 2,
            editCount: 3,
            reactions: [
              tally('like', ['ece', 'me']),
              tally('sparkle', ['ece']),
              tally('gg', ['ali']),
            ],
          ),
        );
        expect(decoded.replyTo, 2);
        expect(decoded.editCount, 3);
        expect(decoded.edited, isTrue);
        // A reaction this phone does not know is left out.
        expect(decoded.reactions.map((r) => r.reaction), [
          MessageReaction.like,
          MessageReaction.gg,
        ]);
        expect(decoded.reactions.first.count, 2);
        expect(decoded.reacted(MessageReaction.like, 'me'), isTrue);
        expect(decoded.reacted(MessageReaction.gg, 'me'), isFalse);
      },
    );

    test('an older server without the new fields still decodes', () {
      final decoded = ChatMessage.fromJson({
        'id': 'x',
        'conversationId': 'c1',
        'seq': 1,
        'authorId': 'ece',
        'text': 'hi',
        'createdAt': '2026-10-24T12:00:00Z',
      });
      expect(decoded.replyTo, isNull);
      expect(decoded.editCount, 0);
      expect(decoded.reactions, isEmpty);
      final old = Conversation.fromJson({
        'id': 'c1',
        'kind': 'direct',
        'members': [card('me'), card('ece')],
        'lastSeq': 7,
        'readSeq': 3,
        'updatedAt': '2026-10-24T12:00:00Z',
      });
      expect(old.pinned, isFalse);
      expect(old.muted, isFalse);
      expect(old.receipts, isNull);
      // No count from the server: worked out from the marks.
      expect(old.unread, 4);
    });

    test('an unsent message keeps no reactions', () {
      final decoded = ChatMessage.fromJson(
        message(
          'c1',
          2,
          deleted: true,
          reactions: [
            tally('love', ['ece']),
          ],
        ),
      );
      expect(decoded.deleted, isTrue);
      expect(decoded.reactions, isEmpty);
    });

    test('a conversation brings pin, mute, receipts and the server unread', () {
      final decoded = Conversation.fromJson(
        conversation(
          'c1',
          ['ece'],
          lastSeq: 9,
          readSeq: 2,
          unread: 3,
          pinned: true,
          muted: true,
          receipts: [receipt('ece', read: 5, delivered: 8)],
        ),
      );
      expect(decoded.pinned, isTrue);
      expect(decoded.muted, isTrue);
      // The server counts others' messages that were not unsent; its number is kept.
      expect(decoded.unread, 3);
      expect(decoded.receipts!.single.userId, 'ece');
      expect(decoded.receipts!.single.readSeq, 5);
      expect(decoded.receipts!.single.deliveredSeq, 8);
    });
  });

  group('receipts', () {
    ChatMessage mine(int seq) =>
        ChatMessage.fromJson(message('c1', seq, author: 'me'));

    test('a direct chat: sent, delivered, read', () {
      Conversation direct({int? read, int? delivered}) => Conversation.fromJson(
        conversation(
          'c1',
          ['ece'],
          receipts: [receipt('ece', read: read, delivered: delivered)],
        ),
      );
      expect(
        receiptOf(direct(read: 2, delivered: 3), mine(4), 'me')!.kind,
        ReceiptKind.sent,
      );
      expect(
        receiptOf(direct(read: 2, delivered: 4), mine(4), 'me')!.kind,
        ReceiptKind.delivered,
      );
      expect(
        receiptOf(direct(read: 4, delivered: 4), mine(4), 'me')!.kind,
        ReceiptKind.read,
      );
      // Read receipts not shared: no read mark, delivered still shows.
      expect(
        receiptOf(direct(read: null, delivered: 9), mine(4), 'me')!.kind,
        ReceiptKind.delivered,
      );
    });

    test('a group: seen by some, seen by everyone', () {
      Conversation squad(int? ali, int? ece) => Conversation.fromJson(
        conversation(
          'g1',
          ['ali', 'ece'],
          group: true,
          receipts: [
            receipt('ali', read: ali),
            receipt('ece', read: ece),
          ],
        ),
      );
      final some = receiptOf(squad(4, 2), mine(4), 'me')!;
      expect(some.kind, ReceiptKind.seen);
      expect(some.count, 1);
      expect(some.everyone, isFalse);
      final all = receiptOf(squad(6, 4), mine(4), 'me')!;
      expect(all.count, 2);
      expect(all.everyone, isTrue);
      final none = receiptOf(squad(null, 1), mine(4), 'me')!;
      expect(none.count, 0);
      expect(none.everyone, isFalse);
    });

    test('nothing for their message, a removed one or an older server', () {
      final direct = Conversation.fromJson(conversation('c1', ['ece']));
      expect(
        receiptOf(direct, ChatMessage.fromJson(message('c1', 3)), 'me'),
        isNull,
      );
      expect(
        receiptOf(
          direct,
          ChatMessage.fromJson(message('c1', 3, author: 'me', deleted: true)),
          'me',
        ),
        isNull,
      );
      final old = Conversation.fromJson(
        conversation('c1', ['ece'])..remove('receipts'),
      );
      expect(receiptOf(old, mine(3), 'me'), isNull);
    });

    test('the texts in English and Turkish', () {
      const en = Strings.english;
      const tr = Strings.turkish;
      expect(en.receipt(const Receipt(ReceiptKind.read)), 'Read');
      expect(tr.receipt(const Receipt(ReceiptKind.delivered)), 'İletildi');
      expect(en.receipt(const Receipt(ReceiptKind.sent)), 'Sent');
      expect(
        en.receipt(const Receipt(ReceiptKind.seen, count: 2)),
        'Seen by 2',
      );
      expect(
        tr.receipt(const Receipt(ReceiptKind.seen, count: 2)),
        '2 kişi gördü',
      );
      expect(
        en.receipt(const Receipt(ReceiptKind.seen, count: 3, everyone: true)),
        'Seen by everyone',
      );
      expect(en.messagesDeleted, 'Message removed');
      expect(tr.messagesDeleted, 'Mesaj kaldırıldı');
      expect(en.pinFull(maxPinned), 'You can pin up to 5 conversations.');
      expect(tr.replyingTo('Ece'), 'Ece kişisine yanıt');
      expect(MessageReaction.values.map(tr.reactionLabel), [
        'Beğen',
        'Sevgi',
        'Haha',
        'Vay',
        'Üzgün',
        'Ateş',
        'GG',
      ]);
      expect(MessageReaction.values.map((r) => r.glyph), [
        '👍',
        '❤️',
        '😂',
        '😮',
        '😢',
        '🔥',
        'GG',
      ]);
    });
  });

  group('who may edit', () {
    final now = DateTime.utc(2026, 10, 24, 12, 10);
    ChatMessage at(
      int minutesAgo, {
      String author = 'me',
      int edits = 0,
      bool deleted = false,
    }) => ChatMessage.fromJson(
      message(
        'c1',
        3,
        author: author,
        editCount: edits,
        deleted: deleted,
        createdAt: now.subtract(Duration(minutes: minutesAgo)),
      ),
    );

    test('their own text, within 15 minutes and under 20 edits', () {
      expect(at(14).canEdit('me', now: now), isTrue);
      expect(at(15).canEdit('me', now: now), isFalse);
      expect(at(1, edits: 19).canEdit('me', now: now), isTrue);
      expect(at(1, edits: 20).canEdit('me', now: now), isFalse);
      expect(at(1, author: 'ece').canEdit('me', now: now), isFalse);
      expect(at(1, deleted: true).canEdit('me', now: now), isFalse);
    });

    test('a photo only when it has a caption', () {
      Map<String, dynamic> photo({String? caption}) => {
        ...message(
          'c1',
          3,
          author: 'me',
          createdAt: now.subtract(const Duration(minutes: 1)),
          text: caption ?? '[photo]',
        ),
        'kind': 'image',
        'caption': caption,
        'attachments': [
          {'id': 'm1', 'kind': 'image', 'url': 'https://x/m1'},
        ],
      };
      expect(ChatMessage.fromJson(photo()).canEdit('me', now: now), isFalse);
      expect(
        ChatMessage.fromJson(photo(caption: 'gg')).canEdit('me', now: now),
        isTrue,
      );
    });
  });

  group('calls and live events', () {
    late FakeServer server;
    late TogetherHub hub;
    Object? pinProblem;
    Object? editProblem;

    setUp(() async {
      HttpOverrides.global = null;
      pinProblem = null;
      editProblem = null;
      server = FakeServer();
      server.answer = (method, path, body) {
        if (path == '/api/v1/me/conversations') {
          return (
            200,
            {
              'conversations': [
                conversation(
                  'p1',
                  ['zed'],
                  lastSeq: 1,
                  readSeq: 1,
                  pinned: true,
                  minute: 1,
                ),
                conversation(
                  'c1',
                  ['ece'],
                  receipts: [receipt('ece', read: 2, delivered: 2)],
                ),
                conversation(
                  'g1',
                  ['ali', 'ece'],
                  group: true,
                  lastSeq: 5,
                  readSeq: 5,
                  minute: 2,
                  receipts: [receipt('ali', read: 3), receipt('ece', read: 1)],
                ),
              ],
            },
          );
        }
        if (path == '/api/v1/me/conversations/unread') {
          return (200, {'conversations': 1, 'messages': 2});
        }
        // Nothing came while the socket was away.
        if (path.contains('&after=')) {
          return (200, {'messages': <Object>[], 'more': false});
        }
        if (path.startsWith('/api/v1/conversations/c1/messages?')) {
          return (
            200,
            {
              'messages': [
                message('c1', 2),
                message(
                  'c1',
                  3,
                  author: 'me',
                  reactions: [
                    tally('fire', ['ece']),
                  ],
                ),
              ],
              'more': false,
            },
          );
        }
        if (method == 'POST' && path == '/api/v1/conversations/c1/messages') {
          return (
            201,
            message(
              'c1',
              4,
              author: 'me',
              id: body!['clientId'] as String,
              text: body['text'] as String?,
              replyTo: body['replyTo'] as int?,
            ),
          );
        }
        if (method == 'PATCH' &&
            path == '/api/v1/conversations/c1/messages/3') {
          if (editProblem != null) {
            return (
              409,
              {'code': 'edit_limit', 'status': 409, 'title': 'limit'},
            );
          }
          return (
            200,
            message(
              'c1',
              3,
              author: 'me',
              text: body!['text'] as String,
              editCount: 1,
            ),
          );
        }
        if (path.startsWith('/api/v1/conversations/c1/messages/3/reactions/')) {
          final name = path.split('/').last;
          return (
            200,
            {
              'conversationId': 'c1',
              'seq': 3,
              // The fixed order: love comes before fire.
              'reactions': [
                if (method == 'PUT') tally(name, ['me']),
                tally('fire', ['ece']),
              ],
            },
          );
        }
        if (method == 'PUT' && path == '/api/v1/conversations/c1/pin') {
          if (pinProblem != null) {
            return (409, {'code': 'full', 'status': 409, 'title': 'full'});
          }
          return (
            200,
            conversation(
              'c1',
              ['ece'],
              pinned: body!['pinned'] as bool,
              receipts: [receipt('ece', read: 2, delivered: 2)],
            ),
          );
        }
        if (method == 'PUT' && path == '/api/v1/conversations/c1/mute') {
          return (
            200,
            conversation('c1', ['ece'], muted: body!['muted'] as bool),
          );
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
    Conversation c(String id) => messages().byId(id)!;
    List<(String, String, Map<String, dynamic>?)> calls(String path) => [
      for (final request in server.requests)
        if (request.$2 == '/api/v1/$path') request,
    ];

    test('a reply is sent with the seq it answers', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      await messages().send('same', replyTo: messages().thread.first);
      final sent = calls('conversations/c1/messages').last;
      expect(sent.$3!['replyTo'], 2);
      expect(sent.$3!['text'], 'same');
      expect(messages().thread.last.replyTo, 2);
    });

    test('an edit is sent and the thread takes what came back', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      await messages().edit(messages().thread.last, '  fixed  ');
      final sent = calls('conversations/c1/messages/3').single;
      expect(sent.$1, 'PATCH');
      expect(sent.$3, {'text': 'fixed'});
      expect(messages().thread.last.text, 'fixed');
      expect(messages().thread.last.editCount, 1);
      editProblem = true;
      await expectLater(
        messages().edit(messages().thread.last, 'again'),
        throwsA(
          isA<TogetherProblem>().having((p) => p.code, 'code', 'edit_limit'),
        ),
      );
      expect(messages().thread.last.text, 'fixed');
    });

    test('unsending leaves a removed message without reactions', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      await messages().unsend(messages().thread.last);
      final sent = calls('conversations/c1/messages/3').single;
      expect(sent.$1, 'DELETE');
      expect(messages().thread.last.deleted, isTrue);
      expect(messages().thread.last.reactions, isEmpty);
      expect(messages().thread.last.text, isNull);
    });

    test('a reaction is added with PUT and taken back with DELETE', () async {
      await until(() => messages().loaded);
      await messages().show('c1');
      await messages().react(messages().thread.last, MessageReaction.love);
      final love = calls('conversations/c1/messages/3/reactions/love');
      expect(love.single.$1, 'PUT');
      expect(messages().thread.last.reactions.map((r) => r.reaction), [
        MessageReaction.love,
        MessageReaction.fire,
      ]);
      expect(
        messages().thread.last.reacted(MessageReaction.love, 'me'),
        isTrue,
      );
      await messages().react(messages().thread.last, MessageReaction.love);
      expect(
        calls('conversations/c1/messages/3/reactions/love').last.$1,
        'DELETE',
      );
      expect(
        messages().thread.last.reacted(MessageReaction.love, 'me'),
        isFalse,
      );
      expect(
        messages().thread.last.reactions.single.reaction,
        MessageReaction.fire,
      );
    });

    test('pinning sends the flag and keeps pinned ones first', () async {
      await until(() => messages().loaded);
      expect(messages().conversations.map((c) => c.id), ['p1', 'c1', 'g1']);
      await messages().pin('c1', true);
      expect(calls('conversations/c1/pin').single.$3, {'pinned': true});
      expect(c('c1').pinned, isTrue);
      // Both pinned: the newer first, then the rest.
      expect(messages().conversations.map((c) => c.id), ['c1', 'p1', 'g1']);
      pinProblem = true;
      await expectLater(
        messages().pin('c1', true),
        throwsA(isA<TogetherProblem>().having((p) => p.code, 'code', 'full')),
      );
      expect(c('c1').pinned, isTrue);
    });

    test(
      'a live message in an unpinned conversation stays under the pinned',
      () async {
        await until(() => messages().loaded);
        server.push('message.created', message('g1', 6, author: 'ali'));
        await until(() => c('g1').lastSeq == 6);
        expect(messages().conversations.map((c) => c.id), ['p1', 'g1', 'c1']);
        expect(c('g1').unread, 1);
      },
    );

    test('muting sends the flag', () async {
      await until(() => messages().loaded);
      await messages().mute('c1', true);
      expect(calls('conversations/c1/mute').single.$3, {'muted': true});
      expect(c('c1').muted, isTrue);
    });

    test(
      'message.reactions replaces them in the thread and the list',
      () async {
        await until(() => messages().loaded);
        await messages().show('c1');
        server.push('message.reactions', {
          'conversationId': 'c1',
          'seq': 3,
          'reactions': [
            tally('laugh', ['ece', 'zed']),
          ],
        });
        await until(
          () =>
              messages().thread.last.reactions.firstOrNull?.reaction ==
              MessageReaction.laugh,
        );
        expect(messages().thread.last.reactions.single.count, 2);
        expect(
          c('c1').lastMessage!.reactions.single.reaction,
          MessageReaction.laugh,
        );
      },
    );

    test(
      'conversation.delivered raises a member’s mark, never lowers it',
      () async {
        await until(() => messages().loaded);
        server.push('conversation.delivered', {
          'conversationId': 'c1',
          'userId': 'ece',
          'upToSeq': 3,
        });
        await until(() => c('c1').receipts!.single.deliveredSeq == 3);
        server.push('conversation.delivered', {
          'conversationId': 'c1',
          'userId': 'ece',
          'upToSeq': 1,
        });
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(c('c1').receipts!.single.deliveredSeq, 3);
        expect(c('c1').receipts!.single.readSeq, 2);
      },
    );

    test('conversation.read from someone else raises their receipt', () async {
      await until(() => messages().loaded);
      server.push('conversation.read', {
        'conversationId': 'c1',
        'userId': 'ece',
        'upToSeq': 3,
      });
      await until(() => c('c1').receipts!.single.readSeq == 3);
      // Read means delivered too.
      expect(c('c1').receipts!.single.deliveredSeq, 3);
      // My own read mark did not move.
      expect(c('c1').readSeq, 1);
      server.push('conversation.read', {
        'conversationId': 'g1',
        'userId': 'ece',
        'upToSeq': 5,
      });
      await until(
        () =>
            c('g1').receipts!.firstWhere((r) => r.userId == 'ece').readSeq == 5,
      );
      expect(
        receiptOf(
          c('g1'),
          ChatMessage.fromJson(message('g1', 3, author: 'me')),
          'me',
        )!.everyone,
        isTrue,
      );
    });

    test(
      'conversation.read from another of my devices takes its unread',
      () async {
        await until(() => messages().loaded && messages().unread == 2);
        server.push('conversation.read', {
          'conversationId': 'c1',
          'userId': 'me',
          'upToSeq': 2,
          'unread': 0,
        });
        await until(() => c('c1').readSeq == 2);
        expect(c('c1').unread, 0);
      },
    );

    test(
      'a removed unread message from someone else refetches the counts',
      () async {
        await until(() => messages().loaded && messages().unread == 2);
        final before = calls('me/conversations').length;
        server.push(
          'message.deleted',
          message('c1', 3, author: 'ece', deleted: true),
        );
        await until(() => calls('me/conversations').length > before);
        await until(() => messages().conversations.isNotEmpty);
        await until(() => calls('me/conversations/unread').length > 1);
        expect(calls('me/conversations/unread').length, greaterThan(1));
      },
    );

    test(
      'a direct message for a thread not open is acknowledged as delivered',
      () async {
        await until(() => messages().loaded);
        server.push('message.created', message('c1', 4, author: 'ece'));
        await until(() => calls('conversations/c1/delivered').isNotEmpty);
        expect(calls('conversations/c1/delivered').single.$3, {'upToSeq': 4});
        // A group, my own message, or the thread on screen: no acknowledgement.
        server.push('message.created', message('g1', 6, author: 'ali'));
        server.push('message.created', message('c1', 5, author: 'me'));
        await messages().show('c1');
        server.push('message.created', message('c1', 6, author: 'ece'));
        await until(() => messages().thread.any((m) => m.seq == 6));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(calls('conversations/g1/delivered'), isEmpty);
        expect(calls('conversations/c1/delivered'), hasLength(1));
      },
    );

    test('messages.settings carries my read receipts setting', () async {
      await until(() => messages().loaded);
      expect(messages().readReceipts, isNull);
      server.push('messages.settings', {'readReceipts': false});
      await until(() => messages().readReceipts == false);
    });
  });

  group('the pane', () {
    late TogetherHub hub;
    late ScriptedAccount account;

    final direct = conversation(
      'c1',
      ['ece'],
      lastSeq: 4,
      readSeq: 4,
      receipts: [receipt('ece', read: 3, delivered: 4)],
    );
    final squad = conversation(
      'g1',
      ['ali', 'ece'],
      group: true,
      lastSeq: 2,
      readSeq: 2,
      receipts: [receipt('ali', read: 2), receipt('ece', read: 1)],
    );

    setUp(() async {
      (hub, account) = await scriptedHub();
      hub.account.storage = StorageInfo.off;
      account.answer = (method, path, body) => switch ((method, path)) {
        ('PUT', 'conversations/c1/messages/2/reactions/like') => {
          'conversationId': 'c1',
          'seq': 2,
          'reactions': [
            tally('like', ['me']),
          ],
        },
        ('DELETE', 'conversations/c1/messages/2/reactions/like') => {
          'conversationId': 'c1',
          'seq': 2,
          'reactions': <Object>[],
        },
        ('POST', 'conversations/c1/messages') => message(
          'c1',
          5,
          author: 'me',
          id: body!['clientId'] as String,
          text: body['text'] as String?,
          replyTo: body['replyTo'] as int?,
        ),
        ('PATCH', 'conversations/c1/messages/4') => message(
          'c1',
          4,
          author: 'me',
          text: body!['text'] as String,
          editCount: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        ('PUT', 'conversations/c1/mute') => conversation(
          'c1',
          ['ece'],
          lastSeq: 4,
          readSeq: 4,
          muted: true,
        ),
        _ => <String, dynamic>{},
      };
    });

    tearDown(() => hub.dispose());

    void sideways(WidgetTester tester) {
      tester.view.physicalSize = const Size(2556, 1179);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> open(
      WidgetTester tester, {
      String id = 'c1',
      List<ChatMessage>? thread,
      Strings strings = Strings.english,
    }) async {
      sideways(tester);
      hub.messages
        ..conversations = [
          Conversation.fromJson(direct),
          Conversation.fromJson(squad),
        ]
        ..loaded = true
        ..openId = id
        ..thread =
            thread ??
            [
              ChatMessage.fromJson(message('c1', 1, text: 'first')),
              ChatMessage.fromJson(message('c1', 2, text: 'naber')),
              ChatMessage.fromJson(message('c1', 3, author: 'me', text: 'iyi')),
              ChatMessage.fromJson(
                message(
                  'c1',
                  4,
                  author: 'me',
                  text: 'sen',
                  createdAt: DateTime.now().toUtc(),
                ),
              ),
            ];
      await tester.pumpWidget(
        MaterialApp(
          home: Texts(
            strings: strings,
            child: Scaffold(body: MessagesPane(hub: hub)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a long press reacts; the chip shows and takes it back', (
      tester,
    ) async {
      await open(tester);
      await tester.longPress(find.text('naber'));
      await tester.pumpAndSettle();
      for (final name in MessageReaction.values) {
        expect(
          find.byTooltip(Strings.english.reactionLabel(name)),
          findsOneWidget,
        );
      }
      expect(find.text('Reply'), findsOneWidget);
      // Not mine: no edit, no unsend.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Unsend'), findsNothing);
      await tester.tap(find.byTooltip('Like'));
      await tester.pumpAndSettle();
      expect(account.calls.last.$1, 'PUT');
      expect(
        account.calls.last.$2,
        'conversations/c1/messages/2/reactions/like',
      );
      final chip = find.byKey(const ValueKey('reaction-2-like'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(account.calls.last.$1, 'DELETE');
      expect(find.byKey(const ValueKey('reaction-2-like')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the visible button opens the same actions', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Message actions').first);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('a reply shows the bar, goes with its seq and quotes it', (
      tester,
    ) async {
      await open(tester);
      await tester.longPress(find.text('naber'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to ECE'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'iyidir');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      final sent = account.calls.lastWhere((c) => c.$1 == 'POST').$3!;
      expect(sent['replyTo'], 2);
      expect(find.text('Replying to ECE'), findsNothing);
      // The sent message quotes the one it answers.
      expect(find.byKey(const ValueKey('quote-5')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('quote-5')),
          matching: find.text('naber'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a quote of a message not loaded or removed', (tester) async {
      await open(
        tester,
        thread: [
          ChatMessage.fromJson(message('c1', 8, deleted: true)),
          ChatMessage.fromJson(message('c1', 9, text: 'a', replyTo: 2)),
          ChatMessage.fromJson(message('c1', 10, text: 'b', replyTo: 8)),
        ],
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('quote-9')),
          matching: find.text('An earlier message'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('quote-10')),
          matching: find.text('Message removed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('my own message is edited and unsent', (tester) async {
      await open(tester);
      await tester.longPress(find.text('sen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'sen?');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(account.calls.last.$1, 'PATCH');
      expect(account.calls.last.$3, {'text': 'sen?'});
      expect(find.text('sen?'), findsOneWidget);
      await tester.longPress(find.text('sen?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unsend'));
      await tester.pumpAndSettle();
      expect(
        find.text("Unsend this message for everyone? It can't be undone."),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Unsend'));
      await tester.pumpAndSettle();
      expect(account.calls.last.$1, 'DELETE');
      expect(account.calls.last.$2, 'conversations/c1/messages/4');
      expect(find.text('Message removed'), findsWidgets);
    });

    testWidgets('an old message of mine cannot be edited, but can be unsent', (
      tester,
    ) async {
      await open(tester);
      await tester.longPress(find.text('iyi'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Unsend'), findsOneWidget);
    });

    testWidgets('the receipt shows under my newest message only', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
      hub.messages
        ..conversations = [
          Conversation.fromJson({
            ...direct,
            'receipts': [receipt('ece', read: 4, delivered: 4)],
          }),
        ]
        ..notifyListeners();
      await tester.pump();
      expect(find.text('Read'), findsOneWidget);
    });

    testWidgets('a group says how many saw it, in Turkish too', (tester) async {
      await open(
        tester,
        id: 'g1',
        thread: [
          ChatMessage.fromJson(message('g1', 1, author: 'ali')),
          ChatMessage.fromJson(message('g1', 2, author: 'me', text: 'gg')),
        ],
        strings: Strings.turkish,
      );
      expect(find.text('1 kişi gördü'), findsOneWidget);
    });

    testWidgets('a conversation is pinned and muted from its row', (
      tester,
    ) async {
      await open(tester);
      account.answer = (method, path, body) => switch ((method, path)) {
        ('PUT', 'conversations/g1/pin') => throw const TogetherProblem(
          409,
          'full',
          'full',
        ),
        ('PUT', 'conversations/c1/mute') => conversation(
          'c1',
          ['ece'],
          lastSeq: 4,
          readSeq: 4,
          muted: true,
          pinned: true,
        ),
        _ => null,
      };
      await tester.longPress(find.text('Squad'));
      await tester.pumpAndSettle();
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Mute notifications'), findsOneWidget);
      await tester.tap(find.text('Pin to top'));
      await tester.pumpAndSettle();
      expect(account.calls.last.$3, {'pinned': true});
      expect(find.text('You can pin up to 5 conversations.'), findsOneWidget);
      await tester.longPress(find.text('ECE').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      expect(account.calls.last.$2, 'conversations/c1/mute');
      expect(account.calls.last.$3, {'muted': true});
      expect(find.byTooltip('Muted'), findsOneWidget);
      expect(find.byTooltip('Pinned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the thread header offers the same conversation actions', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('Conversation options'));
      await tester.pumpAndSettle();
      expect(find.text('Pin to top'), findsOneWidget);
      expect(find.text('Mute notifications'), findsOneWidget);
    });
  });
}
