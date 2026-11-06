// The cryptography is pure Dart: slow in a debug test run on a busy machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/together/e2ee.dart';
import 'package:anyps5_remote/together/sealed_media.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

/// Sealed media: only ciphertext goes up (a clip's poster sealed apart), and what comes down is
/// opened on the phone with the keys from its message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sealed clip goes up as ciphertext, its poster after it', () async {
    HttpOverrides.global = null;
    final server = FakeServer();
    server.answer = (method, path, body) => switch (path) {
      '/api/v1/me/media/sealed?kind=clip' => (
        201,
        {
          'media': {'id': 'm-1', 'kind': 'clip', 'url': 'u', 'sealed': true},
        },
      ),
      _ => (200, {'ok': true}),
    };
    await server.start();
    final account = await server.account();
    final clip = await sealFile(utf8.encode('an mp4'), FilePart.file);
    final poster = await sealFile(utf8.encode('a jpeg'), FilePart.poster);
    final media = await uploadSealedMedia(
      account,
      MediaKind.clip,
      clip.ciphertext,
      poster: poster.ciphertext,
    );
    expect(media.id, 'm-1');
    expect(media.sealed, isTrue);
    expect(server.uploads.map((u) => (u.$1, u.$2, u.$4)), [
      ('POST', '/api/v1/me/media/sealed?kind=clip', 'application/octet-stream'),
      ('PUT', '/api/v1/me/media/m-1/poster', 'application/octet-stream'),
    ]);
    expect(server.uploads[0].$3, clip.ciphertext);
    expect(server.uploads[1].$3, poster.ciphertext);
    await server.stop();
  });

  group('downloading', () {
    late HttpServer files;
    final served = <String, List<int>>{};
    var asked = 0;

    setUp(() async {
      HttpOverrides.global = null;
      asked = 0;
      files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      files.listen((request) async {
        asked++;
        final bytes = served[request.uri.path];
        request.response.statusCode = bytes == null ? 404 : 200;
        if (bytes != null) request.response.add(bytes);
        await request.response.close();
      });
    });

    tearDown(() => files.close(force: true));

    String url(String path) => 'http://127.0.0.1:${files.port}$path';

    Future<Attachment> clip() async {
      final file = await sealFile(utf8.encode('the clip'), FilePart.file);
      final poster = await sealFile(utf8.encode('the poster'), FilePart.poster);
      served['/clip'] = file.ciphertext;
      served['/poster'] = poster.ciphertext;
      return Attachment(
        id: 'm-1',
        kind: MediaKind.clip,
        url: url('/clip'),
        poster: url('/poster'),
        sealed: true,
      ).opened(
        SealedAttachment(
          mediaId: 'm-1',
          kind: 'clip',
          type: 'video/mp4',
          size: 8,
          key: file.key,
          nonce: file.nonce,
          poster: SealedFileKey(
            key: poster.key,
            nonce: poster.nonce,
            type: 'image/jpeg',
          ),
        ),
      );
    }

    test('opens the file and the poster with their keys, once each', () async {
      final media = SealedMedia();
      final attachment = await clip();
      expect(utf8.decode(await media.open(attachment)), 'the clip');
      expect(
        utf8.decode(await media.open(attachment, part: FilePart.poster)),
        'the poster',
      );
      await media.open(attachment);
      expect(asked, 2);
    });

    test('a changed byte or the wrong key does not open', () async {
      final media = SealedMedia();
      final attachment = await clip();
      final bytes = Uint8List.fromList(served['/clip']!);
      bytes[3] ^= 1;
      served['/clip'] = bytes;
      expect(media.open(attachment), throwsA(isA<E2eeError>()));
    });

    test('a clip opens into a temporary file for the player', () async {
      final file = await SealedMedia().temporaryFile(await clip());
      expect(file.path, endsWith('.mp4'));
      expect(await file.readAsString(), 'the clip');
      await file.parent.delete(recursive: true);
    });

    test('media without its keys is not fetched', () async {
      final media = SealedMedia();
      expect(
        media.open(
          Attachment(
            id: 'x',
            kind: MediaKind.image,
            url: url('/clip'),
            sealed: true,
          ),
        ),
        throwsA(isA<E2eeError>()),
      );
      expect(asked, 0);
    });
  });
}
