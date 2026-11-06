// The cryptography is pure Dart: slow in a debug test run on a busy machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/together/e2ee.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Protocol v1 against the shared vectors (packages/e2ee/test/e2ee-v1.json of AnyTogether, made
/// by noble and opened there with OpenSSL too): the same device IDs, signatures, ciphertexts and
/// safety number, byte for byte.
final vectors = jsonDecode(
  File('test/fixtures/e2ee-v1.json').readAsStringSync(),
) as Map<String, dynamic>;

Uint8List unhex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Map<String, dynamic> get devices => vectors['devices'] as Map<String, dynamic>;
List<Map<String, dynamic>> get messages =>
    (vectors['messages'] as List).cast<Map<String, dynamic>>();
String get conversationId => vectors['conversationId'] as String;
String get alice => (vectors['users'] as Map)['alice'] as String;
String get bob => (vectors['users'] as Map)['bob'] as String;

Future<DeviceSecrets> secretsOf(String name) {
  final d = devices[name] as Map<String, dynamic>;
  return DeviceSecrets.fromSeeds(
    unhex(d['signSeed'] as String),
    unhex(d['boxSecret'] as String),
  );
}

PublicDevice publicOf(String name) => PublicDevice.fromJson(
  (devices[name] as Map<String, dynamic>)['public'] as Map<String, dynamic>,
);

String ownerOf(String name) =>
    (devices[name] as Map<String, dynamic>)['userId'] as String;

List<PublicDevice> devicesOf(String user) => [
  for (final name in devices.keys)
    if (ownerOf(name) == user) publicOf(name),
];

Future<E2eeErrorCode?> codeOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on E2eeError catch (error) {
    return error.code;
  }
  return null;
}

String flip(String b64) {
  final bytes = base64.decode(b64);
  bytes[0] ^= 1;
  return base64.encode(bytes);
}

void main() {
  group('the RFC known answers', () {
    final rfc = vectors['rfc'] as Map<String, dynamic>;

    test('X25519 (RFC 7748)', () async {
      final x = rfc['x25519'] as Map<String, dynamic>;
      final pair = await X25519().newKeyPairFromSeed(
        unhex(x['aliceSecretHex'] as String),
      );
      expect(hexOf((await pair.extractPublicKey()).bytes), x['alicePublicHex']);
      final shared = await X25519().sharedSecretKey(
        keyPair: pair,
        remotePublicKey: SimplePublicKey(
          unhex(x['bobPublicHex'] as String),
          type: KeyPairType.x25519,
        ),
      );
      expect(hexOf(await shared.extractBytes()), x['sharedHex']);
    });

    test('Ed25519 (RFC 8032)', () async {
      final e = rfc['ed25519'] as Map<String, dynamic>;
      final pair = await Ed25519().newKeyPairFromSeed(
        unhex(e['seedHex'] as String),
      );
      expect(hexOf((await pair.extractPublicKey()).bytes), e['publicHex']);
      final signature = await Ed25519().sign(
        unhex(e['messageHex'] as String),
        keyPair: pair,
      );
      expect(hexOf(signature.bytes), e['signatureHex']);
    });

    test('ChaCha20-Poly1305 (RFC 8439)', () async {
      final c = rfc['chacha20poly1305'] as Map<String, dynamic>;
      final box = await Chacha20.poly1305Aead().encrypt(
        utf8.encode(c['plaintext'] as String),
        secretKey: SecretKey(unhex(c['keyHex'] as String)),
        nonce: unhex(c['nonceHex'] as String),
        aad: unhex(c['aadHex'] as String),
      );
      expect(hexOf(box.cipherText), c['ciphertextHex']);
      expect(hexOf(box.mac.bytes), c['tagHex']);
    });
  });

  group('the vector devices', () {
    test(
      'come out of their seeds with the same keys, IDs and signatures',
      () async {
        for (final name in devices.keys) {
          final secrets = await secretsOf(name);
          final expected = publicOf(name);
          final made = await publicDevice(secrets, ownerOf(name));
          expect(made.id, expected.id, reason: name);
          expect(secrets.deviceId, expected.id, reason: name);
          expect(made.signKey, expected.signKey, reason: name);
          expect(made.boxKey, expected.boxKey, reason: name);
          expect(made.sig, expected.sig, reason: name);
          expect(await verifyDevice(ownerOf(name), expected), isTrue);
        }
      },
    );

    test('verify for their own user only, and not once changed', () async {
      final phone = publicOf('alicePhone');
      expect(await verifyDevice(bob, phone), isFalse);
      expect(await verifyDevice(alice, phone.copyWith(id: '0' * 32)), isFalse);
      expect(
        await verifyDevice(
          alice,
          phone.copyWith(boxKey: publicOf('aliceMac').boxKey),
        ),
        isFalse,
      );
      expect(await verifyDevice(alice, phone.copyWith(sig: 'nope')), isFalse);
      expect(
        await verifyDevice(alice, phone.copyWith(sig: flip(phone.sig))),
        isFalse,
      );
    });
  });

  group('the vector messages', () {
    test('open on every vector device and verify', () async {
      for (final m in messages) {
        final sealed = Sealed.fromJson(m['sealed'] as Map<String, dynamic>);
        for (final name in devices.keys) {
          final me = await secretsOf(name);
          final payload = await open(
            sealed,
            conversationId: conversationId,
            messageId: m['messageId'] as String,
            authorId: m['authorId'] as String,
            me: me,
            authorDevices: devicesOf(m['authorId'] as String),
          );
          expect(
            payload.toJson(),
            jsonDecode(m['payload'] as String),
            reason: '${m['name']} on $name',
          );
          final key = await unwrapKey(
            sealed,
            MessageContext(
              conversationId: conversationId,
              messageId: m['messageId'] as String,
              senderUserId: m['authorId'] as String,
              senderDeviceId: sealed.device,
            ),
            me,
          );
          expect(base64.encode(key), (m['random'] as Map)['contentKey']);
        }
      }
    });

    test('the clip payload reads as an attachment with its poster', () async {
      final m = messages[1];
      final payload = await open(
        Sealed.fromJson(m['sealed'] as Map<String, dynamic>),
        conversationId: conversationId,
        messageId: m['messageId'] as String,
        authorId: m['authorId'] as String,
        me: await secretsOf('alicePhone'),
        authorDevices: devicesOf(bob),
      );
      final a = payload.attachment!;
      expect(payload.text, 'a caption');
      expect(a.mediaId, '0190f1a2-0000-7000-8000-00000000f11e');
      expect(a.kind, 'clip');
      expect(a.type, 'video/mp4');
      expect(a.size, 47);
      expect((a.width, a.height, a.durationMs), (1280, 720, 4200));
      expect(a.poster!.type, 'image/jpeg');
      expect(a.poster!.key, '9M4H9ahvPV4+4BII4nV5FBwXhxZ3JshB8kGUYKhJw00=');
    });

    test('seal again byte for byte with the same randomness', () async {
      final recipients = [for (final name in devices.keys) publicOf(name)];
      for (final m in messages) {
        final expected = m['sealed'] as Map<String, dynamic>;
        final random = m['random'] as Map<String, dynamic>;
        final sender = expected['device'] == publicOf('aliceMac').id
            ? await secretsOf('aliceMac')
            : await secretsOf('bobDesktop');
        final result = await seal(
          conversationId: conversationId,
          messageId: m['messageId'] as String,
          senderUserId: m['authorId'] as String,
          sender: sender,
          recipients: recipients,
          payload: const Payload(),
          payloadBytes: utf8.encode(m['payload'] as String),
          random: SealRandom(
            contentKey: base64.decode(random['contentKey'] as String),
            nonce: base64.decode(random['nonce'] as String),
            ephSecret: base64.decode(random['ephSecret'] as String),
          ),
        );
        final json = result.sealed.toJson();
        expect(json['eph'], expected['eph']);
        expect(json['nonce'], expected['nonce']);
        expect(json['body'], expected['body']);
        expect(json['keys'], expected['keys']);
        expect(json['sig'], expected['sig']);
        expect(json, expected);
        expect(base64.encode(result.contentKey), random['contentKey']);
      }
    });

    test('the files open, and seal again byte for byte', () async {
      for (final f in (vectors['files'] as List).cast<Map<String, dynamic>>()) {
        final part = FilePart.values.byName(f['part'] as String);
        final opened = await openFile(
          base64.decode(f['ciphertext'] as String),
          part,
          key: f['key'] as String,
          nonce: f['nonce'] as String,
        );
        expect(base64.encode(opened), f['plaintext']);
        final again = await sealFile(
          base64.decode(f['plaintext'] as String),
          part,
          key: base64.decode(f['key'] as String),
          nonce: base64.decode(f['nonce'] as String),
        );
        expect(base64.encode(again.ciphertext), f['ciphertext']);
        expect((again.key, again.nonce), (f['key'], f['nonce']));
      }
    });

    test('give the same safety number', () async {
      final s = vectors['safetyNumber'] as Map<String, dynamic>;
      final a = (userId: alice, signKeys: (s['alice'] as List).cast<String>());
      final b = (userId: bob, signKeys: (s['bob'] as List).cast<String>());
      expect(await safetyNumber(a, b), s['digits']);
      expect(await safetyNumber(b, a), s['digits']);
      expect(
        await safetyNumber((
          userId: alice,
          signKeys: a.signKeys.reversed.toList(),
        ), b),
        s['digits'],
      );
      expect(safetyGroups(s['digits'] as String), hasLength(12));
      expect(safetyGroups(s['digits'] as String).first, '44483');
      expect(await safetyNumber(a, (userId: bob, signKeys: [])), isNull);
    });
  });

  group('sealing on the phone', () {
    late DeviceSecrets mac;
    late DeviceSecrets phone;
    late DeviceSecrets desktop;
    late DeviceSecrets later;
    late PublicDevice macPublic;
    late PublicDevice phonePublic;
    late PublicDevice desktopPublic;
    late SealResult sent;
    const messageId = '0190f1a2-0000-7000-8000-000000000009';

    setUpAll(() async {
      mac = await DeviceSecrets.generate();
      phone = await DeviceSecrets.generate();
      desktop = await DeviceSecrets.generate();
      later = await DeviceSecrets.generate();
      macPublic = await publicDevice(mac, alice);
      phonePublic = await publicDevice(phone, alice);
      desktopPublic = await publicDevice(desktop, bob);
      sent = await seal(
        conversationId: conversationId,
        messageId: messageId,
        senderUserId: alice,
        sender: phone,
        recipients: [macPublic, phonePublic, desktopPublic],
        payload: const Payload(text: 'GG 🔥'),
      );
    });

    Future<Payload> openAs(
      DeviceSecrets me, {
      Sealed? sealed,
      String? conversation,
      String? id,
      String? author,
      List<PublicDevice>? authors,
    }) => open(
      sealed ?? sent.sealed,
      conversationId: conversation ?? conversationId,
      messageId: id ?? messageId,
      authorId: author ?? alice,
      me: me,
      authorDevices: authors ?? [macPublic, phonePublic],
    );

    test('a fresh device verifies, and its keys are new each time', () async {
      expect(await verifyDevice(alice, phonePublic), isTrue);
      expect(phone.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(mac.deviceId, isNot(phone.deviceId));
    });

    test('a round trip opens on every device it was sealed for', () async {
      for (final me in [mac, phone, desktop]) {
        expect((await openAs(me)).text, 'GG 🔥');
      }
      expect(sent.sealed.keys.keys.toSet(), {
        mac.deviceId,
        phone.deviceId,
        desktop.deviceId,
      });
    });

    test('a device added later has no key for it', () async {
      expect(await codeOf(() => openAs(later)), E2eeErrorCode.noKey);
    });

    test('anything moved or changed is refused', () async {
      Sealed changed(Map<String, dynamic> with_) =>
          Sealed.fromJson({...sent.sealed.toJson(), ...with_});
      for (final field in ['body', 'sig', 'nonce', 'eph']) {
        final value = sent.sealed.toJson()[field] as String;
        expect(
          await codeOf(
            () => openAs(desktop, sealed: changed({field: flip(value)})),
          ),
          E2eeErrorCode.badMessage,
          reason: field,
        );
      }
      expect(
        await codeOf(() => openAs(desktop, conversation: messageId)),
        E2eeErrorCode.badMessage,
      );
      expect(
        await codeOf(() => openAs(desktop, id: conversationId)),
        E2eeErrorCode.badMessage,
      );
      expect(
        await codeOf(() => openAs(desktop, author: bob)),
        E2eeErrorCode.badMessage,
      );
      // Signed by a device that is not the author's.
      expect(
        await codeOf(() => openAs(desktop, authors: [desktopPublic])),
        E2eeErrorCode.badMessage,
      );
      // A key wrapped for one device does not open for another.
      final keys = {...sent.sealed.keys}
        ..[desktop.deviceId] = sent.sealed.keys[mac.deviceId]!;
      expect(
        await codeOf(() => openAs(desktop, sealed: changed({'keys': keys}))),
        E2eeErrorCode.badMessage,
      );
      // Another sending device claimed than the one that signed.
      expect(
        await codeOf(
          () => openAs(desktop, sealed: changed({'device': mac.deviceId})),
        ),
        E2eeErrorCode.badMessage,
      );
    });

    test('opens with the content key alone, as a report does', () async {
      final context = MessageContext(
        conversationId: conversationId,
        messageId: messageId,
        senderUserId: alice,
        senderDeviceId: phone.deviceId,
      );
      final key = await unwrapKey(sent.sealed, context, desktop);
      expect(key, sent.contentKey);
      expect(
        (await openWithKey(
          sent.sealed,
          context,
          key,
          phonePublic.signKey,
        )).text,
        'GG 🔥',
      );
      expect(
        await codeOf(
          () => openWithKey(
            sent.sealed,
            context,
            Uint8List(32),
            phonePublic.signKey,
          ),
        ),
        E2eeErrorCode.badMessage,
      );
      expect(
        await codeOf(
          () => openWithKey(sent.sealed, context, key, macPublic.signKey),
        ),
        E2eeErrorCode.badMessage,
      );
    });

    test('an all-zero shared secret is refused both ways', () async {
      // The all-zero point is of small order: X25519 with it gives zero.
      final zero = phonePublic.copyWith(boxKey: base64.encode(Uint8List(32)));
      expect(
        await codeOf(
          () => seal(
            conversationId: conversationId,
            messageId: messageId,
            senderUserId: alice,
            sender: phone,
            recipients: [phonePublic, zero],
            payload: const Payload(text: 'x'),
          ),
        ),
        E2eeErrorCode.badDevice,
      );
      final zeroEph = Sealed.fromJson({
        ...sent.sealed.toJson(),
        'eph': base64.encode(Uint8List(32)),
      });
      expect(
        await codeOf(() => openAs(desktop, sealed: zeroEph)),
        E2eeErrorCode.badMessage,
      );
    });

    test('a payload that is not v1 JSON is refused', () async {
      final bad = await seal(
        conversationId: conversationId,
        messageId: messageId,
        senderUserId: alice,
        sender: phone,
        recipients: [phonePublic, desktopPublic],
        payload: const Payload(),
        payloadBytes: utf8.encode('{"v":2,"text":"x"}'),
      );
      expect(
        await codeOf(() => openAs(desktop, sealed: bad.sealed)),
        E2eeErrorCode.badPayload,
      );
    });

    test('files open with their key, only as the part they were', () async {
      final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
      final sealed = await sealFile(bytes, FilePart.file);
      expect(sealed.ciphertext.length, bytes.length + 16);
      expect(
        await openFile(
          sealed.ciphertext,
          FilePart.file,
          key: sealed.key,
          nonce: sealed.nonce,
        ),
        bytes,
      );
      expect(
        await codeOf(
          () => openFile(
            sealed.ciphertext,
            FilePart.poster,
            key: sealed.key,
            nonce: sealed.nonce,
          ),
        ),
        E2eeErrorCode.badMessage,
      );
    });

    test('base64 is read strictly', () {
      expect(fromBase64('AAAA', 3), Uint8List(3));
      for (final bad in ['AAA', 'AA-A', 'AA_A', ' AAAA', 'AA==AA==']) {
        expect(() => fromBase64(bad), throwsA(isA<E2eeError>()), reason: bad);
      }
      expect(() => fromBase64('AAAA', 4), throwsA(isA<E2eeError>()));
    });

    test('a sealed message from the API is checked before use', () {
      final json = sent.sealed.toJson();
      for (final broken in [
        {...json, 'v': 2},
        {...json, 'device': 'XYZ'},
        {...json, 'keys': 'none'},
        {...json, 'body': 5},
      ]) {
        expect(
          () => Sealed.fromJson(broken),
          throwsA(isA<E2eeError>()),
          reason: '$broken',
        );
      }
    });
  });
}
