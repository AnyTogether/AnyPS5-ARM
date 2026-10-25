import 'dart:io';

import 'package:anyps5_remote/together/activity.dart';
import 'package:anyps5_remote/together/leaderboards.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/feed_view.dart';
import 'package:anyps5_remote/ui/leaderboard_view.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_server.dart';

String itemId(int n) =>
    '0190a000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> item(
  int n, {
  String kind = 'trophy',
  int trophyCount = 1,
  Map<String, int> counts = const {},
  String? mine,
  DateTime? at,
}) => {
  'id': itemId(n),
  'kind': kind,
  'createdAt': (at ?? DateTime.now().subtract(Duration(minutes: n)))
      .toUtc()
      .toIso8601String(),
  'actor': card('ece', name: 'Ece'),
  'game': {
    'titleId': 'PPSA01234',
    'names': {'en': 'Astro Bot'},
    'iconUrl': null,
  },
  'highlight': null,
  'trophies': [
    {
      'trophyId': 3,
      'grade': 'gold',
      'hidden': false,
      'texts': {
        'en': {'name': 'Speedrunner'},
      },
      'rarity': 0.12,
      'rarityLabel': 'rare',
    },
  ],
  'trophyCount': trophyCount,
  'reactions': {'counts': counts, 'mine': mine},
};

Map<String, dynamic> board({
  String name = 'points',
  String scope = 'friends',
  int? rank = 2,
  bool listed = true,
  List<Map<String, dynamic>>? around,
}) => {
  'board': name,
  'scope': scope,
  'game': null,
  'entries': [
    {'rank': 1, 'user': card('ece', name: 'Ece'), 'value': 12450},
    {'rank': 2, 'user': card('me', name: 'Utku'), 'value': 9030},
    {'rank': 3, 'user': card('ali', name: 'Ali'), 'value': 400},
  ],
  'me': {'rank': rank, 'value': 9030, 'listed': listed},
  'around': around ?? const [],
  'total': 3,
  'updatedAt': '2026-10-24T10:00:00Z',
};

class FakeBoards extends Leaderboards {
  FakeBoards(super.account);

  final asked = <String>[];

  @override
  Future<Leaderboard> overall(BoardScope scope) async {
    asked.add('overall ${scope.name}');
    return Leaderboard.fromJson(board(scope: scope.name));
  }

  @override
  Future<Leaderboard> game(
    String titleId,
    BoardKind kind,
    BoardScope scope,
  ) async {
    asked.add('$titleId ${kind.name} ${scope.name}');
    return Leaderboard.fromJson(board(name: kind.name, scope: scope.name));
  }

  @override
  Future<List<BoardGame>> games() async => [
    BoardGame.fromJson({
      'titleId': 'PPSA01234',
      'names': {'en': 'Astro Bot'},
      'iconUrl': null,
      'players': 1200,
      'mine': true,
    }),
    BoardGame.fromJson({
      'titleId': 'PPSA05678',
      'names': {'en': 'Stray'},
      'iconUrl': null,
      'players': 900,
      'mine': false,
    }),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the feed', () {
    late FakeServer server;
    late TogetherHub hub;
    var reactionStatus = 200;

    setUp(() async {
      HttpOverrides.global = null;
      reactionStatus = 200;
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/me/feed?limit=30') => (
          200,
          {
            'items': [
              item(1),
              item(2, counts: {'clap': 1}),
            ],
            'next': itemId(2),
          },
        ),
        ('GET', final p)
            when p.startsWith('/api/v1/me/feed?limit=30&before=') =>
          (
            200,
            {
              'items': [item(2), item(3)],
              'next': null,
            },
          ),
        (
          'PUT',
          '/api/v1/activities/0190a000-0000-7000-8000-000000000001/reaction',
        ) =>
          reactionStatus == 200
              ? (
                  200,
                  {
                    'counts': {'fire': 4},
                    'mine': 'fire',
                  },
                )
              : (
                  404,
                  {'code': 'not_found', 'status': 404, 'title': 'No such item'},
                ),
        ('DELETE', _) => (200, {'counts': <String, int>{}, 'mine': null}),
        _ => (200, const <String, dynamic>{}),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
      await until(() => hub.socket.session != null);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    test('a page, then older ones without the same item twice', () async {
      await hub.feed.refresh();
      expect(hub.feed.items.map((i) => i.id), [itemId(1), itemId(2)]);
      expect(hub.feed.items[1].reactions.counts, {Reaction.clap: 1});
      await hub.feed.older();
      expect(hub.feed.items.map((i) => i.id), [
        itemId(1),
        itemId(2),
        itemId(3),
      ]);
      expect(hub.feed.next, isNull);
    });

    test('a live item replaces the one with its id, or goes on top', () async {
      await hub.feed.refresh();
      server.push('feed.item', item(2, trophyCount: 4));
      await until(() => hub.feed.items[1].trophyCount == 4);
      expect(hub.feed.items.length, 2);
      expect(hub.feed.unseen, 0);
      server.push('feed.item', item(9, at: DateTime.now()));
      await until(() => hub.feed.items.length == 3);
      expect(hub.feed.items.first.id, itemId(9));
      expect(hub.feed.unseen, 1);
      hub.feed.watch(true);
      expect(hub.feed.unseen, 0);
      server.push('feed.item', item(10, at: DateTime.now()));
      await until(() => hub.feed.items.length == 4);
      expect(hub.feed.unseen, 0);
    });

    test('a reaction shows at once and settles with the server', () async {
      await hub.feed.refresh();
      final pending = hub.feed.react(itemId(1), Reaction.fire);
      expect(hub.feed.items.first.reactions.mine, Reaction.fire);
      expect(hub.feed.items.first.reactions.counts, {Reaction.fire: 1});
      await pending;
      expect(server.requests.last.$3, {'reaction': 'fire'});
      expect(hub.feed.items.first.reactions.counts, {Reaction.fire: 4});
      await hub.feed.react(itemId(1), null);
      expect(server.requests.last.$1, 'DELETE');
      expect(hub.feed.items.first.reactions.mine, isNull);
    });

    test('a reaction the server refuses is put back', () async {
      await hub.feed.refresh();
      reactionStatus = 404;
      await expectLater(
        hub.feed.react(itemId(1), Reaction.fire),
        throwsA(isA<TogetherProblem>()),
      );
      expect(hub.feed.items.first.reactions.mine, isNull);
      expect(hub.feed.items.first.reactions.counts, isEmpty);
    });

    test('a changed reaction moves the count', () {
      const before = Reactions(
        counts: {Reaction.fire: 2, Reaction.clap: 1},
        mine: Reaction.clap,
      );
      final after = before.picked(Reaction.heart);
      expect(after.counts, {Reaction.fire: 2, Reaction.heart: 1});
      expect(after.mine, Reaction.heart);
    });
  });

  test('a board, and the reader left out of a global one', () {
    final shown = Leaderboard.fromJson(
      board(
        scope: 'global',
        rank: 140,
        listed: false,
        around: [
          {'rank': 139, 'user': card('x'), 'value': 9100},
        ],
      ),
    );
    expect(shown.scope, BoardScope.global);
    expect(shown.entries.first.person.displayName, 'Ece');
    expect(shown.myRank, 140);
    expect(shown.listed, isFalse);
    expect(shown.around.single.rank, 139);
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

    testWidgets('the feed with its reactions fits', (tester) async {
      sideways(tester);
      hub.feed
        ..items = [
          Activity.fromJson(item(1, counts: {'fire': 2}, mine: 'fire'))!,
          Activity.fromJson(item(2, kind: 'long_session')..['seconds'] = 9000)!,
        ]
        ..loaded = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedPane(hub: hub)),
        ),
      );
      await tester.pump();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(find.text('Activity'), findsOneWidget);
      expect(
        find.textContaining(
          'Ece earned Speedrunner in Astro Bot',
          findRichText: true,
        ),
        findsWidgets,
      );
      expect(
        find.textContaining('Ece played Astro Bot for', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('2 h 30 min', findRichText: true),
        findsWidgets,
      );
      final box = tester.getRect(find.text('🔥').first);
      expect(box.bottom, lessThanOrEqualTo(screen.height));
      expect(box.right, lessThanOrEqualTo(screen.width));
      expect(find.text('12%'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a board shows your rank, and friends or global', (
      tester,
    ) async {
      sideways(tester);
      final boards = FakeBoards(hub.account);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeaderboardPane(hub: hub, boards: boards),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in ['All games', 'Astro Bot', '#2 of 3', '12,450 pts']) {
        final box = tester.getRect(find.text(text).first);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
        expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
      }
      expect(find.text('YOUR GAMES'), findsOneWidget);
      expect(find.text('MOST PLAYED'), findsOneWidget);
      await tester.tap(find.text('Global'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Astro Bot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      expect(boards.asked, [
        'overall friends',
        'overall global',
        'PPSA01234 points global',
        'PPSA01234 time global',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'opening on the feed marks it seen after the frame, not in it',
      (tester) async {
        sideways(tester);
        hub.feed.unseen = 3;
        await tester.pumpWidget(
          MaterialApp(
            home: TogetherScreen(hub: hub, tab: TogetherTab.feed),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(hub.feed.unseen, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('every part of the rail stays on the screen', (tester) async {
      sideways(tester);
      await tester.pumpWidget(MaterialApp(home: TogetherScreen(hub: hub)));
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final text in [
        'Friends',
        'Activity',
        'Messages',
        'Party',
        'Find players',
        'Leaderboards',
      ]) {
        final box = tester.getRect(find.text(text).first);
        expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
      }
      await tester.tap(find.text('Leaderboards'));
      await tester.pumpAndSettle();
      expect(find.text('All games'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
