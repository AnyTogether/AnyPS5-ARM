import 'dart:io';

import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/together/voice.dart';
import 'package:anyps5_remote/together/voice_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

const offerSdp =
    'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=rtpmap:111 opus/48000/2\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=0\r\n';

/// A peer connection that keeps what it was told and answers like a browser would.
class FakeLink implements VoiceLink {
  FakeLink(this.engine);

  final FakeEngine engine;
  final calls = <String>[];
  final candidates = <Map<String, dynamic>>[];
  Map<String, dynamic>? local;
  Map<String, dynamic>? remote;
  void Function(Map<String, dynamic>)? candidate;
  void Function()? state;
  double incoming = 0;
  double outgoing = 0;
  bool closed = false;

  @override
  String signalingState = 'stable';
  @override
  String connectionState = 'new';
  @override
  bool hasRemote = false;

  @override
  Future<Map<String, dynamic>> createOffer({bool restart = false}) async {
    calls.add(restart ? 'offer(restart)' : 'offer');
    return {'type': 'offer', 'sdp': offerSdp};
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    calls.add('answer');
    return {'type': 'answer', 'sdp': offerSdp};
  }

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {
    local = description;
    calls.add('local ${description['type']}');
    signalingState = description['type'] == 'offer'
        ? 'have-local-offer'
        : 'stable';
  }

  @override
  Future<void> setRemote(Map<String, dynamic> description) async {
    remote = description;
    hasRemote = true;
    calls.add('remote ${description['type']}');
    signalingState = description['type'] == 'offer'
        ? 'have-remote-offer'
        : 'stable';
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async =>
      candidates.add(candidate);

  @override
  Future<({double incoming, double outgoing})> levels() async =>
      (incoming: incoming, outgoing: outgoing);

  @override
  set onCandidate(void Function(Map<String, dynamic>) handler) =>
      candidate = handler;

  @override
  set onState(void Function() handler) => state = handler;

  @override
  Future<void> close() async => closed = true;
}

class FakeEngine implements VoiceEngine {
  FakeEngine({this.deny = false});

  final bool deny;
  final links = <FakeLink>[];
  List<Map<String, dynamic>>? ice;
  bool talking = true;
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start() async {
    if (deny) throw const VoiceDenied();
    started = true;
  }

  @override
  Future<VoiceLink> link(List<Map<String, dynamic>> iceServers) async {
    ice = iceServers;
    final link = FakeLink(this);
    links.add(link);
    return link;
  }

  @override
  void setTalking(bool on) => talking = on;

  @override
  Future<void> stop() async => stopped = true;
}

Map<String, dynamic> party(String id, List<String> members) => {
  'id': id,
  'leaderId': members.first,
  'privacy': 'invite',
  'members': [for (final member in members) card(member)],
  'invited': [],
  'call': null,
};

void main() {
  test('Opus is tuned for voice, the way the website does it', () {
    final tuned = tuneOpus(offerSdp);
    expect(
      tuned,
      contains(
        'a=fmtp:111 minptime=10;useinbandfec=1;usedtx=1;stereo=0;maxaveragebitrate=32000',
      ),
    );
    final bare = tuneOpus(
      'm=audio 9 UDP/TLS/RTP/SAVPF 109\r\na=rtpmap:109 opus/48000/2\r\n',
    );
    expect(
      bare,
      contains(
        'a=rtpmap:109 opus/48000/2\r\na=fmtp:109 useinbandfec=1;usedtx=1;stereo=0;maxaveragebitrate=32000',
      ),
    );
    expect(tuneOpus('m=video 9'), 'm=video 9');
  });

  group('the mesh', () {
    late FakeEngine engine;
    late List<(String, String, String, Object?)> sent;
    late VoiceMesh mesh;

    VoiceMesh make(String me) => VoiceMesh(
      me: me,
      engine: engine,
      iceServers: const [
        {
          'urls': ['stun:stun.example.org'],
        },
      ],
      signal: (to, device, kind, data) {
        sent.add((to, device, kind, data));
        return true;
      },
      onChange: () {},
    );

    setUp(() {
      engine = FakeEngine();
      sent = [];
      mesh = make('m');
    });

    test('the newcomer offers, and takes the answer', () async {
      await mesh.connectTo('z', 'dz');
      final (to, device, kind, data) = sent.single;
      expect((to, device, kind), ('z', 'dz', 'offer'));
      expect((data! as Map)['sdp'], contains('usedtx=1'));
      expect(engine.ice!.single['urls'], ['stun:stun.example.org']);
      // A candidate before the answer waits for it.
      await mesh.onSignal('z', 'dz', 'candidate', {'candidate': 'c1'});
      expect(engine.links.single.candidates, isEmpty);
      await mesh.onSignal('z', 'dz', 'answer', {
        'type': 'answer',
        'sdp': offerSdp,
      });
      expect(engine.links.single.calls, [
        'offer',
        'local offer',
        'remote answer',
      ]);
      expect(engine.links.single.candidates.single['candidate'], 'c1');
      engine.links.single.candidate!({'candidate': 'mine'});
      expect(sent.last.$3, 'candidate');
    });

    test(
      'an offer is answered, and a signal from another device is not taken',
      () async {
        await mesh.onSignal('a', 'da', 'offer', {
          'type': 'offer',
          'sdp': offerSdp,
        });
        expect(sent.single.$3, 'answer');
        expect((sent.single.$4! as Map)['sdp'], contains('stereo=0'));
        await mesh.onSignal('a', 'other', 'candidate', {'candidate': 'x'});
        expect(engine.links.single.candidates, isEmpty);
        await mesh.onSignal('a', 'da', 'candidate', {'candidate': 'y'});
        expect(engine.links.single.candidates.single['candidate'], 'y');
      },
    );

    test(
      'two offers at once: the polite side gives way, the other ignores',
      () async {
        // 'm' is larger than 'a': polite.
        await mesh.connectTo('a', 'da');
        await mesh.onSignal('a', 'da', 'offer', {
          'type': 'offer',
          'sdp': offerSdp,
        });
        expect(engine.links.single.calls, [
          'offer',
          'local offer',
          'local rollback',
          'remote offer',
          'answer',
          'local answer',
        ]);
        // 'm' is smaller than 'z': impolite, keeps its own offer.
        await mesh.connectTo('z', 'dz');
        await mesh.onSignal('z', 'dz', 'offer', {
          'type': 'offer',
          'sdp': offerSdp,
        });
        expect(engine.links.last.calls, ['offer', 'local offer']);
      },
    );

    test('a failed path is restarted by the impolite side', () async {
      await mesh.connectTo('z', 'dz');
      await mesh.onSignal('z', 'dz', 'answer', {
        'type': 'answer',
        'sdp': offerSdp,
      });
      final link = engine.links.single
        ..connectionState = 'failed'
        ..state!();
      await until(() => link.calls.contains('offer(restart)'));
      expect(sent.last.$3, 'offer');
    });

    test(
      'speaking rings come from the levels, and muting stops mine',
      () async {
        await mesh.connectTo('z', 'dz');
        engine.links.single
          ..incoming = 0.2
          ..outgoing = 0.3;
        await mesh.measure();
        expect(mesh.peers.single.speaking, isTrue);
        expect(mesh.speaking, isTrue);
        mesh.talking = false;
        expect(engine.talking, isFalse);
        await mesh.measure();
        expect(mesh.speaking, isFalse);
      },
    );

    test(
      'leaving says bye to everyone and lets go of the microphone',
      () async {
        await mesh.connectTo('z', 'dz');
        await mesh.onSignal('a', 'da', 'offer', {
          'type': 'offer',
          'sdp': offerSdp,
        });
        sent.clear();
        await mesh.close();
        expect(sent.map((s) => (s.$1, s.$3)).toSet(), {
          ('z', 'bye'),
          ('a', 'bye'),
        });
        expect(engine.links.every((link) => link.closed), isTrue);
        expect(engine.stopped, isTrue);
      },
    );
  });

  group('voice in the party', () {
    late FakeServer server;
    late TogetherHub hub;
    late FakeEngine engine;
    var deny = false;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      deny = false;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/party') => (
          200,
          {
            'party': party('p1', ['me', 'ece', 'can']),
            'invites': [],
          },
        ),
        ('POST', '/api/v1/calls') => (
          201,
          {
            'call': {
              'id': 'call1',
              'kind': 'party',
              'partyId': 'p1',
              'in': [
                {'userId': 'ece', 'device': 'dev-ece'},
                {'userId': 'me', 'device': 'device-1'},
              ],
            },
            'iceServers': [
              {
                'urls': ['turn:turn.example.org:3478'],
                'username': '1:me',
                'credential': 'c',
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
        voiceEngine: () => engine = FakeEngine(deny: deny),
      );
      await until(() => hub.parties.party != null);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Voice voice() => hub.voice;

    test(
      'joining asks for the call and offers to everyone already in',
      () async {
        await voice().join();
        expect(voice().active, isTrue);
        expect(voice().callId, 'call1');
        expect(server.requests.firstWhere((r) => r.$2 == '/api/v1/calls').$3, {
          'partyId': 'p1',
        });
        await until(() => server.sent('signal').isNotEmpty);
        expect(engine.ice!.single['username'], '1:me');
        final offer = server.sent('signal').single;
        expect(offer['to'], 'ece');
        expect(offer['device'], 'dev-ece');
        expect(offer['call'], 'call1');
        expect(offer['kind'], 'offer');
      },
    );

    test(
      'signals for the call reach the mesh; someone leaving is dropped',
      () async {
        await voice().join();
        await until(() => engine.links.length == 1);
        server.push('signal', {
          'call': 'call1',
          'from': 'ece',
          'device': 'dev-ece',
          'kind': 'answer',
          'data': {'type': 'answer', 'sdp': offerSdp},
        }, id: '17-a');
        await until(() => engine.links.single.hasRemote);
        // Another call's signal is not ours.
        server.push('signal', {
          'call': 'other',
          'from': 'can',
          'device': 'dev-can',
          'kind': 'offer',
          'data': {'type': 'offer', 'sdp': offerSdp},
        }, id: '17-b');
        server.push('call.left', {
          'callId': 'call1',
          'partyId': 'p1',
          'userId': 'ece',
        });
        await until(() => engine.links.single.closed);
        expect(engine.links, hasLength(1));
        expect(voice().peers, isEmpty);
      },
    );

    test('muting stops the microphone; leaving tells the server', () async {
      await voice().join();
      voice().setMuted(true);
      expect(engine.talking, isFalse);
      await voice().leave();
      expect(voice().active, isFalse);
      expect(engine.stopped, isTrue);
      expect(server.requests.last.$2, '/api/v1/calls/call1/leave');
      // Muted stays muted for the next time.
      await voice().join();
      expect(engine.talking, isFalse);
    });

    test('leaving the party leaves its voice', () async {
      await voice().join();
      await hub.parties.leave();
      await until(() => !voice().active);
      expect(engine.stopped, isTrue);
    });

    test('the call ending ends the voice', () async {
      await voice().join();
      server.push('call.ended', {
        'callId': 'call1',
        'partyId': 'p1',
        'reason': 'ended',
      });
      await until(() => !voice().active);
    });

    test('no microphone, no voice, and a reason', () async {
      deny = true;
      await voice().join();
      expect(voice().active, isFalse);
      expect(voice().problem, VoiceProblem.microphone);
      expect(server.requests.any((r) => r.$2 == '/api/v1/calls'), isFalse);
    });
  });
}
