import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/media_strings.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_socket.dart';
import 'package:anyps5_remote/ui/messages_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// A message as the API sends it, with media when [attachments] is given.
Map<String, dynamic> mediaMessage(
  int seq, {
  String kind = 'image',
  String? caption,
  List<Map<String, dynamic>> attachments = const [],
  String author = 'ece',
}) => {
  'id': '0190a000-0000-7000-8000-${seq.toString().padLeft(12, '0')}',
  'conversationId': 'c1',
  'seq': seq,
  'authorId': author,
  'kind': kind,
  'text': caption ?? '[photo]',
  'caption': caption,
  'attachments': attachments,
  'replyTo': null,
  'editedAt': null,
  'deletedAt': null,
  'createdAt': DateTime.utc(2026, 10, 25, 12, seq).toIso8601String(),
};

Map<String, dynamic> media(
  String id, {
  String kind = 'image',
  int? durationMs,
  String? poster,
}) => {
  'id': id,
  'kind': kind,
  'contentType': kind == 'image'
      ? 'image/webp'
      : kind == 'clip'
      ? 'video/mp4'
      : 'audio/ogg',
  'size': 2048,
  'width': kind == 'voice' ? null : 1920,
  'height': kind == 'voice' ? null : 1080,
  'durationMs': durationMs,
  'url': 'https://files.test/$id',
  'thumb': kind == 'image' ? 'https://files.test/$id/thumb' : null,
  'poster': poster,
  'createdAt': DateTime.utc(2026, 10, 25).toIso8601String(),
};

/// The smallest PNG header: enough for the phone to call it a PNG.
final png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, //
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing', () {
    test('a text message from an older server parses as before', () {
      final message = ChatMessage.fromJson({
        'id': 'm1',
        'conversationId': 'c1',
        'seq': 1,
        'authorId': 'ece',
        'text': 'hi',
        'createdAt': '2026-10-25T12:00:00.000Z',
      });
      expect(message.kind, MediaKind.text);
      expect(message.attachments, isEmpty);
      expect(message.caption, isNull);
      expect(message.text, 'hi');
    });

    test('a photo, a clip and a voice note come with their attachment', () {
      final photo = ChatMessage.fromJson(
        mediaMessage(1, caption: 'look', attachments: [media('p1')]),
      );
      expect(photo.kind, MediaKind.image);
      expect(photo.caption, 'look');
      final attachment = photo.attachments.single;
      expect(attachment.kind, MediaKind.image);
      expect(attachment.url, 'https://files.test/p1');
      expect(attachment.thumb, 'https://files.test/p1/thumb');
      expect(attachment.width, 1920);
      expect(attachment.aspect, closeTo(16 / 9, 0.001));
      expect(attachment.shown, isTrue);

      final clip = ChatMessage.fromJson(
        mediaMessage(
          2,
          kind: 'clip',
          attachments: [
            media(
              'k1',
              kind: 'clip',
              durationMs: 30000,
              poster: 'https://p.test',
            ),
          ],
        ),
      );
      expect(clip.kind, MediaKind.clip);
      expect(clip.attachments.single.poster, 'https://p.test');
      expect(clip.attachments.single.duration, const Duration(seconds: 30));

      final voice = ChatMessage.fromJson(
        mediaMessage(
          3,
          kind: 'voice',
          attachments: [media('v1', kind: 'voice', durationMs: 4200)],
        ),
      );
      expect(voice.kind, MediaKind.voice);
      expect(voice.attachments.single.contentType, 'audio/ogg');
    });

    test('removed and blocked attachments say so', () {
      final message = ChatMessage.fromJson(
        mediaMessage(
          1,
          attachments: [
            {'id': 'a', 'kind': 'image', 'removed': true},
            {'id': 'b', 'kind': 'clip', 'blocked': true},
            {'id': 'c', 'kind': 'hologram'},
          ],
        ),
      );
      expect(message.attachments[0].removed, isTrue);
      expect(message.attachments[0].shown, isFalse);
      expect(message.attachments[1].blocked, isTrue);
      expect(message.attachments[1].kind, MediaKind.clip);
      expect(
        message.attachments[2].kind,
        MediaKind.image,
        reason: 'an unknown kind stays a picture rather than breaking the list',
      );
    });

    test('the list shows what a message holds, not the stand-in', () {
      const en = Strings.english;
      const tr = Strings.turkish;
      final photo = ChatMessage.fromJson(
        mediaMessage(1, attachments: [media('p1')]),
      );
      final captioned = ChatMessage.fromJson(
        mediaMessage(2, caption: 'GG', attachments: [media('p1')]),
      );
      final voice = ChatMessage.fromJson(
        mediaMessage(
          3,
          kind: 'voice',
          attachments: [media('v', kind: 'voice')],
        ),
      );
      expect(en.messagePreview(photo), 'Photo');
      expect(en.messagePreview(captioned), 'Photo: GG');
      expect(tr.messagePreview(voice), 'Sesli mesaj');
      final text = ChatMessage.fromJson({
        'id': 'm',
        'conversationId': 'c1',
        'seq': 4,
        'authorId': 'ece',
        'text': 'hello',
        'createdAt': '2026-10-25T12:00:00.000Z',
      });
      expect(en.messagePreview(text), 'hello');
    });

    test('storage limits and usage parse; off is off', () {
      expect(StorageInfo.fromJson({'enabled': false}).enabled, isFalse);
      final on = StorageInfo.fromJson({
        'enabled': true,
        'quota': 104857600,
        'saveMax': 52428800,
        'saveVersions': 3,
        'partSize': 4194304,
        'media': {'image': 10485760, 'clip': 26214400, 'voice': 1048576},
        'galleryMax': 12,
      });
      expect(on.enabled, isTrue);
      expect(on.quota, 104857600);
      expect(on.imageMax, 10485760);
      final usage = StorageUsage.fromJson({
        'used': 52428800,
        'limit': 104857600,
        'saves': 41943040,
        'media': 10485760,
      });
      expect(usage.fraction, 0.5);
      expect(Strings.english.storageUsed(usage), '50 MB of 100 MB');
      expect(Strings.turkish.storageUsed(usage), '50 MB / 100 MB');
    });
  });

  group('with the server', () {
    late FakeServer server;
    late TogetherAccount account;
    late Messages messages;
    late TogetherSocket socket;
    var storageAsked = 0;
    (int, Object?)? Function(String method, String path)? override;

    setUp(() async {
      HttpOverrides.global = null;
      storageAsked = 0;
      override = null;
      server = FakeServer();
      server.answer = (method, path, body) {
        final custom = override?.call(method, path);
        if (custom != null) return custom;
        switch ((method, path)) {
          case ('GET', '/api/v1/storage'):
            storageAsked++;
            return (200, {'enabled': true, 'quota': 104857600});
          case ('GET', '/api/v1/me/storage'):
            return (
              200,
              {
                'enabled': true,
                'usage': {
                  'used': 3145728,
                  'limit': 104857600,
                  'saves': 2097152,
                  'media': 1048576,
                },
                'saves': [],
                'media': [],
              },
            );
          case ('POST', '/api/v1/me/media?kind=image'):
            return (
              201,
              {
                'media': media('0190a000-0000-7000-8000-00000000abcd'),
                'usage': {
                  'used': 1,
                  'limit': 104857600,
                  'saves': 0,
                  'media': 1,
                },
              },
            );
          case ('POST', '/api/v1/conversations/c1/messages'):
            return (
              201,
              mediaMessage(
                9,
                author: 'me',
                caption: body?['text'] as String?,
                attachments: [media('0190a000-0000-7000-8000-00000000abcd')],
              )..['id'] = body?['clientId'],
            );
        }
        return (404, {'code': 'not_found', 'status': 404, 'title': 'no'});
      };
      await server.start();
      account = await server.account();
      socket = TogetherSocket(account: account);
      messages = Messages(account: account, socket: socket);
      messages.openId = 'c1';
    });

    tearDown(() async {
      messages.dispose();
      socket.dispose();
      await server.stop();
    });

    test('whether storage is on is asked once, without a token', () async {
      expect(await account.storageEnabled(), isTrue);
      expect(await account.storageEnabled(), isTrue);
      expect(storageAsked, 1);
      expect(account.storage?.enabled, isTrue);
    });

    test('a server that keeps no files hides storage', () async {
      override = (method, path) =>
          path == '/api/v1/storage' ? (200, {'enabled': false}) : null;
      expect(await account.storageEnabled(), isFalse);
    });

    test('the usage comes from me/storage', () async {
      final usage = await account.storageUsage();
      expect(usage.used, 3145728);
      expect(usage.saves, 2097152);
      expect(usage.media, 1048576);
    });

    test('a photo goes up as its bytes, then in a message', () async {
      await messages.sendPhoto(png, caption: 'look');
      final upload = server.uploads.single;
      expect(upload.$1, 'POST');
      expect(upload.$2, '/api/v1/me/media?kind=image');
      expect(upload.$3, png);
      expect(upload.$4, 'image/png');
      final sent = server.requests.last;
      expect(sent.$2, '/api/v1/conversations/c1/messages');
      expect(sent.$3?['text'], 'look');
      expect(sent.$3?['attachments'], [
        {'mediaId': '0190a000-0000-7000-8000-00000000abcd'},
      ]);
      final shown = messages.thread.single;
      expect(shown.pending, isFalse);
      expect(shown.failed, isFalse);
      expect(shown.kind, MediaKind.image);
      expect(shown.id, sent.$3?['clientId']);
      expect(shown.attachments.single.url, contains('abcd'));
    });

    test('a full storage refuses the photo for good', () async {
      override = (method, path) => path == '/api/v1/me/media?kind=image'
          ? (
              413,
              {
                'status': 413,
                'code': 'quota_exceeded',
                'title': 'full',
                'used': 104857600,
                'limit': 104857600,
                'needed': 12,
              },
            )
          : null;
      await messages.sendPhoto(png);
      final shown = messages.thread.single;
      expect(shown.failed, isTrue);
      expect(shown.problem?.code, 'quota_exceeded');
      expect(shown.refused, isTrue);
      expect(
        Strings.english.mediaProblem(shown.problem!),
        contains('storage is full'),
      );
      expect(server.requests.where((r) => r.$2.contains('/messages')), isEmpty);
    });

    test('a photo that went up is not sent twice on a retry', () async {
      var fail = true;
      override = (method, path) =>
          path == '/api/v1/conversations/c1/messages' && fail
          ? (500, {'status': 500, 'code': 'internal', 'title': 'oops'})
          : null;
      await messages.sendPhoto(png);
      expect(messages.thread.single.failed, isTrue);
      expect(messages.thread.single.refused, isFalse);
      fail = false;
      await messages.retry(messages.thread.single);
      expect(server.uploads, hasLength(1), reason: 'the media was kept');
      expect(messages.thread.single.failed, isFalse);
      expect(messages.thread.single.attachments, isNotEmpty);
    });
  });

  testWidgets('bubbles: removed, blocked, a voice note and a clip', (
    tester,
  ) async {
    final thread = [
      ChatMessage.fromJson(
        mediaMessage(
          1,
          attachments: [
            {'id': 'a', 'kind': 'image', 'removed': true},
          ],
        ),
      ),
      ChatMessage.fromJson(
        mediaMessage(
          2,
          kind: 'clip',
          attachments: [
            {'id': 'b', 'kind': 'clip', 'blocked': true},
          ],
        ),
      ),
      ChatMessage.fromJson(
        mediaMessage(
          3,
          kind: 'voice',
          attachments: [media('v', kind: 'voice', durationMs: 65000)],
        ),
      ),
      ChatMessage.fromJson(
        mediaMessage(
          4,
          kind: 'clip',
          attachments: [media('k', kind: 'clip', durationMs: 12000)],
        ),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ListView(
            children: [
              for (final message in thread)
                MessageMedia(message: message, mine: false),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Removed'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));
    expect(find.text('0:12'), findsOneWidget);
  });
}
