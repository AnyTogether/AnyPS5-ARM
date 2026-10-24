import 'dart:io';

import 'package:anyps5_remote/together/discover.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discover_data.dart';
import 'support/fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the API says, read', () {
    test(
      'a post, with the asker\'s own "I\'m in" and, for its poster, who asked',
      () {
        final post = LfgPost.fromJson(
          lfgPost(
            'l1',
            author: 'ece',
            purpose: 'coop',
            slots: 3,
            filled: 1,
            startsAt: '2026-10-25T20:00:00Z',
            note: 'mics on',
            myRequest: {
              'status': 'accepted',
              'invite': {'kind': 'share_play', 'id': 's1'},
            },
            requests: [
              {
                'user': card('ali'),
                'status': 'pending',
                'invite': null,
                'createdAt': '2026-10-25T18:00:00Z',
              },
            ],
          ),
        );
        expect(post.id, 'l1');
        expect(post.author.handle, 'ece');
        expect(post.game.name('en'), 'Astro Bot');
        expect(post.game.name('tr'), 'Astro Bot');
        expect(post.purpose, LfgPurpose.coop);
        expect(post.startsAt, DateTime.utc(2026, 10, 25, 20));
        expect(post.languages, ['en', 'tr']);
        expect(post.slots, 3);
        expect(post.filled, 1);
        expect(post.left, 2);
        expect(post.note, 'mics on');
        expect(post.status, LfgStatus.open);
        expect(post.myRequest?.status, LfgAnswer.accepted);
        expect(post.myRequest?.invite?.share, isTrue);
        expect(post.myRequest?.invite?.id, 's1');
        expect(post.requests.single.person.handle, 'ali');
        expect(post.requests.single.status, LfgAnswer.pending);
        expect(post.waiting, 1);
      },
    );

    test(
      'a post for a game the catalogue does not know shows its title ID',
      () {
        final post = LfgPost.fromJson(lfgPost('l1')..['game'] = null);
        expect(post.game.name('en'), 'PPSA01234');
        expect(post.startsAt, isNull);
        expect(post.myRequest, isNull);
        expect(post.requests, isEmpty);
      },
    );

    test('a public party and a public share play', () {
      final party = PublicParty.fromJson(publicParty('p1', join: 'request'));
      expect(party.host?.handle, 'ece');
      expect(party.game?.name('en'), 'Astro Bot');
      expect(party.join, PublicJoin.request);
      expect(party.size, 2);
      expect(party.max, 8);
      expect(party.full, isFalse);
      final bare = PublicParty.fromJson(
        publicParty('p2')
          ..['titleId'] = null
          ..['game'] = null,
      );
      expect(bare.game, isNull);
      final share = PublicShare.fromJson(publicShare('s1', viewers: 2));
      expect(share.join, PublicJoin.open);
      expect(share.live, isTrue);
      expect(share.viewers, 2);
      expect(share.maxViewers, 4);
      expect(share.full, isFalse);
      expect(share.name('en'), 'Astro Bot');
      expect(
        PublicShare.fromJson(
          publicShare('s2')
            ..['game'] = null
            ..['title'] = 'Stray',
        ).name('en'),
        'Stray',
      );
    });

    test('a suggestion and why', () {
      final suggestion = Suggestion.fromJson({
        'user': card('zeynep'),
        'friendship': 'none',
        'presence': {'state': 'in_game', 'titleId': 'PPSA01234'},
        'reasons': [
          {
            'kind': 'game',
            'titleId': 'PPSA01234',
            'names': {'en': 'Astro Bot'},
          },
          {'kind': 'friends', 'count': 3},
          {'kind': 'language', 'language': 'tr'},
          {'kind': 'something new'},
        ],
      });
      expect(suggestion.person.handle, 'zeynep');
      expect(suggestion.friendship, Friendship.none);
      expect(suggestion.presence?.titleId, 'PPSA01234');
      expect(suggestion.reasons, hasLength(3));
      expect(
        (suggestion.reasons[0] as GameReason).game.name('en'),
        'Astro Bot',
      );
      expect((suggestion.reasons[1] as FriendsReason).count, 3);
      expect((suggestion.reasons[2] as LanguageReason).language, 'tr');
    });

    test('the discovery setting', () {
      final setting = DiscoverySettings.fromJson({
        'discoverable': true,
        'chosen': null,
        'languages': ['tr', 'en'],
      });
      expect(setting.discoverable, isTrue);
      expect(setting.chosen, isNull);
      expect(setting.languages, ['tr', 'en']);
    });
  });

  group('a new post', () {
    final now = DateTime.utc(2026, 10, 25, 18);

    test('now, for three hours, as the API takes it', () {
      const draft = LfgDraft(
        titleId: 'PPSA01234',
        purpose: LfgPurpose.online,
        languages: ['tr'],
        slots: 3,
        note: '  chill  ',
      );
      expect(draft.issue, isNull);
      expect(draft.toJson(now), {
        'titleId': 'PPSA01234',
        'purpose': 'online',
        'languages': ['tr'],
        'slots': 3,
        'note': 'chill',
        'expiresAt': '2026-10-25T21:00:00.000Z',
      });
    });

    test('later, and never past a day from now', () {
      const draft = LfgDraft(
        titleId: 'PPSA01234',
        purpose: LfgPurpose.party,
        languages: ['en', 'tr'],
        slots: 7,
        startIn: Duration(hours: 4),
        hours: 24,
      );
      final json = draft.toJson(now);
      expect(json['startsAt'], '2026-10-25T22:00:00.000Z');
      expect(json['expiresAt'], '2026-10-26T18:00:00.000Z');
      expect(json.containsKey('note'), isFalse);
    });

    test('co-op has room for three more, the rest for seven', () {
      expect(LfgDraft.maxSlots(LfgPurpose.coop), 3);
      expect(LfgDraft.maxSlots(LfgPurpose.online), 7);
      expect(
        const LfgDraft(
          titleId: 'PPSA01234',
          purpose: LfgPurpose.coop,
          languages: ['en'],
          slots: 4,
        ).issue,
        LfgDraftIssue.slots,
      );
      expect(
        const LfgDraft(
          titleId: 'PPSA01234',
          purpose: LfgPurpose.coop,
          languages: ['en'],
          slots: 4,
        ).withPurpose(LfgPurpose.coop).slots,
        3,
      );
    });

    test('what the API would turn down is caught first', () {
      LfgDraft draft({
        String titleId = 'PPSA01234',
        List<String> languages = const ['en'],
        String note = '',
        int slots = 1,
      }) => LfgDraft(
        titleId: titleId,
        purpose: LfgPurpose.trophies,
        languages: languages,
        note: note,
        slots: slots,
      );
      expect(draft(titleId: 'stray').issue, LfgDraftIssue.game);
      expect(draft(languages: const []).issue, LfgDraftIssue.languages);
      expect(
        draft(languages: const ['en', 'tr', 'de', 'fr']).issue,
        LfgDraftIssue.languages,
      );
      expect(draft(note: 'x' * 141).issue, LfgDraftIssue.note);
      expect(draft(slots: 0).issue, LfgDraftIssue.slots);
      expect(draft().issue, isNull);
    });

    test('the board\'s filters as a query', () {
      expect(const LfgFilter().query(), 'lfg');
      expect(
        const LfgFilter(
          titleId: 'PPSA01234',
          purpose: LfgPurpose.coop,
          language: 'tr',
          now: true,
        ).query(before: 'l9'),
        'lfg?titleId=PPSA01234&purpose=coop&language=tr&now=1&before=l9',
      );
      expect(const LfgFilter(titleId: 'PPSA01234').topic, 'lfg:PPSA01234');
      expect(const LfgFilter().topic, 'lfg');
    });
  });

  group('finding players', () {
    late FakeServer server;
    late TogetherHub hub;
    late Map<String, dynamic> imIn;
    var boardPages = 0;

    setUp(() async {
      HttpOverrides.global = null;
      boardPages = 0;
      imIn = lfgPost('l1', myRequest: {'status': 'pending', 'invite': null});
      server = FakeServer();
      server.answer = (method, path, body) => switch ((method, path)) {
        ('GET', '/api/v1/lfg') ||
        ('GET', '/api/v1/lfg?titleId=PPSA01234') => () {
          boardPages++;
          return (
            200,
            {
              'posts': [lfgPost('l2'), lfgPost('l1')],
              'more': true,
            },
          );
        }(),
        ('GET', '/api/v1/lfg?before=l1') => (
          200,
          {
            'posts': [lfgPost('l1'), lfgPost('l0')],
            'more': false,
          },
        ),
        ('GET', '/api/v1/lfg/games') => (
          200,
          {
            'games': [
              {
                'titleId': 'PPSA01234',
                'posts': 4,
                'names': {'en': 'Astro Bot'},
                'iconUrl': null,
              },
            ],
          },
        ),
        ('GET', '/api/v1/me/lfg') => (
          200,
          {
            'posts': [
              lfgPost(
                'm1',
                author: 'me',
                mine: true,
                requests: [
                  {
                    'user': card('ali'),
                    'status': 'pending',
                    'invite': null,
                    'createdAt': '2026-10-25T18:00:00Z',
                  },
                ],
              ),
            ],
            'asked': [imIn],
          },
        ),
        ('POST', '/api/v1/lfg') => (
          201,
          lfgPost('m2', author: 'me', mine: true, requests: const []),
        ),
        ('POST', '/api/v1/lfg/l1/requests') => (201, imIn),
        ('POST', '/api/v1/lfg/m1/requests/ali/accept') => (
          200,
          lfgPost(
            'm1',
            author: 'me',
            mine: true,
            filled: 1,
            requests: [
              {
                'user': card('ali'),
                'status': 'accepted',
                'invite': {'kind': 'party', 'id': 'p1'},
                'createdAt': '2026-10-25T18:00:00Z',
              },
            ],
          ),
        ),
        ('GET', '/api/v1/share-plays/public?live=1') => (
          200,
          {
            'sharePlays': [publicShare('s1')],
          },
        ),
        ('GET', '/api/v1/parties/public') => (
          200,
          {
            'parties': [publicParty('p1', join: 'request')],
          },
        ),
        ('POST', '/api/v1/parties/p1/requests') => (201, {'requested': true}),
        ('POST', '/api/v1/share-plays/s1/requests') => (
          201,
          {'requested': true},
        ),
        ('GET', '/api/v1/me/discovery') => (
          200,
          {'discoverable': false, 'chosen': null, 'languages': <String>[]},
        ),
        ('PATCH', '/api/v1/me/discovery') => (
          200,
          {
            'discoverable': body?['discoverable'] ?? false,
            'chosen': body?['discoverable'],
            'languages': body?['languages'] ?? <String>[],
          },
        ),
        ('GET', '/api/v1/discover/suggestions') => (
          200,
          {
            'suggestions': [
              {
                'user': card('zeynep'),
                'friendship': 'none',
                'reasons': [
                  {'kind': 'friends', 'count': 2},
                ],
              },
            ],
          },
        ),
        ('GET', '/api/v1/users/utku/library') => (
          200,
          {
            'games': [
              {
                'titleId': 'PPSA01234',
                'names': {'en': 'Astro Bot'},
                'iconUrl': null,
                'lastPlayedAt': '2026-10-25T10:00:00Z',
              },
            ],
          },
        ),
        ('GET', '/api/v1/me/party') => (
          200,
          {'party': null, 'invites': <Object>[], 'requests': <Object>[]},
        ),
        _ => (204, null),
      };
      await server.start();
      hub = TogetherHub(account: await server.account());
      await until(() => hub.socket.session != null);
    });

    tearDown(() async {
      hub.dispose();
      await server.stop();
    });

    Discover discover() => hub.discover;

    /// The last request sent with [method]: the phone's own reads at start-up are all GETs.
    (String, String, Map<String, dynamic>?) lastOf(String method) =>
        server.requests.lastWhere((r) => r.$1 == method);

    test('the board, a page at a time, and its games', () async {
      await discover().loadBoard();
      expect(discover().board.map((p) => p.id), ['l2', 'l1']);
      expect(discover().boardMore, isTrue);
      await discover().olderBoard();
      expect(discover().board.map((p) => p.id), ['l2', 'l1', 'l0']);
      expect(discover().boardMore, isFalse);
      await discover().loadBoardGames();
      expect(discover().boardGames.single.posts, 4);
      expect(discover().boardGames.single.game.name('en'), 'Astro Bot');
    });

    test(
      'a filter reads the board again, and watches that game only',
      () async {
        discover().show(DiscoverView.board);
        await until(() => server.sent('watch').isNotEmpty);
        expect(server.sent('watch').last['topics'], ['lfg']);
        await discover().loadBoard(
          filter: const LfgFilter(titleId: 'PPSA01234'),
        );
        expect(
          server.requests.map((r) => r.$2),
          contains('/api/v1/lfg?titleId=PPSA01234'),
        );
        expect(discover().filter.titleId, 'PPSA01234');
        await until(() => server.sent('watch').length == 2);
        expect(server.sent('watch').last['topics'], ['lfg:PPSA01234']);
        discover().show(DiscoverView.live);
        await until(() => server.sent('watch').length == 3);
        expect(server.sent('watch').last['topics'], ['discover']);
        discover().show(null);
        await until(() => server.sent('watch').length == 4);
        expect(server.sent('watch').last['topics'], isEmpty);
      },
    );

    test('a screen gone hides only what it showed', () async {
      final first = Object();
      final second = Object();
      discover().show(DiscoverView.board, by: first);
      discover().show(DiscoverView.live, by: second);
      discover().hide(first);
      expect(discover().showing, DiscoverView.live);
      discover().hide(second);
      expect(discover().showing, isNull);
    });

    test('the reader\'s games to post for', () async {
      final games = await discover().myGames();
      expect(
        server.requests.map((r) => r.$2),
        contains('/api/v1/users/utku/library'),
      );
      expect(games.single.name('en'), 'Astro Bot');
    });

    test(
      'the board reads itself again when it changes, only while shown',
      () async {
        discover().show(DiscoverView.board);
        await until(() => boardPages == 1);
        server.push('lfg.changed', {
          'postId': 'l3',
          'titleId': 'PPSA01234',
          'change': 'opened',
        });
        await until(() => boardPages == 2);
        discover().show(DiscoverView.people);
        server.push('lfg.changed', {
          'postId': 'l3',
          'titleId': 'PPSA01234',
          'change': 'closed',
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(boardPages, 2);
      },
    );

    test('"I\'m in", then taken back', () async {
      await discover().loadBoard();
      await discover().imIn('l1');
      expect(lastOf('POST').$2, '/api/v1/lfg/l1/requests');
      expect(
        discover().board.firstWhere((p) => p.id == 'l1').myRequest?.status,
        LfgAnswer.pending,
      );
      await discover().takeBack('l1');
      expect(lastOf('DELETE'), ('DELETE', '/api/v1/lfg/l1/requests/me', null));
      expect(
        discover().board.firstWhere((p) => p.id == 'l1').myRequest,
        isNull,
      );
    });

    test('the poster\'s answer reaches the asker live, and a party invite is fetched', () async {
      await discover().loadBoard();
      await discover().imIn('l1');
      final asked = server.requests.length;
      server.push('lfg.answered', {
        'postId': 'l1',
        'answer': 'accepted',
        'invite': {'kind': 'party', 'id': 'p1'},
      });
      await until(
        () =>
            discover().board
                .firstWhere((p) => p.id == 'l1')
                .myRequest
                ?.status ==
            LfgAnswer.accepted,
      );
      expect(
        discover().board.firstWhere((p) => p.id == 'l1').myRequest?.invite?.id,
        'p1',
      );
      // The invite is quiet: the party is asked for.
      await until(
        () =>
            server.requests.skip(asked).any((r) => r.$2 == '/api/v1/me/party'),
      );
    });

    test('my posts with who asked, a yes, and closing one', () async {
      await discover().loadMine();
      expect(discover().mine.single.requests.single.person.handle, 'ali');
      expect(discover().asked.single.id, 'l1');
      expect(discover().waiting, 1);
      await discover().answer('m1', 'ali', accept: true);
      expect(discover().mine.single.filled, 1);
      expect(discover().mine.single.requests.single.invite?.id, 'p1');
      expect(discover().waiting, 0);
      await discover().close('m1');
      expect(lastOf('DELETE'), ('DELETE', '/api/v1/lfg/m1', null));
      expect(discover().mine.single.status, LfgStatus.closed);
    });

    test('someone asking in on my post reads my posts again', () async {
      await discover().loadMine();
      final before = server.requests.where((r) => r.$2 == '/api/v1/me/lfg');
      final count = before.length;
      server.push('lfg.request', {
        'postId': 'm1',
        'titleId': 'PPSA01234',
        'from': card('can'),
      });
      await until(
        () =>
            server.requests.where((r) => r.$2 == '/api/v1/me/lfg').length ==
            count + 1,
      );
    });

    test(
      'an ask on a post counts on the badge, my posts read or not',
      () async {
        expect(hub.badge, 0);
        server.push('lfg.request', {
          'postId': 'm1',
          'titleId': 'PPSA01234',
          'from': card('ali'),
        });
        await until(() => discover().mineLoaded);
        expect(discover().waiting, 1);
        expect(hub.badge, 1);
      },
    );

    test('posting sends the draft and keeps the post among mine', () async {
      await discover().loadMine();
      final post = await discover().post(
        const LfgDraft(
          titleId: 'PPSA01234',
          purpose: LfgPurpose.coop,
          languages: ['tr'],
          slots: 2,
        ),
      );
      expect(post.id, 'm2');
      expect(lastOf('POST').$3?['purpose'], 'coop');
      expect(lastOf('POST').$3?['slots'], 2);
      expect(discover().mine.first.id, 'm2');
    });

    test('live now: public share plays and parties, asking to join', () async {
      await discover().loadLive();
      expect(discover().liveShares.single.id, 's1');
      expect(discover().publicParties.single.id, 'p1');
      await discover().askParty('p1');
      expect(lastOf('POST').$2, '/api/v1/parties/p1/requests');
      expect(discover().publicParties.single.requested, isTrue);
      server.push('party.request_answered', {
        'partyId': 'p1',
        'answer': 'declined',
      });
      await until(() => !discover().publicParties.single.requested);
      await discover().askShare('s1');
      expect(lastOf('POST').$2, '/api/v1/share-plays/s1/requests');
      expect(discover().liveShares.single.requested, isTrue);
    });

    test('the public lists read themselves again when they change', () async {
      discover().show(DiscoverView.live);
      await until(() => discover().liveLoaded);
      final count = server.requests
          .where((r) => r.$2 == '/api/v1/parties/public')
          .length;
      server.push('discover.changed', {
        'kind': 'party',
        'id': 'p2',
        'titleId': null,
        'change': 'listed',
      });
      await until(
        () =>
            server.requests
                .where((r) => r.$2 == '/api/v1/parties/public')
                .length ==
            count + 1,
      );
    });

    test('the discovery setting and the languages, and suggestions', () async {
      await discover().loadDiscovery();
      expect(discover().discovery?.discoverable, isFalse);
      await discover().setDiscoverable(true);
      expect(lastOf('PATCH').$3, {'discoverable': true});
      expect(discover().discovery?.chosen, isTrue);
      await discover().setDiscoverable(null);
      expect(lastOf('PATCH').$3, {'discoverable': null});
      expect(discover().discovery?.chosen, isNull);
      await discover().setLanguages(['tr', 'en']);
      expect(lastOf('PATCH').$3, {
        'languages': ['tr', 'en'],
      });
      expect(discover().discovery?.languages, ['tr', 'en']);
      await discover().loadSuggestions();
      expect(discover().suggestions.single.person.handle, 'zeynep');
      discover().requested('zeynep');
      expect(discover().suggestions.single.friendship, Friendship.pendingOut);
    });

    test('signing out forgets it all', () async {
      await discover().loadBoard();
      await discover().loadMine();
      await hub.account.signOut();
      expect(discover().board, isEmpty);
      expect(discover().mine, isEmpty);
      expect(discover().boardLoaded, isFalse);
    });
  });
}
