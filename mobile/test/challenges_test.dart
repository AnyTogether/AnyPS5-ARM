import 'dart:io';

import 'package:anyps5_remote/social_strings.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/challenges.dart';
import 'package:anyps5_remote/together/leaderboards.dart';
import 'package:anyps5_remote/together/notifications.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/challenge_view.dart';
import 'package:anyps5_remote/ui/leaderboard_view.dart';
import 'package:anyps5_remote/ui/notifications_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feed_test.dart' show FakeBoards;
import 'notifications_test.dart' show note;
import 'support/fake_server.dart';

const challengeId = '0190c000-0000-7000-8000-000000000001';

/// A challenge as the API answers it, with a field this app does not know yet.
Map<String, dynamic> challenge({
  String id = challengeId,
  String title = 'Silksong sprint',
  String metric = 'points',
  String state = 'active',
  bool joined = true,
  bool mine = false,
  bool isFinal = false,
  Duration startsIn = const Duration(days: -1),
  Duration endsIn = const Duration(days: 2, hours: 3),
  Map<String, dynamic>? leader,
  Map<String, dynamic>? myStanding = const {'rank': 2, 'value': 315},
  Object? creator = const {
    'userId': 'ece',
    'handle': 'ece',
    'displayName': 'Ece',
    'avatar': null,
  },
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'title': title,
    'description': 'Most points by Sunday.',
    'game': {
      'titleId': 'PPSA01234',
      'names': {'en': 'Astro Bot', 'tr': 'Astro Bot'},
      'iconUrl': null,
    },
    'metric': metric,
    'audience': 'friends',
    'community': null,
    'creator': creator,
    'startsAt': now.add(startsIn).toUtc().toIso8601String(),
    'endsAt': now.add(endsIn).toUtc().toIso8601String(),
    'state': state,
    'final': isFinal,
    'entrants': 12,
    'joined': joined,
    'mine': mine,
    'canCancel': mine,
    'leader':
        leader ??
        {
          'rank': 1,
          'user': card('ece', name: 'Ece'),
          'value': 1230,
          'me': false,
        },
    'myStanding': myStanding,
    'createdAt': now.toUtc().toIso8601String(),
    'prize': {'kind': 'badge'},
  };
}

Map<String, dynamic> detailJson({
  String state = 'active',
  bool joined = true,
  bool isFinal = false,
  bool mine = false,
}) => {
  ...challenge(state: state, joined: joined, isFinal: isFinal, mine: mine),
  'standings': [
    {'rank': 1, 'user': card('ece', name: 'Ece'), 'value': 1230, 'me': false},
    {'rank': 2, 'user': card('me', name: 'Utku'), 'value': 315, 'me': true},
    {'rank': 2, 'user': null, 'value': 315, 'me': false},
    {'rank': 4, 'user': card('ali', name: 'Ali'), 'value': 0, 'me': false},
  ],
  'around': const [],
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
};

class FakeChallenges extends Challenges {
  FakeChallenges(
    super.account, {
    this.listed = const [],
    this.failure,
    Map<String, dynamic>? shown,
  }) : shown = shown ?? detailJson();

  List<Map<String, dynamic>> listed;
  Map<String, dynamic> shown;
  Object? failure;
  final asked = <String>[];

  @override
  Future<List<ChallengeView>> forGame(String titleId) async {
    asked.add('game $titleId');
    if (failure case final failure?) throw failure;
    return [for (final c in listed) ?ChallengeView.fromJson(c)];
  }

  @override
  Future<List<ChallengeView>> mine() async {
    asked.add('mine');
    if (failure case final failure?) throw failure;
    return [for (final c in listed) ?ChallengeView.fromJson(c)];
  }

  @override
  Future<ChallengeDetail> detail(String id) async {
    asked.add('detail $id');
    return ChallengeDetail.fromJson(shown);
  }

  @override
  Future<ChallengeView> join(String id) async {
    asked.add('join $id');
    shown = {...shown, 'joined': true, 'entrants': 13};
    return ChallengeView.fromJson(shown)!;
  }

  @override
  Future<ChallengeView> leave(String id) async {
    asked.add('leave $id');
    shown = {...shown, 'joined': false, 'entrants': 11, 'myStanding': null};
    return ChallengeView.fromJson(shown)!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a challenge as the API sends it', () {
    test('reads every field, and skips the ones it does not know', () {
      final view = ChallengeView.fromJson(challenge())!;
      expect(view.id, challengeId);
      expect(view.title, 'Silksong sprint');
      expect(view.description, 'Most points by Sunday.');
      expect(view.game.name('en'), 'Astro Bot');
      expect(view.metric, ChallengeMetric.points);
      expect(view.audience, ChallengeAudience.friends);
      expect(view.creator?.displayName, 'Ece');
      expect(view.state, ChallengeState.active);
      expect(view.entrants, 12);
      expect(view.joined, isTrue);
      expect(view.leader?.person?.displayName, 'Ece');
      expect(view.leader?.value, 1230);
      expect(view.myRank, 2);
      expect(view.myValue, 315);
    });

    test('a hidden player, a gone maker and no place yet', () {
      final view = ChallengeView.fromJson(
        challenge(
          creator: null,
          myStanding: null,
          leader: {'rank': 1, 'user': null, 'value': 90, 'me': false},
        ),
      )!;
      expect(view.creator, isNull);
      expect(view.leader?.person, isNull);
      expect(view.leader?.value, 90);
      expect(view.myRank, isNull);
    });

    test('a metric or state from a newer server', () {
      expect(ChallengeView.fromJson(challenge(metric: 'speedruns')), isNull);
      expect(ChallengeView.fromJson({'id': challengeId}), isNull);
      final later = ChallengeView.fromJson(challenge(state: 'paused'))!;
      // Read from its window instead.
      expect(later.state, ChallengeState.active);
    });

    test('the detail: standings with shared ranks and a hidden player', () {
      final shown = ChallengeDetail.fromJson({
        ...detailJson(),
        'around': [
          {'rank': 140, 'user': card('me'), 'value': 3, 'me': true},
          {
            'rank': 141,
            'user': {'weird': true},
            'value': 2,
            'me': false,
          },
        ],
      });
      expect(shown.view.title, 'Silksong sprint');
      expect(shown.standings.map((s) => s.rank), [1, 2, 2, 4]);
      expect(shown.standings[1].me, isTrue);
      expect(shown.standings[2].person, isNull);
      expect(shown.around.first.rank, 140);
      expect(shown.around.last.person, isNull);
      expect(shown.updatedAt, isNotNull);
    });

    test('how far the window has gone', () {
      final now = DateTime.utc(2026, 11, 6, 12);
      final view = ChallengeView.fromJson({
        ...challenge(),
        'startsAt': '2026-11-06T10:00:00Z',
        'endsAt': '2026-11-06T14:00:00Z',
      })!;
      expect(view.progress(now), 0.5);
      expect(view.progress(DateTime.utc(2026, 11, 6, 9)), 0);
      expect(view.progress(DateTime.utc(2026, 11, 7)), 1);
    });
  });

  group('the challenges on the server', () {
    late FakeServer server;
    late Challenges challenges;
    var status = 200;

    setUp(() async {
      HttpOverrides.global = null;
      status = 200;
      server = FakeServer();
      server.answer = (method, path, body) => status == 404
          ? (404, {'code': 'not_found', 'status': 404, 'title': 'Not found'})
          : switch ((method, path)) {
              ('GET', '/api/v1/challenges?titleId=PPSA01234') => (
                200,
                {
                  'challenges': [challenge(), challenge(metric: 'future')],
                },
              ),
              ('GET', '/api/v1/me/challenges') => (
                200,
                {
                  'challenges': [challenge()],
                },
              ),
              ('GET', '/api/v1/challenges/$challengeId') => (200, detailJson()),
              ('POST', '/api/v1/challenges/$challengeId/join') => (
                200,
                challenge(),
              ),
              ('POST', '/api/v1/challenges/$challengeId/leave') => (
                409,
                {'code': 'conflict', 'status': 409, 'title': 'The maker'},
              ),
              _ => (404, {'code': 'not_found', 'status': 404, 'title': 'no'}),
            };
      await server.start();
      challenges = Challenges(await server.account());
    });

    tearDown(() => server.stop());

    test('a game\'s, the reader\'s own, one, and joining', () async {
      expect((await challenges.forGame('PPSA01234')).single.id, challengeId);
      expect((await challenges.mine()).single.title, 'Silksong sprint');
      expect((await challenges.detail(challengeId)).standings, hasLength(4));
      expect((await challenges.join(challengeId)).joined, isTrue);
      await expectLater(
        challenges.leave(challengeId),
        throwsA(
          isA<TogetherProblem>().having((p) => p.code, 'code', 'conflict'),
        ),
      );
      expect(server.requests.map((r) => '${r.$1} ${r.$2}'), [
        'GET /api/v1/challenges?titleId=PPSA01234',
        'GET /api/v1/me/challenges',
        'GET /api/v1/challenges/$challengeId',
        'POST /api/v1/challenges/$challengeId/join',
        'POST /api/v1/challenges/$challengeId/leave',
      ]);
      expect(server.requests[3].$3, <String, dynamic>{});
    });

    test('a server without challenges answers 404: there are none', () async {
      status = 404;
      expect(await challenges.forGame('PPSA01234'), isEmpty);
      expect(await challenges.mine(), isEmpty);
    });
  });

  group('the words', () {
    final en = Strings.english;
    final tr = Strings.turkish;
    final now = DateTime.utc(2026, 11, 6, 12);

    ChallengeView at(
      String startsAt,
      String endsAt, {
      String state = 'active',
    }) => ChallengeView.fromJson({
      ...challenge(state: state),
      'startsAt': startsAt,
      'endsAt': endsAt,
    })!;

    test('time left, or till it starts', () {
      final running = at('2026-11-05T12:00:00Z', '2026-11-08T13:00:00Z');
      expect(en.challengeWhen(running, now: now), 'Ends in 2 days');
      expect(tr.challengeWhen(running, now: now), '2 gün sonra bitiyor');
      final soon = at('2026-11-05T12:00:00Z', '2026-11-07T15:00:00Z');
      expect(en.challengeWhen(soon, now: now), 'Ends in 1 day');
      final hours = at('2026-11-05T12:00:00Z', '2026-11-06T17:30:00Z');
      expect(en.challengeWhen(hours, now: now), 'Ends in 5 h');
      final minutes = at('2026-11-05T12:00:00Z', '2026-11-06T12:45:00Z');
      expect(en.challengeWhen(minutes, now: now), 'Ends in 45 min');
      expect(tr.challengeWhen(minutes, now: now), '45 dk sonra bitiyor');
      final coming = at(
        '2026-11-06T15:00:00Z',
        '2026-11-09T15:00:00Z',
        state: 'upcoming',
      );
      expect(en.challengeWhen(coming, now: now), 'Starts in 3 h');
      expect(tr.challengeWhen(coming, now: now), '3 sa sonra başlıyor');
      final over = at(
        '2026-11-01T12:00:00Z',
        '2026-11-05T12:00:00Z',
        state: 'ended',
      );
      expect(en.challengeWhen(over, now: now), 'Ended yesterday');
      expect(tr.challengeWhen(over, now: now), 'Bitti, dün');
      final off = at(
        '2026-11-01T12:00:00Z',
        '2026-11-09T12:00:00Z',
        state: 'cancelled',
      );
      expect(en.challengeWhen(off, now: now), 'Called off');
    });

    test('what counts, and its values', () {
      expect(en.challengeMetric(ChallengeMetric.points), 'Trophy points');
      expect(tr.challengeMetric(ChallengeMetric.points), 'Kupa puanı');
      expect(tr.challengeMetric(ChallengeMetric.trophies), 'Kupalar');
      expect(tr.challengeMetric(ChallengeMetric.time), 'Oynama süresi');
      expect(en.challengeValue(ChallengeMetric.points, 1230), '1,230 pts');
      expect(en.challengeValue(ChallengeMetric.trophies, 1), '1 trophy');
      expect(en.challengeValue(ChallengeMetric.trophies, 7), '7 trophies');
      expect(
        en.challengeValue(ChallengeMetric.time, 7 * 3600 + 120),
        en.boardValue(BoardKind.time, 7 * 3600 + 120),
      );
      expect(en.challengeEntrants(12), '12 in it');
      expect(tr.challengeEntrants(12), '12 kişi katıldı');
      expect(tr.hiddenPlayer, 'Gizli oyuncu');
      expect(tr.joinChallenge, 'Katıl');
      expect(tr.leaveChallenge, 'Ayrıl');
      expect(tr.challengeWinner, 'Kazanan');
      expect(tr.challengeLeading, 'Önde');
      expect(tr.yourPlace, 'Senin yerin');
      expect(tr.challenges, 'Meydan okumalar');
    });

    test('the three notifications', () {
      final data = {
        'challengeId': challengeId,
        'title': 'Silksong sprint',
        'titleId': 'PPSA01234',
        'gameNames': {'en': 'Astro Bot'},
        'metric': 'points',
        'endsAt': '2026-11-08T12:00:00Z',
      };
      final invite = Notice.fromJson(note(1, 'challenge_invite', data: data))!;
      final started = Notice.fromJson(
        note(2, 'challenge_started', data: data),
      )!;
      final won = Notice.fromJson(
        note(
          3,
          'challenge_ended',
          actor: false,
          data: {
            ...data,
            'rank': 1,
            'value': 1230,
            'entrants': 12,
            'winner': {'displayName': 'Utku', 'handle': 'utku', 'value': 1230},
          },
        ),
      )!;
      final lost = Notice.fromJson(
        note(
          4,
          'challenge_ended',
          actor: false,
          data: {
            ...data,
            'rank': 3,
            'value': 90,
            'entrants': 12,
            'winner': {'displayName': 'Ece', 'handle': 'ece', 'value': 1230},
          },
        ),
      )!;
      expect(invite.kind, NoticeKind.challengeInvite);
      expect(started.kind, NoticeKind.challengeStarted);
      expect(won.kind, NoticeKind.challengeEnded);
      expect(
        en.notice(invite),
        '{name} challenged you to Silksong sprint in Astro Bot.',
      );
      expect(en.notice(started), 'Silksong sprint has started in Astro Bot.');
      expect(en.notice(won), 'Silksong sprint in Astro Bot is over.');
      expect(tr.notice(won), 'Astro Bot oyunundaki Silksong sprint bitti.');
      expect(en.challengeResult(won), 'You won with 1,230 pts.');
      expect(
        en.challengeResult(lost),
        'Ece won with 1,230 pts. You came #3 of 12.',
      );
      expect(
        tr.challengeResult(lost),
        'Ece 1.230 puan ile kazandı. 12 kişi arasında 3. oldun.',
      );
      for (final kind in [
        NoticeKind.challengeInvite,
        NoticeKind.challengeStarted,
        NoticeKind.challengeEnded,
      ]) {
        expect(optionalNoticeKinds, contains(kind));
        expect(en.noticeKind(kind), isNot(startsWith('nk_')));
        expect(tr.noticeKind(kind), isNot(en.noticeKind(kind)));
      }
    });
  });

  group('on the phone held sideways', () {
    late TogetherHub hub;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      hub = TogetherHub(
        account: TogetherAccount(
          preferences: await SharedPreferences.getInstance(),
          clientName: 'test',
        ),
      );
    });

    tearDown(() => hub.dispose());

    void sideways(WidgetTester tester) {
      tester.view.physicalSize = const Size(2556, 1179);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> board(WidgetTester tester, FakeChallenges challenges) async {
      sideways(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeaderboardPane(
              hub: hub,
              boards: FakeBoards(hub.account),
              challenges: challenges,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the board shows the reader\'s challenges, then a game\'s', (
      tester,
    ) async {
      final challenges = FakeChallenges(hub.account, listed: [challenge()]);
      await board(tester, challenges);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in [
        'CHALLENGES',
        'Silksong sprint',
        'Ends in 2 days',
        '12 in it',
      ]) {
        final box = tester.getRect(find.text(text).first);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
      }
      expect(
        find.textContaining('Your place', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Ece', findRichText: true), findsWidgets);
      await tester.tap(find.text('Astro Bot').first);
      await tester.pumpAndSettle();
      expect(challenges.asked, ['mine', 'game PPSA01234']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('none, or a server without them: no section at all', (
      tester,
    ) async {
      final challenges = FakeChallenges(hub.account);
      await board(tester, challenges);
      expect(find.text('CHALLENGES'), findsNothing);
      expect(find.text('#2 of 3'), findsOneWidget);
      challenges
        ..listed = [challenge()]
        ..failure = const TogetherProblem(404, 'not_found', 'Not found');
      await tester.tap(find.text('Astro Bot').first);
      await tester.pumpAndSettle();
      expect(find.text('CHALLENGES'), findsNothing);
      expect(find.textContaining('Not found'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a challenge: standings, the hidden player, join and leave', (
      tester,
    ) async {
      sideways(tester);
      final challenges = FakeChallenges(
        hub.account,
        shown: detailJson(joined: false),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChallengePane(
              hub: hub,
              id: challengeId,
              challenges: challenges,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in [
        'Silksong sprint',
        'Hidden player',
        'Utku',
        'Join',
        'Joining shows your progress in this challenge to everyone who can see it.',
        'Make a challenge on the website',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.textContaining('Ece', findRichText: true), findsWidgets);
      expect(find.text('1,230 pts'), findsWidgets);
      await tester.ensureVisible(find.text('Join'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('Leave'), findsOneWidget);
      await tester.ensureVisible(find.text('Leave'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Join'), findsOneWidget);
      expect(challenges.asked, [
        'detail $challengeId',
        'join $challengeId',
        'detail $challengeId',
        'leave $challengeId',
        'detail $challengeId',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the maker cannot leave; a final one shows its winner', (
      tester,
    ) async {
      sideways(tester);
      final challenges = FakeChallenges(
        hub.account,
        shown: detailJson(state: 'ended', isFinal: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChallengePane(
              hub: hub,
              id: challengeId,
              challenges: challenges,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('WINNER'), findsOneWidget);
      expect(find.text('FINAL STANDINGS'), findsOneWidget);
      expect(find.text('Join'), findsNothing);
      expect(find.text('Leave'), findsNothing);
      challenges.shown = detailJson(mine: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChallengePane(
              key: const ValueKey('mine'),
              hub: hub,
              id: challengeId,
              challenges: challenges,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Leave'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a challenge notification reads well and leads to it', (
      tester,
    ) async {
      sideways(tester);
      hub.notifications
        ..items = [
          Notice.fromJson(
            note(
              1,
              'challenge_ended',
              actor: false,
              data: {
                'challengeId': challengeId,
                'title': 'Silksong sprint',
                'titleId': 'PPSA01234',
                'gameNames': {'en': 'Astro Bot'},
                'metric': 'points',
                'endsAt': '2026-11-08T12:00:00Z',
                'rank': 1,
                'value': 1230,
                'entrants': 12,
                'winner': null,
              },
            ),
          )!,
        ]
        ..unread = 1
        ..loaded = true;
      final opened = <Notice>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationsPane(hub: hub, onOpen: opened.add),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining(
          'Silksong sprint in Astro Bot is over.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('You won with 1,230 pts.'), findsOneWidget);
      expect(find.byIcon(Icons.gpp_maybe_rounded), findsNothing);
      await tester.tap(find.textContaining('is over', findRichText: true));
      await tester.pump();
      expect(challengeOf(opened.single), challengeId);
      expect(tester.takeException(), isNull);
    });
  });
}
