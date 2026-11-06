import 'dart:convert';

import 'package:anyps5_remote/together/e2ee.dart';
import 'package:anyps5_remote/together/e2ee_keys.dart';

/// End-to-end encryption for the pictures: Ines's phone and Mac, Mira's Mac and her new phone,
/// every message of the Mira thread really sealed and opened on the phone, Theo on an older app
/// (not encrypted), and Sol with a conversation that was encrypted, a message from before this
/// phone, one that does not open, and no device now.
class DemoE2ee {
  DemoE2ee._(this.inesPhone, this.inesMac, this.miraMac, this.miraPhone);

  static Future<DemoE2ee> make() async {
    Future<DeviceSecrets> device(int n) =>
        DeviceSecrets.fromSeeds(List.filled(32, n), List.filled(32, n + 100));
    return DemoE2ee._(
      await device(1),
      await device(2),
      await device(3),
      await device(4),
    );
  }

  final DeviceSecrets inesPhone;
  final DeviceSecrets inesMac;
  final DeviceSecrets miraMac;
  final DeviceSecrets miraPhone;

  final _sealed = <String, Map<String, dynamic>>{};

  /// The phone's keystore, with Ines's phone keys in it.
  DeviceKeyStore keys(Uri server) =>
      MemoryDeviceKeyStore()
        ..kept[keySlot(server, 'ines')] = encodeSecrets(inesPhone);

  /// What the Mira conversation saw before: Mira's Mac only, so her new phone shows the notice.
  Map<String, Object> preferences(Map<String, Object> signedIn) => {
    ...signedIn,
    'together.e2ee.conversations.ines': jsonEncode({
      'c-mira': {
        'theirs': [miraMac.deviceId],
        'mine': [inesMac.deviceId, inesPhone.deviceId]..sort(),
        'encrypted': true,
      },
    }),
  };

  Future<Map<String, dynamic>> _device(
    DeviceSecrets d,
    String user,
    String name,
  ) async {
    final p = await publicDevice(d, user, name: name);
    return {
      'id': p.id,
      'signKey': p.signKey,
      'boxKey': p.boxKey,
      'sig': p.sig,
      'name': name,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'removedAt': null,
    };
  }

  Future<List<PublicDevice>> _public(
    List<(DeviceSecrets, String)> list,
  ) async => [for (final (d, user) in list) await publicDevice(d, user)];

  /// A message as the API keeps it: sealed for [to], its text only the stand-in.
  Future<Map<String, dynamic>> seal(
    Map<String, dynamic> message, {
    List<(DeviceSecrets, String)>? to,
    bool broken = false,
  }) async {
    final key = '${message['id']}|$broken|${to?.length}';
    final known = _sealed[key];
    if (known != null) return known;
    final author = message['authorId'] as String;
    final sender = author == 'ines' ? inesPhone : miraMac;
    final recipients =
        to ??
        [
          (inesPhone, 'ines'),
          (inesMac, 'ines'),
          (miraMac, 'mira'),
          (miraPhone, 'mira'),
        ];
    final result = await seal_(
      conversationId: message['conversationId'] as String,
      messageId: message['id'] as String,
      senderUserId: author,
      sender: sender,
      recipients: await _public(recipients),
      payload: Payload(text: message['text'] as String?),
    );
    var sealed = result.sealed.toJson();
    if (broken) sealed = {...sealed, 'sig': toBase64(List.filled(64, 7))};
    return _sealed[key] = {
      ...message,
      'text': '[encrypted message]',
      'sealed': sealed,
    };
  }

  /// The demo's own [base] answer, sealed where the conversation is encrypted.
  Future<Map<String, dynamic>> wrap(
    String method,
    String path,
    Map<String, dynamic> base,
  ) async {
    final bare = path.split('?').first;
    if (method == 'GET' && bare == 'me/conversations') {
      return {
        'conversations': [
          for (final c
              in (base['conversations'] as List).cast<Map<String, dynamic>>())
            if (c['id'] == 'c-mira' || c['id'] == 'c-sol')
              {
                ...c,
                'encrypted': true,
                'lastMessage': await seal(
                  c['lastMessage'] as Map<String, dynamic>,
                ),
              }
            else
              c,
        ],
      };
    }
    if (method == 'GET' && bare == 'conversations/c-mira/messages') {
      return {
        ...base,
        'messages': [
          for (final m
              in (base['messages'] as List).cast<Map<String, dynamic>>())
            await seal(m),
        ],
      };
    }
    if (method == 'GET' && bare == 'conversations/c-sol/messages') {
      Map<String, dynamic> message(
        int seq,
        String author,
        String text,
        int minutes,
      ) => {
        'id':
            '0190a000-0000-7000-8000-${(seq + 300).toString().padLeft(12, '0')}',
        'conversationId': 'c-sol',
        'seq': seq,
        'authorId': author,
        'text': text,
        'replyTo': null,
        'editedAt': null,
        'deletedAt': null,
        'createdAt': DateTime.now()
            .subtract(Duration(minutes: minutes))
            .toUtc()
            .toIso8601String(),
      };
      return {
        'messages': [
          await seal(
            message(28, 'sol', 'last week’s tournament bracket', 1500),
            to: [(inesMac, 'ines'), (miraMac, 'sol')],
          ),
          await seal(
            message(29, 'sol', 'ready for round two?', 1260),
            broken: true,
          ),
          await seal(message(30, 'ines', 'gg, rematch tomorrow', 1200)),
        ],
        'more': false,
      };
    }
    return base;
  }

  /// The answer for an encryption call, or null for anything else.
  Future<Map<String, dynamic>?> answer(String method, String path) async {
    final bare = path.split('?').first;
    switch ((method, bare)) {
      case ('GET', 'me/e2ee/device'):
        return _device(inesPhone, 'ines', 'Pixel 8');
      case ('GET', 'e2ee/devices'):
        final users =
            Uri.parse(path).queryParameters['users']?.split(',') ?? [];
        return {
          'users': [
            if (users.contains('ines'))
              {
                'userId': 'ines',
                'devices': [
                  await _device(inesPhone, 'ines', 'Pixel 8'),
                  await _device(inesMac, 'ines', 'MacBook Air'),
                ],
                'removed': [],
              },
            if (users.contains('mira'))
              {
                'userId': 'mira',
                'devices': [
                  await _device(miraMac, 'mira', 'Mira’s Mac mini'),
                  await _device(miraPhone, 'mira', 'iPhone 16'),
                ],
                'removed': [],
              },
            for (final other in ['theo', 'sol', 'ada', 'kenji'])
              if (users.contains(other))
                {'userId': other, 'devices': [], 'removed': []},
          ],
        };
    }
    return null;
  }
}

/// The library's seal, beside the method of the same name.
const seal_ = seal;
