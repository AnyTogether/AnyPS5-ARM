// The cryptography is pure Dart: slow in a debug test run on a busy machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/together/e2ee.dart';
import 'package:anyps5_remote/together/e2ee_devices.dart';
import 'package:anyps5_remote/together/e2ee_keys.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fake_server.dart';

/// The phone against a server that keeps device keys and sealed messages, with Ece on another
/// device: registering, opening, sealing, the device checks and every refusal the contract has.
const conversationId = '0190a000-0000-7000-8000-0000000c0c01';

Map<String, dynamic> conversation({bool encrypted = false}) => {
  'id': conversationId,
  'kind': 'direct',
  'title': null,
  'createdBy': 'me',
  'members': [card('me'), card('ece')],
  'lastSeq': 0,
  'readSeq': 0,
  'unread': 0,
  'lastMessage': null,
  'updatedAt': DateTime.utc(2026, 11, 6, 12).toIso8601String(),
  'encrypted': encrypted,
};

Map<String, dynamic> view(
  String id,
  int seq, {
  String author = 'ece',
  Sealed? sealed,
  String? text,
  List<Map<String, dynamic>> attachments = const [],
}) => {
  'id': id,
  'conversationId': conversationId,
  'seq': seq,
  'authorId': author,
  'kind': attachments.isEmpty ? 'text' : 'image',
  'text': sealed != null ? '[encrypted message]' : text,
  'caption': null,
  'attachments': attachments,
  'replyTo': null,
  'editedAt': null,
  'editCount': 0,
  'reactions': [],
  'deletedAt': null,
  'createdAt': DateTime.utc(2026, 11, 6, 12, seq).toIso8601String(),
  'sealed': ?sealed?.toJson(),
};

Map<String, dynamic> deviceJson(PublicDevice d, {String name = 'Ece Mac'}) => {
  'id': d.id,
  'signKey': d.signKey,
  'boxKey': d.boxKey,
  'sig': d.sig,
  'name': name,
  'createdAt': '2026-11-01T10:00:00.000Z',
  'removedAt': null,
};

String id(int n) => '0190a000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeServer server;
  late TogetherHub hub;
  late MemoryDeviceKeyStore keys;
  late DeviceSecrets ece;
  late PublicDevice ecePublic;

  // What the fake server keeps.
  late bool routes;
  Map<String, dynamic>? registered;
  String? registeredId;
  late List<PublicDevice> eceDevices;
  late bool encrypted;
  late List<Map<String, dynamic>> thread;
  late List<Map<String, dynamic>> sent;
  late int devicesConflicts;
  late bool requirePlain;

  Future<void> start({
    bool withRoutes = true,
    MemoryDeviceKeyStore? store,
  }) async {
    routes = withRoutes;
    keys = store ?? MemoryDeviceKeyStore();
    hub = TogetherHub(account: await server.account(), e2eeKeys: keys);
    await until(
      () => hub.e2ee.availability != E2eeAvailability.unknown,
      within: const Duration(seconds: 90),
    );
    registeredId = hub.e2ee.device?.deviceId ?? registeredId;
  }

  PublicDevice mine() =>
      PublicDevice.fromJson({...registered!, 'id': registeredId});

  setUpAll(() async {
    ece = await DeviceSecrets.generate();
    ecePublic = await publicDevice(ece, 'ece', name: 'Ece Mac');
  });

  setUp(() async {
    HttpOverrides.global = null;
    registered = null;
    registeredId = null;
    eceDevices = [ecePublic];
    encrypted = false;
    thread = [];
    sent = [];
    devicesConflicts = 0;
    requirePlain = false;
    server = FakeServer();
    server.answer = (method, path, body) {
      const missing = (
        404,
        {'code': 'not_found', 'status': 404, 'title': 'Not found'},
      );
      final bare = path.split('?').first;
      if (bare.contains('/e2ee') && !routes) return missing;
      switch ((method, bare)) {
        case ('GET', '/api/v1/me/e2ee/device'):
          final r = registered;
          if (r == null) return missing;
          return (200, {...r, 'id': registeredId});
        case ('PUT', '/api/v1/me/e2ee/device'):
          final again = registered != null;
          registered = body;
          return (again ? 200 : 201, body);
        case ('GET', '/api/v1/e2ee/devices'):
          final users = Uri.parse(path).queryParameters['users']!.split(',');
          return (
            200,
            {
              'users': [
                if (users.contains('me'))
                  {
                    'userId': 'me',
                    'devices': [
                      if (registered != null)
                        {
                          ...registered!,
                          'id': registeredId,
                          'createdAt': null,
                          'removedAt': null,
                        },
                    ],
                    'removed': [],
                  },
                if (users.contains('ece'))
                  {
                    'userId': 'ece',
                    'devices': [for (final d in eceDevices) deviceJson(d)],
                    'removed': [],
                  },
              ],
            },
          );
        case ('GET', '/api/v1/me/conversations'):
          return (
            200,
            {
              'conversations': [conversation(encrypted: encrypted)],
            },
          );
        case ('GET', '/api/v1/me/conversations/unread'):
          return (200, {'conversations': 0, 'messages': 0});
        case ('GET', '/api/v1/conversations/$conversationId/messages'):
          return (200, {'messages': thread, 'more': false});
        case ('POST', '/api/v1/conversations/$conversationId/messages'):
          sent.add(body!);
          if (body['sealed'] == null && (encrypted || requirePlain)) {
            return (
              409,
              {'code': 'e2ee_required', 'status': 409, 'title': 'Encrypted'},
            );
          }
          if (body['sealed'] != null) {
            final keys = (body['sealed']['keys'] as Map).keys.toSet();
            final want = {
              hub.e2ee.device!.deviceId,
              for (final d in eceDevices) d.id,
            };
            if (devicesConflicts > 0 ||
                keys.length != want.length ||
                !keys.containsAll(want)) {
              if (devicesConflicts > 0) devicesConflicts--;
              return (
                409,
                {'code': 'e2ee_devices', 'status': 409, 'title': 'Devices'},
              );
            }
            encrypted = true;
          }
          return (
            201,
            {
              ...view(
                body['clientId'] as String,
                thread.length + 10,
                author: 'me',
                sealed: body['sealed'] == null
                    ? null
                    : Sealed.fromJson(body['sealed']),
                text: body['text'] as String?,
                attachments: [
                  for (final a in (body['attachments'] as List? ?? const []))
                    {
                      'id': a['mediaId'],
                      'kind': 'image',
                      'contentType': 'application/octet-stream',
                      'size': 1,
                      'width': null,
                      'height': null,
                      'durationMs': null,
                      'url': 'http://127.0.0.1/none',
                      'thumb': null,
                      'poster': null,
                      'sealed': true,
                      'createdAt': '2026-11-06T12:00:00.000Z',
                    },
                ],
              ),
            },
          );
        case ('POST', '/api/v1/me/media/sealed'):
          return (
            201,
            {
              'media': {
                'id': id(900),
                'kind': 'image',
                'contentType': 'application/octet-stream',
                'size': 1,
                'url': 'http://127.0.0.1/none',
                'sealed': true,
                'createdAt': '2026-11-06T12:00:00.000Z',
              },
            },
          );
      }
      if (method == 'PATCH') {
        sent.add(body!);
        return (
          200,
          view(id(5), 5, author: 'me', sealed: Sealed.fromJson(body['sealed'])),
        );
      }
      return (204, null);
    };
    await server.start();
  });

  tearDown(() async {
    hub.dispose();
    await server.stop();
  });

  Future<Sealed> fromEce(
    String messageId,
    String text, {
    List<PublicDevice>? to,
  }) async => (await seal(
    conversationId: conversationId,
    messageId: messageId,
    senderUserId: 'ece',
    sender: ece,
    recipients: to ?? [mine(), ecePublic],
    payload: Payload(text: text),
  )).sealed;

  Future<Payload> eceOpens(Map<String, dynamic> body) => open(
    Sealed.fromJson(body['sealed']),
    conversationId: conversationId,
    messageId: body['clientId'] as String? ?? id(5),
    authorId: 'me',
    me: ece,
    authorDevices: [mine()],
  );

  Messages messages() => hub.messages;

  Future<void> openThread() async {
    await until(() => messages().loaded, within: const Duration(seconds: 90));
    await messages().show(conversationId);
  }

  test('the keys are made once, kept in the keystore and registered, signed for me', () async {
    await start();
    expect(hub.e2ee.on, isTrue);
    final body = registered!;
    expect(body.keys.toSet(), {'signKey', 'boxKey', 'sig', 'name'});
    final device = PublicDevice.fromJson({
      ...body,
      'id': hub.e2ee.device!.deviceId,
    });
    expect(await verifyDevice('me', device), isTrue);
    expect(keys.kept, hasLength(1));
    // The secrets are in the keystore, and nowhere in the app's preferences.
    final seed =
        (jsonDecode(keys.kept.values.single) as Map)['signSeed'] as String;
    final preferences = hub.account.preferences;
    for (final key in preferences.getKeys()) {
      expect('${preferences.get(key)}', isNot(contains(seed)), reason: key);
    }
    final firstId = hub.e2ee.device!.deviceId;
    final puts = server.requests.where((r) => r.$1 == 'PUT').length;

    // Signed in again on the same phone: the same keys, and nothing to register.
    hub.dispose();
    await start(store: keys);
    expect(hub.e2ee.device!.deviceId, firstId);
    expect(server.requests.where((r) => r.$1 == 'PUT').length, puts);
  });

  test('a server without the routes means no encryption, and messages work as before', () async {
    await start(withRoutes: false);
    expect(hub.e2ee.availability, E2eeAvailability.off);
    await openThread();
    expect(messages().lockOf(messages().open).state, ChatLock.none);
    final before = server.requests.length;
    await messages().send('hello');
    expect(sent.single, {'clientId': sent.single['clientId'], 'text': 'hello'});
    expect(
      server.requests.skip(before).where((r) => r.$2.contains('e2ee')),
      isEmpty,
    );
  });

  test(
    'sealed messages open on the phone; the stand-in text never shows',
    () async {
      await start();
      final other = await DeviceSecrets.generate();
      thread = [
        view(id(1), 1, sealed: await fromEce(id(1), 'Merhaba 👋')),
        // Sealed before this phone was added: no key for it.
        view(id(2), 2, sealed: await fromEce(id(2), 'old', to: [ecePublic])),
        // Signed by someone else's key.
        view(
          id(3),
          3,
          sealed: (await seal(
            conversationId: conversationId,
            messageId: id(3),
            senderUserId: 'ece',
            sender: other,
            recipients: [mine()],
            payload: const Payload(text: 'forged'),
          )).sealed,
        ),
        // Moved from another message.
        view(id(4), 4, sealed: await fromEce(id(1), 'moved')),
      ];
      await openThread();
      final shown = messages().thread;
      expect(shown[0].seal, SealState.open);
      expect(shown[0].text, 'Merhaba 👋');
      expect(shown[1].seal, SealState.noKey);
      expect(shown[2].seal, SealState.failed);
      expect(shown[3].seal, SealState.failed);
      for (final m in shown.skip(1)) {
        expect(m.text, isNull);
        expect(m.words, isNull);
      }
      expect(messages().lockOf(messages().open).state, ChatLock.encrypted);
    },
  );

  test(
    'a message is sealed for every device of both, and Ece opens it',
    () async {
      await start();
      await openThread();
      await messages().send('GG 🔥');
      final body = sent.single;
      expect(body.containsKey('text'), isFalse);
      expect((body['sealed']['keys'] as Map).keys.toSet(), {
        hub.e2ee.device!.deviceId,
        ecePublic.id,
      });
      expect((await eceOpens(body)).text, 'GG 🔥');
      final mineNow = messages().thread.single;
      expect(mineNow.seal, SealState.open);
      expect(mineNow.text, 'GG 🔥');
      expect(mineNow.pending, isFalse);
    },
  );

  test(
    '409 e2ee_devices: the devices again, the change shown, sealed again',
    () async {
      await start();
      await openThread();
      expect(messages().lockOf(messages().open).notice, isNull);
      // Ece signed in on a new phone since the thread was opened.
      final phone = await DeviceSecrets.generate();
      eceDevices = [
        ecePublic,
        await publicDevice(phone, 'ece', name: 'Ece phone'),
      ];
      await messages().send('still there?');
      expect(sent, hasLength(2));
      expect((sent.last['sealed']['keys'] as Map), hasLength(3));
      expect(messages().thread.single.failed, isFalse);
      expect(messages().lockOf(messages().open).notice, DevicesNotice.theirs);
      hub.e2ee.dismissNotice(conversationId);
      expect(messages().lockOf(messages().open).notice, isNull);
    },
  );

  test('a device list that keeps changing fails after a few tries', () async {
    await start();
    await openThread();
    devicesConflicts = 99;
    await messages().send('hello?');
    expect(sent, hasLength(Messages.sealTries));
    expect(messages().thread.single.failed, isTrue);
    expect(messages().thread.single.problem?.code, 'e2ee_devices');
  });

  test('a device that does not check out is left out', () async {
    await start();
    final fake = await publicDevice(await DeviceSecrets.generate(), 'mallory');
    eceDevices = [ecePublic, fake];
    await openThread();
    expect(hub.e2ee.devicesOf('ece')!.active.map((d) => d.id), [ecePublic.id]);
  });

  test(
    'the other person on an older app: plain, labelled, as before',
    () async {
      await start();
      eceDevices = [];
      await openThread();
      expect(messages().lockOf(messages().open).state, ChatLock.plain);
      await messages().send('hi');
      expect(sent.single['text'], 'hi');
      expect(sent.single.containsKey('sealed'), isFalse);
    },
  );

  test(
    'encrypted, but the other person has no device now: nothing goes out',
    () async {
      await start();
      eceDevices = [];
      encrypted = true;
      await openThread();
      expect(messages().lockOf(messages().open).state, ChatLock.noDevice);
      await messages().send('hi');
      expect(sent, isEmpty);
      expect(messages().thread.single.failed, isTrue);
    },
  );

  test('409 e2ee_required on a plain message: sealed after all', () async {
    await start();
    eceDevices = [];
    await openThread();
    expect(messages().lockOf(messages().open).state, ChatLock.plain);
    // Ece updated her app meanwhile.
    eceDevices = [ecePublic];
    requirePlain = true;
    await messages().send('now?');
    expect(sent, hasLength(2));
    expect(sent.first['text'], 'now?');
    expect((await eceOpens(sent.last)).text, 'now?');
    expect(hub.e2ee.seenEncrypted(conversationId), isTrue);
  });

  test('a conversation seen encrypted never gets plain text, even if the server says no devices', () async {
    await start();
    thread = [view(id(1), 1, sealed: await fromEce(id(1), 'secret'))];
    await openThread();
    expect(hub.e2ee.seenEncrypted(conversationId), isTrue);
    eceDevices = [];
    await hub.e2ee.fetch(['ece']);
    expect(messages().lockOf(messages().open).state, ChatLock.noDevice);
    await messages().send('plain?');
    expect(sent, isEmpty);
  });

  test(
    'devices that change show a notice; the first time only remembers',
    () async {
      await start();
      await openThread();
      final lock = messages().lockOf(messages().open);
      expect(lock.notice, isNull);
      hub.e2ee.markCompared(conversationId);
      expect(messages().lockOf(messages().open).compared, isTrue);
      final phone = await DeviceSecrets.generate();
      eceDevices = [ecePublic, await publicDevice(phone, 'ece')];
      server.push('e2ee.devices', {'userId': 'ece'});
      await until(() => messages().lockOf(messages().open).notice != null);
      expect(messages().lockOf(messages().open).notice, DevicesNotice.theirs);
      expect(messages().lockOf(messages().open).compared, isFalse);
    },
  );

  test('both sides see the same safety number', () async {
    await start();
    await openThread();
    final chat = messages().chatOf(messages().open)!;
    final number = await hub.e2ee.safetyNumberOf(chat);
    expect(number, matches(RegExp(r'^\d{60}$')));
    final eceSide = await safetyNumber(
      (userId: 'ece', signKeys: [ecePublic.signKey]),
      (userId: 'me', signKeys: [mine().signKey]),
    );
    expect(number, eceSide);
  });

  test('a photo goes up sealed, drawn again without its EXIF, and its keys in the message', () async {
    await start();
    await openThread();
    final picture = img.Image(width: 30, height: 20);
    picture.exif.imageIfd['Model'] = img.IfdValueAscii('SecretCam 9');
    picture.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    final jpeg = img.encodeJpg(picture);
    await messages().sendPhoto(jpeg, caption: 'look');
    final upload = server.uploads.single;
    expect(upload.$2, '/api/v1/me/media/sealed?kind=image');
    expect(upload.$4, 'application/octet-stream');
    final body = sent.single;
    expect(body['attachments'], [
      {'mediaId': id(900)},
    ]);
    final payload = await eceOpens(body);
    expect(payload.text, 'look');
    final a = payload.attachment!;
    expect(
      (a.mediaId, a.kind, a.type, a.width, a.height),
      (id(900), 'image', 'image/jpeg', 30, 20),
    );
    final plain = await openFile(
      upload.$3,
      FilePart.file,
      key: a.key,
      nonce: a.nonce,
    );
    expect(a.size, plain.length);
    expect(img.decodeJpg(plain)!.exif.isEmpty, isTrue);
    expect(
      latin1.decode(plain, allowInvalid: true).contains('SecretCam'),
      isFalse,
    );
    expect(
      latin1.decode(upload.$3, allowInvalid: true).contains('JFIF'),
      isFalse,
    );
    final shown = messages().thread.single;
    expect(shown.seal, SealState.open);
    expect(shown.attachments.single.file?.key, a.key);
  });

  test('an edit is a new seal of the same message', () async {
    await start();
    await openThread();
    await messages().send('frist');
    final message = messages().thread.single;
    await messages().edit(message, 'first');
    final patch = sent.last;
    expect(patch.keys, ['sealed']);
    final opened = await open(
      Sealed.fromJson(patch['sealed']),
      conversationId: conversationId,
      messageId: message.id,
      authorId: 'me',
      me: ece,
      authorDevices: [mine()],
    );
    expect(opened.text, 'first');
  });

  test('reporting a sealed message sends its content key', () async {
    await start();
    final result = await seal(
      conversationId: conversationId,
      messageId: id(1),
      senderUserId: 'ece',
      sender: ece,
      recipients: [mine(), ecePublic],
      payload: const Payload(text: 'bad words'),
    );
    thread = [view(id(1), 1, sealed: result.sealed)];
    await openThread();
    await messages().report(messages().thread.single, 'harassment');
    final report = server.requests
        .lastWhere((r) => r.$2 == '/api/v1/reports')
        .$3!;
    expect(report, {
      'targetKind': 'message',
      'targetId': id(1),
      'reason': 'harassment',
      'contentKey': base64.encode(result.contentKey),
    });
  });

  test(
    'the conversation list opens the last message for its preview',
    () async {
      await start();
      final last = view(id(7), 7, sealed: await fromEce(id(7), 'see you at 8'));
      final answer = server.answer;
      server.answer = (method, path, body) {
        if (path == '/api/v1/me/conversations') {
          return (
            200,
            {
              'conversations': [
                {
                  ...conversation(encrypted: true),
                  'lastMessage': last,
                  'lastSeq': 7,
                },
              ],
            },
          );
        }
        return answer(method, path, body);
      };
      await messages().refresh();
      final preview = messages().conversations.single.lastMessage!;
      expect(preview.seal, SealState.open);
      expect(preview.text, 'see you at 8');
    },
  );

  test(
    'a sealed attachment that is not the message\'s own does not open',
    () async {
      await start();
      final payload = Payload(
        text: 'x',
        attachment: SealedAttachment(
          mediaId: id(901),
          kind: 'image',
          type: 'image/jpeg',
          size: 3,
          key: base64.encode(Uint8List(32)),
          nonce: base64.encode(Uint8List(12)),
        ),
      );
      final result = await seal(
        conversationId: conversationId,
        messageId: id(1),
        senderUserId: 'ece',
        sender: ece,
        recipients: [mine(), ecePublic],
        payload: payload,
      );
      thread = [
        view(
          id(1),
          1,
          sealed: result.sealed,
          attachments: [
            {
              'id': id(902),
              'kind': 'image',
              'url': 'http://127.0.0.1/x',
              'sealed': true,
            },
          ],
        ),
      ];
      await openThread();
      expect(messages().thread.single.seal, SealState.failed);
    },
  );
}
