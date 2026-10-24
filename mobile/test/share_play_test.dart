import 'dart:io';
import 'dart:typed_data';

import 'package:anyps5_remote/protocol/packets.dart';
import 'package:anyps5_remote/stream/stream_packets.dart';
import 'package:anyps5_remote/together/people.dart';
import 'package:anyps5_remote/together/share_play.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

const offer = {
  'type': 'offer',
  'sdp': 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 102\r\n',
};

class FakeChannel implements ShareChannel {
  FakeChannel(this.label);

  @override
  final String label;
  @override
  bool open = true;
  final sent = <Uint8List>[];
  void Function(Uint8List)? handler;

  @override
  void send(Uint8List bytes) => sent.add(bytes);

  @override
  set onMessage(void Function(Uint8List bytes) handler) =>
      this.handler = handler;

  @override
  void close() => open = false;
}

class FakeShareLink implements ShareLink {
  final calls = <String>[];
  final candidates = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic>)? candidate;
  void Function()? state;
  void Function(ShareChannel)? channel;
  bool closed = false;

  @override
  String signalingState = 'stable';
  @override
  String connectionState = 'new';
  @override
  bool hasRemote = false;

  @override
  Future<void> setRemote(Map<String, dynamic> description) async {
    calls.add('remote ${description['type']}');
    hasRemote = true;
    signalingState = 'have-remote-offer';
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    calls.add('answer');
    return {'type': 'answer', 'sdp': 'v=0 answer'};
  }

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {
    calls.add('local ${description['type']}');
    signalingState = 'stable';
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async =>
      candidates.add(candidate);

  @override
  set onCandidate(void Function(Map<String, dynamic>) handler) =>
      candidate = handler;

  @override
  set onState(void Function() handler) => state = handler;

  @override
  set onChannel(void Function(ShareChannel) handler) => channel = handler;

  @override
  Widget video() => const SizedBox.expand();

  @override
  Future<ShareQuality> quality() async =>
      const ShareQuality(roundTripMs: 40, framesPerSecond: 60, height: 720);

  @override
  Future<void> close() async => closed = true;

  /// The connection works and the host's channels open.
  (FakeChannel, FakeChannel) connect() {
    connectionState = 'connected';
    state?.call();
    final pad = FakeChannel('pad');
    final audio = FakeChannel('audio');
    channel?.call(pad);
    channel?.call(audio);
    return (pad, audio);
  }
}

class FakeShareEngine implements ShareEngine {
  final links = <FakeShareLink>[];
  List<Map<String, dynamic>>? ice;

  @override
  Future<ShareLink> link(List<Map<String, dynamic>> iceServers) async {
    ice = iceServers;
    final link = FakeShareLink();
    links.add(link);
    return link;
  }
}

class FakeSound implements ShareSound {
  final packets = <AudioPacket>[];
  bool stopped = false;

  @override
  void sound(AudioPacket packet) => packets.add(packet);

  @override
  void stop() => stopped = true;
}

Map<String, dynamic> view({int? slot, List<Map<String, dynamic>>? viewers}) => {
  'id': 'sp1',
  'host': card('host', name: 'Ece'),
  'hostDevice': 'mac-1',
  'titleId': 'PPSA01234',
  'title': 'Cat Quest III',
  'open': true,
  'maxViewers': 3,
  'viewers':
      viewers ??
      [
        {
          'user': card('me', handle: 'utku', name: 'Utku'),
          'device': 'device-1',
          'slot': slot,
          'joinedAt': '2026-10-24T10:00:00Z',
        },
      ],
  'startedAt': '2026-10-24T10:00:00Z',
};

Uint8List audioPacket(int number) {
  final bytes = Uint8List(audioHeader + 960);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, audioMagic, Endian.little);
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, audioHeader, Endian.little);
  data.setUint32(8, number, Endian.little);
  data.setUint32(12, number * 5, Endian.little);
  bytes[audioHeader] = 7;
  return bytes;
}

Uint8List outputPacket({required int sentMicros, int r = 0, int g = 0}) {
  final bytes = Uint8List(outputSize);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, outputMagic, Endian.little);
  data.setUint16(4, protocolVersion, Endian.little);
  data.setUint16(6, outputSize, Endian.little);
  data.setUint64(16, sentMicros, Endian.little);
  bytes[24] = 200;
  bytes[26] = 1;
  bytes[27] = r;
  bytes[28] = g;
  return bytes;
}

void main() {
  test('a friend sharing shows in their presence', () {
    final presence = Presence.fromJson({
      'state': 'in_game',
      'titleId': 'PPSA01234',
      'share': {
        'sharePlayId': 'sp1',
        'titleId': 'PPSA01234',
        'title': 'Cat Quest III',
        'open': true,
        'viewers': 1,
        'maxViewers': 3,
      },
    });
    expect(presence.share?.sharePlayId, 'sp1');
    expect(presence.share?.open, isTrue);
    expect(presence.share?.maxViewers, 3);
    expect(Presence.fromJson({'state': 'online'}).share, isNull);
  });

  group('watching', () {
    late FakeServer server;
    late TogetherHub hub;
    late FakeShareEngine engine;
    late FakeSound sound;
    late String? expiresAt;
    late (int, Object?) joinAnswer;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      server = FakeServer();
      expiresAt = null;
      joinAnswer = (
        201,
        {
          'sharePlay': view(),
          'iceServers': [
            {
              'urls': ['turn:turn.example.org:3478'],
              'username': '1:me',
              'credential': 'c',
            },
          ],
          'expiresAt': null,
        },
      );
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/share-play') => (
          200,
          {
            'hosting': null,
            'watching': null,
            'invites': [
              {
                'sharePlayId': 'sp1',
                'from': card('host', name: 'Ece'),
                'titleId': 'PPSA01234',
                'title': 'Cat Quest III',
                'invitedAt': '2026-10-24T10:00:00Z',
              },
            ],
          },
        ),
        ('POST', '/api/v1/share-plays/sp1/join') => (
          joinAnswer.$1,
          joinAnswer.$1 == 201
              ? {
                  ...joinAnswer.$2! as Map<String, dynamic>,
                  'expiresAt': expiresAt,
                }
              : joinAnswer.$2,
        ),
        ('GET', '/api/v1/share-plays/sp1/ice-servers') => (
          200,
          {
            'iceServers': [
              {
                'urls': ['turn:turn.example.org:3478'],
                'username': '2:me',
                'credential': 'd',
              },
            ],
            'expiresAt': null,
          },
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(
        account: await server.account(),
        shareEngine: () => engine = FakeShareEngine(),
        shareSound: () => sound = FakeSound(),
      );
      await until(() => hub.sharePlays.invites.isNotEmpty);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    SharePlays plays() => hub.sharePlays;

    List<Map<String, dynamic>> signals() => server.sent('signal');

    void push(String kind, Object? data, {String from = 'host'}) =>
        server.push('share_play.signal', {
          'sharePlayId': 'sp1',
          'from': from,
          'device': 'mac-1',
          'kind': kind,
          'data': data,
        }, id: '${DateTime.now().microsecondsSinceEpoch}-s');

    Future<FakeShareLink> connected() async {
      await plays().watch('sp1');
      push('offer', offer);
      await until(() => signals().any((s) => s['kind'] == 'answer'));
      return engine.links.single;
    }

    test('invites come from the server and count in the badge', () {
      expect(plays().invites.single.name, 'Cat Quest III');
      expect(plays().invites.single.from?.displayName, 'Ece');
      expect(hub.badge, 1);
    });

    test(
      'joining asks the host for an offer, and the offer is answered',
      () async {
        await plays().watch('sp1');
        expect(plays().status, WatchStatus.connecting);
        expect(plays().invites, isEmpty);
        await until(() => signals().isNotEmpty);
        final ask = signals().first;
        expect(ask, {
          'op': 'signal',
          'to': 'host',
          'device': 'mac-1',
          'share': 'sp1',
          'kind': 'renegotiate',
          'data': null,
        });
        // A candidate before the offer waits for it.
        push('candidate', {
          'candidate': 'early',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        });
        push('offer', offer);
        await until(() => signals().any((s) => s['kind'] == 'answer'));
        final link = engine.links.single;
        expect(engine.ice!.single['username'], '1:me');
        expect(link.calls, ['remote offer', 'answer', 'local answer']);
        expect(link.candidates.single['candidate'], 'early');
        final answer = signals().firstWhere((s) => s['kind'] == 'answer');
        expect(answer['data'], {'type': 'answer', 'sdp': 'v=0 answer'});
        expect(answer['share'], 'sp1');
        link.candidate!({'candidate': 'mine'});
        await until(() => signals().any((s) => s['kind'] == 'candidate'));
        link.connect();
        expect(plays().status, WatchStatus.watching);
      },
    );

    test(
      'signals from anyone but the host, or another share play, are ignored',
      () async {
        await plays().watch('sp1');
        push('offer', offer, from: 'stranger');
        server.push('share_play.signal', {
          'sharePlayId': 'other',
          'from': 'host',
          'device': 'mac-1',
          'kind': 'offer',
          'data': offer,
        }, id: '99-x');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(engine.links, isEmpty);
      },
    );

    test(
      'a new offer on a working connection is taken by the same one',
      () async {
        final link = await connected();
        link.connect();
        push('offer', offer);
        await until(
          () => link.calls.where((c) => c == 'remote offer').length == 2,
        );
        expect(engine.links, hasLength(1));
      },
    );

    test('a failed connection is dropped and the host asked again', () async {
      final link = await connected();
      link.connectionState = 'failed';
      link.state!();
      await until(() => link.closed);
      await until(
        () => signals().where((s) => s['kind'] == 'renegotiate').length >= 2,
      );
      push('offer', offer);
      await until(() => engine.links.length == 2);
    });

    test('the pad goes only while the host lets this phone play', () async {
      final link = await connected();
      final (pad, _) = link.connect();
      plays().update(PadState()..buttons = PadButton.cross);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(pad.sent, isEmpty, reason: 'only watching');

      server.push('share_play.updated', view(slot: 2));
      await until(() => plays().slot == 2);
      await until(
        () => pad.sent.length > 3,
        within: const Duration(seconds: 1),
      );
      final last = pad.sent.last;
      expect(last, hasLength(inputSize));
      final data = ByteData.sublistView(last);
      expect(data.getUint32(0, Endian.little), inputMagic);
      expect(data.getUint32(32, Endian.little), PadButton.cross);
      // Sequences go up; one session for the whole watch.
      final first = ByteData.sublistView(pad.sent.first);
      expect(
        data.getUint32(8, Endian.little),
        greaterThan(first.getUint32(8, Endian.little)),
      );
      expect(
        data.getUint64(24, Endian.little),
        first.getUint64(24, Endian.little),
      );
      // A change goes at once.
      final before = pad.sent.length;
      plays().update(PadState()..buttons = PadButton.circle);
      expect(pad.sent.length, before + 1);
      expect(
        ByteData.sublistView(pad.sent.last).getUint32(32, Endian.little),
        PadButton.circle,
      );

      server.push('share_play.updated', view(slot: null));
      await until(() => plays().slot == null);
      final stopped = pad.sent.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(pad.sent.length, stopped);
      plays().update(PadState()..buttons = PadButton.cross);
      expect(pad.sent.length, stopped);
    });

    test(
      'the game answers on the pad channel: light, rumble and latency',
      () async {
        final link = await connected();
        final (pad, _) = link.connect();
        Output? heard;
        plays().onOutput = (output, _) => heard = output;
        pad.handler!(outputPacket(sentMicros: 0, r: 255));
        expect(heard?.large, 200);
        expect(plays().output?.r, 255);
        pad.handler!(Uint8List(5));
        expect(plays().output?.r, 255);
      },
    );

    test(
      "the game's sound reaches the speaker; anything else does not",
      () async {
        final link = await connected();
        final (_, audio) = link.connect();
        audio.handler!(audioPacket(1));
        audio.handler!(audioPacket(2));
        audio.handler!(Uint8List.fromList([1, 2, 3]));
        expect(sound.packets.map((p) => p.number), [1, 2]);
        expect(sound.packets.first.samples, hasLength(960));
        expect(sound.packets.first.samples.first, 7);
      },
    );

    test('the host stopping ends it; being taken out says so', () async {
      final link = await connected();
      server.push('share_play.ended', {
        'sharePlayId': 'sp1',
        'reason': 'removed',
      });
      await until(() => plays().status == WatchStatus.ended);
      expect(plays().ended, WatchEnd.removed);
      expect(link.closed, isTrue);
      expect(sound.stopped, isTrue);
      expect(server.requests.any((r) => r.$2.endsWith('/leave')), isFalse);
    });

    test('leaving says bye and tells the server', () async {
      final link = await connected();
      await plays().leave();
      expect(plays().status, WatchStatus.ended);
      expect(plays().ended, WatchEnd.left);
      expect(link.closed, isTrue);
      expect(signals().last['kind'], 'bye');
      expect(server.requests.last.$2, '/api/v1/share-plays/sp1/leave');
    });

    test('a full share play says so', () async {
      joinAnswer = (409, {'status': 409, 'code': 'full', 'title': 'Full'});
      await expectLater(plays().watch('sp1'), throwsA(anything));
      expect(plays().status, WatchStatus.ended);
      expect(plays().ended, WatchEnd.full);
    });

    test('declining tells the server', () async {
      await plays().decline(plays().invites.single);
      expect(plays().invites, isEmpty);
      expect(server.requests.last.$2, '/api/v1/share-plays/sp1/decline');
    });

    test(
      'relay credentials about to run out are renewed for new connections',
      () async {
        expiresAt = DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String();
        await plays().watch('sp1');
        await until(
          () => server.requests.any(
            (r) => r.$2 == '/api/v1/share-plays/sp1/ice-servers',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        push('offer', offer);
        await until(() => engine.links.length == 1);
        expect(engine.ice!.single['username'], '2:me');
      },
    );
  });
}
