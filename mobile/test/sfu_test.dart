import 'dart:io';

import 'package:anyps5_remote/together/media.dart';
import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/together/share_play.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/together/voice.dart';
import 'package:anyps5_remote/together/voice_mesh.dart';
import 'package:anyps5_remote/ui/together_widgets.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'share_play_test.dart'
    show FakeShareEngine, FakeShareLink, FakeSound, offer, view;
import 'support/fake_server.dart';
import 'voice_test.dart' show FakeEngine, party;

/// The media server's room as the viewer sees it: told what to join, put in a state by the test.
class FakeShareRoom implements ShareRoom {
  SfuAccess? joined;
  String? host;
  bool left = false;
  void Function()? changed;

  @override
  String state = 'connecting';

  @override
  Future<void> join(SfuAccess access, {required String host}) async {
    joined = access;
    this.host = host;
  }

  @override
  set onState(void Function() handler) => changed = handler;

  @override
  Widget video() => const SizedBox.expand();

  @override
  Future<ShareQuality> quality() async =>
      const ShareQuality(roundTripMs: 30, framesPerSecond: 60, height: 720);

  @override
  Future<void> leave() async => left = true;

  void become(String next) {
    state = next;
    changed?.call();
  }
}

class FakeVoiceRoom implements VoiceRoom {
  SfuAccess? joined;
  bool left = false;
  bool? joinedTalking;
  bool? joinedHearing;
  void Function()? changed;

  @override
  bool talking = true;
  @override
  bool hearing = true;
  @override
  bool speaking = false;
  @override
  List<PeerVoice> peers = const [];
  @override
  String state = 'connecting';

  @override
  Future<void> join(
    SfuAccess access, {
    required bool talking,
    required bool hearing,
  }) async {
    joined = access;
    joinedTalking = talking;
    joinedHearing = hearing;
    this.talking = talking;
    this.hearing = hearing;
    state = 'connected';
  }

  @override
  set onChange(void Function() handler) => changed = handler;

  @override
  Future<void> leave() async => left = true;
}

Map<String, dynamic> access(String room, {String token = 'jwt-1'}) => {
  'url': 'wss://media.example.org',
  'token': token,
  'room': room,
  'identity': 'me',
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 10))
      .toIso8601String(),
};

void main() {
  group('the models', () {
    test('a share play, a call and a party say how their media go', () {
      expect(SharePlayView.fromJson(view()).media, MediaRoute.mesh);
      expect(
        SharePlayView.fromJson({...view(), 'media': 'sfu'}).media,
        MediaRoute.sfu,
      );
      expect(
        SharePlayView.fromJson({...view(), 'media': 'mesh'}).media,
        MediaRoute.mesh,
      );
      expect(mediaRouteFrom(null), MediaRoute.mesh);
      expect(mediaRouteFrom('something new'), MediaRoute.mesh);

      final older = Party.fromJson({
        ...party('p1', ['me', 'ece']),
        'call': {
          'id': 'c1',
          'in': ['me'],
          'muted': [],
          'deafened': [],
        },
      });
      expect(older.callMedia, MediaRoute.mesh);
      expect(older.max, 8);
      final bigger = Party.fromJson({
        ...party('p1', ['me', 'ece']),
        'max': 24,
        'call': {
          'id': 'c1',
          'in': ['me'],
          'muted': [],
          'deafened': [],
          'media': 'sfu',
        },
      });
      expect(bigger.callMedia, MediaRoute.sfu);
      expect(bigger.max, 24);
      expect(bigger.full, isFalse);
      expect(
        Party.fromJson({
          ...party('p1', ['me', 'ece', 'can']),
          'max': 3,
        }).full,
        isTrue,
      );
    });

    test('media server access: read, and whether it still works', () {
      final room = SfuAccess.fromJson(access('share-sp1'))!;
      expect(room.url, 'wss://media.example.org');
      expect(room.token, 'jwt-1');
      expect(room.room, 'share-sp1');
      expect(room.identity, 'me');
      expect(room.usable, isTrue);
      final old = SfuAccess.fromJson({
        ...access('share-sp1'),
        'expiresAt': DateTime.now()
            .add(const Duration(seconds: 20))
            .toIso8601String(),
      })!;
      expect(old.usable, isFalse);
      expect(SfuAccess.fromJson(null), isNull);
      expect(SfuAccess.fromJson({'url': 'wss://x'}), isNull);
    });

    test('the limits, and the mesh ones when the server has none', () {
      final limits = MediaLimits.fromJson({
        'sfu': true,
        'maxShareViewers': 16,
        'maxPartySize': 24,
      });
      expect(limits.sfu, isTrue);
      expect(limits.maxShareViewers, 16);
      expect(limits.maxPartySize, 24);
      expect(MediaLimits.fromJson(const {}).sfu, isFalse);
      expect(MediaLimits.fromJson(const {}).maxShareViewers, 4);
      expect(MediaLimits.fromJson(const {}).maxPartySize, 8);
    });

    test('a server without a media server says so in words', () {
      final texts = Strings.of('en');
      expect(
        togetherFailure(
          texts,
          const TogetherProblem(400, 'media_server_off', 'More than 4'),
        ),
        texts.mediaServerOff,
      );
      expect(texts.mediaServerOff, isNot('mediaServerOff'));
      expect(Strings.of('tr').mediaServerOff, isNot(texts.mediaServerOff));
      expect(texts.shareViaServer, isNot('shareViaServer'));
    });
  });

  group('limits from the server', () {
    late FakeServer server;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      server = FakeServer();
      await server.start();
    });

    tearDown(() => server.stop());

    test('asked from /media-server; the mesh limits if it fails', () async {
      server.answer = (method, path, _) => switch ((method, path)) {
        ('GET', '/api/v1/media-server') => (
          200,
          {'sfu': true, 'maxShareViewers': 16, 'maxPartySize': 24},
        ),
        _ => (404, {'code': 'not_found', 'status': 404, 'title': 'no'}),
      };
      final account = await server.account();
      expect((await MediaLimits.of(account)).maxShareViewers, 16);
      server.answer = (_, _, _) =>
          (500, {'code': 'internal', 'status': 500, 'title': 'no'});
      expect(await MediaLimits.of(account), MediaLimits.mesh);
    });
  });

  group('watching through the media server', () {
    late FakeServer server;
    late TogetherHub hub;
    late FakeShareEngine engine;
    late List<FakeShareRoom> rooms;
    late Map<String, dynamic> joinAnswer;
    late int fresh;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      server = FakeServer();
      rooms = [];
      fresh = 0;
      joinAnswer = {
        'sharePlay': {...view(), 'media': 'sfu', 'maxViewers': 12},
        'iceServers': [],
        'expiresAt': null,
        'sfu': access('share-sp1'),
      };
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/share-play') => (
          200,
          {'hosting': null, 'watching': null, 'invites': []},
        ),
        ('POST', '/api/v1/share-plays/sp1/join') => (201, joinAnswer),
        ('GET', '/api/v1/share-plays/sp1/sfu') => (
          200,
          access('share-sp1', token: 'jwt-fresh-${++fresh}'),
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(
        account: await server.account(),
        shareEngine: () => engine = FakeShareEngine(),
        shareSound: FakeSound.new,
        shareRoom: () {
          final room = FakeShareRoom();
          rooms.add(room);
          return room;
        },
      );
      await until(() => server.sockets.isNotEmpty);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    SharePlays plays() => hub.sharePlays;
    List<Map<String, dynamic>> signals() => server.sent('signal');

    Map<String, dynamic> updated({int? slot, String media = 'sfu'}) => {
      ...view(slot: slot),
      'media': media,
      'maxViewers': 12,
    };

    void push(String kind, Object? data) => server.push('share_play.signal', {
      'sharePlayId': 'sp1',
      'from': 'host',
      'device': 'mac-1',
      'kind': kind,
      'data': data,
    }, id: '${DateTime.now().microsecondsSinceEpoch}-s');

    test(
      'only watching: the room from the join answer, and no signals at all',
      () async {
        await plays().watch('sp1');
        await until(() => rooms.isNotEmpty && rooms.single.joined != null);
        final room = rooms.single;
        expect(room.joined!.token, 'jwt-1');
        expect(room.host, 'host');
        expect(plays().viaServer, isTrue);
        expect(plays().status, WatchStatus.connecting);
        room.become('connected');
        expect(plays().status, WatchStatus.watching);
        // An offer the host sends anyway is not taken.
        push('offer', offer);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(signals(), isEmpty);
        expect(engine.links, isEmpty);
        expect(
          server.requests.any((r) => r.$2.endsWith('/sfu')),
          isFalse,
          reason: 'the join answer had the room',
        );
      },
    );

    test('the quality line comes from the room', () async {
      await plays().watch('sp1');
      await until(() => rooms.isNotEmpty);
      rooms.single.become('connected');
      await until(() => plays().quality.framesPerSecond == 60);
      expect(plays().quality.roundTripMs, 30);
    });

    test(
      'a pad handed over goes to the host; taken back, back to the room',
      () async {
        await plays().watch('sp1');
        await until(() => rooms.isNotEmpty && rooms.single.joined != null);
        server.push('share_play.updated', updated(slot: 2));
        await until(() => rooms.single.left);
        expect(plays().viaServer, isFalse);
        await until(() => signals().any((s) => s['kind'] == 'renegotiate'));
        push('offer', offer);
        await until(() => signals().any((s) => s['kind'] == 'answer'));
        final link = engine.links.single;
        link.connect();
        expect(plays().status, WatchStatus.watching);
        expect(plays().slot, 2);

        server.push('share_play.updated', updated(slot: null));
        await until(() => rooms.length == 2 && rooms.last.joined != null);
        expect(link.closed, isTrue);
        expect(signals().last['kind'], 'bye');
        expect(plays().viaServer, isTrue);
        expect(plays().status, WatchStatus.connecting);
        // The token from joining still works, so it is used again.
        expect(rooms.last.joined!.token, 'jwt-1');
      },
    );

    test(
      'a share play that turns "sfu" mid-way moves a watcher to the room',
      () async {
        joinAnswer = {
          'sharePlay': view(),
          'iceServers': [],
          'expiresAt': null,
          'sfu': null,
        };
        await plays().watch('sp1');
        await until(() => signals().any((s) => s['kind'] == 'renegotiate'));
        push('offer', offer);
        await until(() => signals().any((s) => s['kind'] == 'answer'));
        final link = engine.links.single..connect();
        expect(rooms, isEmpty);

        server.push('share_play.updated', updated());
        await until(() => rooms.isNotEmpty && rooms.single.joined != null);
        expect(link.closed, isTrue);
        expect(signals().last['kind'], 'bye');
        expect(rooms.single.joined!.token, 'jwt-fresh-1');
        expect(
          server.requests.where((r) => r.$2 == '/api/v1/share-plays/sp1/sfu'),
          hasLength(1),
        );
      },
    );

    test('a pad holder on an "sfu" share play stays on the mesh', () async {
      joinAnswer = {
        ...joinAnswer,
        'sharePlay': {...view(slot: 3), 'media': 'sfu', 'maxViewers': 12},
      };
      await plays().watch('sp1');
      await until(() => signals().any((s) => s['kind'] == 'renegotiate'));
      expect(rooms, isEmpty);
      // Updates that change nothing leave it there.
      server.push('share_play.updated', updated(slot: 3));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rooms, isEmpty);
    });

    test('a room that is lost is joined again with a fresh token', () async {
      await plays().watch('sp1');
      await until(() => rooms.isNotEmpty);
      rooms.single.become('connected');
      rooms.single.become('failed');
      await until(() => rooms.length == 2 && rooms.last.joined != null);
      expect(rooms.first.left, isTrue);
      expect(rooms.last.joined!.token, 'jwt-fresh-1');
      expect(plays().status, WatchStatus.connecting);
    });

    test('leaving and the host stopping leave the room', () async {
      await plays().watch('sp1');
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      await plays().leave();
      expect(rooms.single.left, isTrue);
      expect(signals(), isEmpty, reason: 'no bye: there was no connection');
      expect(
        server.requests.map((r) => r.$2),
        contains('/api/v1/share-plays/sp1/leave'),
      );

      await plays().watch('sp1');
      await until(() => rooms.length == 2 && rooms.last.joined != null);
      server.push('share_play.ended', {
        'sharePlayId': 'sp1',
        'reason': 'stopped',
      });
      await until(() => rooms.last.left);
      expect(plays().status, WatchStatus.ended);
    });

    test('the mesh is as before when the share play is not "sfu"', () async {
      joinAnswer = {'sharePlay': view(), 'iceServers': [], 'expiresAt': null};
      await plays().watch('sp1');
      await until(() => signals().isNotEmpty);
      expect(signals().first['kind'], 'renegotiate');
      push('offer', offer);
      await until(() => engine.links.isNotEmpty);
      expect(engine.links.single, isA<FakeShareLink>());
      expect(rooms, isEmpty);
      expect(plays().viaServer, isFalse);
    });
  });

  group('party voice through the media server', () {
    late FakeServer server;
    late TogetherHub hub;
    late FakeEngine engine;
    late List<FakeVoiceRoom> rooms;
    late Map<String, dynamic> callAnswer;
    late Map<String, dynamic> partyJson;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      server = FakeServer();
      rooms = [];
      partyJson = {
        ...party('p1', ['me', 'ece', 'can']),
        'max': 24,
      };
      callAnswer = {
        'call': {
          'id': 'call1',
          'kind': 'party',
          'partyId': 'p1',
          'media': 'mesh',
          'in': [
            {'userId': 'ece', 'device': 'dev-ece'},
            {'userId': 'me', 'device': 'device-1'},
          ],
        },
        'iceServers': [],
        'expiresAt': null,
        'sfu': null,
      };
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/party') => (
          200,
          {'party': partyJson, 'invites': []},
        ),
        ('POST', '/api/v1/calls') => (201, callAnswer),
        ('GET', '/api/v1/calls/call1/sfu') => (
          200,
          access('call-call1', token: 'jwt-call'),
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(
        account: await server.account(),
        voiceEngine: () => engine = FakeEngine(),
        voiceRoom: () {
          final room = FakeVoiceRoom();
          rooms.add(room);
          return room;
        },
      );
      await until(() => hub.parties.party != null);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Voice voice() => hub.voice;

    test('the party says how many it may hold', () {
      expect(hub.parties.party!.max, 24);
    });

    test('a call already on the media server: the room, no mesh', () async {
      callAnswer = {
        ...callAnswer,
        'call': {...callAnswer['call'] as Map<String, dynamic>, 'media': 'sfu'},
        'sfu': access('call-call1'),
      };
      voice().setMuted(true);
      await voice().join();
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      expect(voice().active, isTrue);
      expect(rooms.single.joined!.room, 'call-call1');
      expect(rooms.single.joinedTalking, isFalse, reason: 'muted before');
      expect(rooms.single.joinedHearing, isTrue);
      expect(engine.links, isEmpty);
      expect(engine.stopped, isTrue, reason: 'the room has its own mic');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.sent('signal'), isEmpty);
    });

    test(
      'the call moving to the media server closes the mesh and joins the room',
      () async {
        await voice().join();
        await until(() => engine.links.length == 1);
        server.push('call.media', {
          'callId': 'call1',
          'partyId': 'p1',
          'media': 'sfu',
        });
        await until(() => rooms.isNotEmpty && rooms.single.joined != null);
        expect(engine.links.single.closed, isTrue);
        expect(server.sent('signal').last['kind'], 'bye');
        expect(rooms.single.joined!.token, 'jwt-call');
        expect(voice().active, isTrue);
        expect(voice().callId, 'call1');
        expect(hub.parties.party!.callMedia, MediaRoute.sfu);
        // Mesh signals for the call are not answered any more.
        final before = server.sent('signal').length;
        server.push('signal', {
          'call': 'call1',
          'from': 'can',
          'device': 'dev-can',
          'kind': 'offer',
          'data': {'type': 'offer', 'sdp': 'v=0'},
        }, id: '30-a');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(server.sent('signal'), hasLength(before));
        expect(engine.links, hasLength(1));
        // Asked once, even though the party view says it too.
        expect(
          server.requests.where((r) => r.$2 == '/api/v1/calls/call1/sfu'),
          hasLength(1),
        );
      },
    );

    test('mute and deafen reach the room and still go to the server', () async {
      await voice().join();
      server.push('call.media', {
        'callId': 'call1',
        'partyId': 'p1',
        'media': 'sfu',
      });
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      final room = rooms.single;
      voice().setMuted(true);
      expect(room.talking, isFalse);
      expect(room.hearing, isTrue);
      voice().setDeafened(true);
      expect(room.hearing, isFalse);
      await until(
        () =>
            server.requests
                .where((r) => r.$2 == '/api/v1/calls/call1/mute')
                .lastOrNull
                ?.$3?['deafened'] ==
            true,
      );
      voice().setMuted(false);
      expect(room.talking, isTrue);
      expect(room.hearing, isTrue);
    });

    test('speaking comes from the room', () async {
      await voice().join();
      server.push('call.media', {
        'callId': 'call1',
        'partyId': 'p1',
        'media': 'sfu',
      });
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      rooms.single
        ..peers = const [PeerVoice('ece', 'connected', true)]
        ..speaking = true;
      rooms.single.changed!();
      expect(voice().speakingOf('ece'), isTrue);
      expect(voice().speaking, isTrue);
    });

    test('leaving leaves the room and tells the server', () async {
      await voice().join();
      server.push('call.media', {
        'callId': 'call1',
        'partyId': 'p1',
        'media': 'sfu',
      });
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      await voice().leave();
      expect(rooms.single.left, isTrue);
      expect(voice().active, isFalse);
      expect(server.requests.last.$2, '/api/v1/calls/call1/leave');
    });

    test('the call ending leaves the room', () async {
      await voice().join();
      server.push('call.media', {
        'callId': 'call1',
        'partyId': 'p1',
        'media': 'sfu',
      });
      await until(() => rooms.isNotEmpty && rooms.single.joined != null);
      server.push('call.ended', {
        'callId': 'call1',
        'partyId': 'p1',
        'reason': 'ended',
      });
      await until(() => rooms.single.left);
      expect(voice().active, isFalse);
    });

    test('another call moving is not this one', () async {
      await voice().join();
      server.push('call.media', {
        'callId': 'other',
        'partyId': 'p2',
        'media': 'sfu',
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(rooms, isEmpty);
      expect(engine.links.single.closed, isFalse);
    });
  });
}
