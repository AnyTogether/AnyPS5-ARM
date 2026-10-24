import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discover_data.dart';
import 'support/fake_server.dart';
import 'support/scripted_hub.dart';

/// An iPhone 14 Pro on its side, as the other screens are tested.
void sideways(WidgetTester tester) {
  tester.view.physicalSize = const Size(2556, 1179);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Each of [texts] is on the screen, not past its edges.
void onScreen(WidgetTester tester, List<String> texts) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final text in texts) {
    final found = find.text(text);
    expect(found, findsWidgets, reason: text);
    final box = tester.getRect(found.first);
    expect(box.bottom, lessThanOrEqualTo(screen.height), reason: text);
    expect(box.right, lessThanOrEqualTo(screen.width), reason: text);
    expect(box.left, greaterThanOrEqualTo(0), reason: text);
  }
}

/// Picks a tab of Find players; the row of tabs scrolls sideways when the words are long.
Future<void> pickTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.pump();
  await tester.tap(find.text(label).first);
  await settle(tester);
}

/// Scrolls the list on the right until [finder] shows.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      80,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> open(
  WidgetTester tester,
  TogetherHub hub, {
  Strings strings = Strings.english,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Texts(
        strings: strings,
        child: TogetherScreen(hub: hub, tab: TogetherTab.findPlayers),
      ),
    ),
  );
  await settle(tester);
}

void main() {
  testWidgets('the board fits sideways: filters, posts, and "I\'m in"', (
    tester,
  ) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg' || 'lfg?purpose=coop') => {
        'posts': [
          lfgPost('l1', note: 'mics on, chill'),
          lfgPost(
            'l2',
            author: 'ali',
            purpose: 'coop',
            myRequest: {'status': 'pending', 'invite': null},
          ),
          lfgPost(
            'l3',
            author: 'can',
            purpose: 'party',
            slots: 2,
            filled: 2,
            myRequest: {
              'status': 'accepted',
              'invite': {'kind': 'party', 'id': 'p1'},
            },
          ),
        ],
        'more': false,
      },
      ('GET', 'lfg/games') => {
        'games': [
          {
            'titleId': 'PPSA01234',
            'posts': 3,
            'names': {'en': 'Astro Bot'},
            'iconUrl': null,
          },
        ],
      },
      ('POST', 'lfg/l1/requests') => lfgPost(
        'l1',
        note: 'mics on, chill',
        myRequest: {'status': 'pending', 'invite': null},
      ),
      _ => null,
    };
    await open(tester, hub);
    onScreen(tester, [
      'Find players',
      'Looking for group',
      'Your posts',
      'Post',
      'All games',
      'Anything',
      'Any language',
      'Now',
      "I'm in",
      'Asked',
      'Take back',
    ]);
    expect(find.text('Astro Bot'), findsNWidgets(3));
    expect(
      find.text('Now · English, Turkish · 3 of 3 spots left'),
      findsWidgets,
    );
    expect(find.text('“mics on, chill”'), findsOneWidget);
    expect(find.text("You're in"), findsOneWidget);
    expect(find.text('Party'), findsWidgets);
    await tester.tap(find.text("I'm in"));
    await settle(tester);
    expect(account.paths('POST'), ['lfg/l1/requests']);
    expect(find.text('Asked'), findsNWidgets(2));
    await tester.tap(find.text('Anything'));
    await settle(tester);
    await tester.tap(find.text('Co-op').last);
    await settle(tester);
    expect(account.paths('GET'), contains('lfg?purpose=coop'));
    // The board is watched (sent once the socket is up).
    expect(hub.socket.topics, ['lfg']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new post: the form fits sideways and sends the draft', (
    tester,
  ) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg') => {'posts': <Object>[], 'more': false},
      ('GET', 'users/utku/library') => {
        'games': [
          {
            'titleId': 'PPSA01234',
            'names': {'en': 'Astro Bot'},
            'iconUrl': null,
          },
          {
            'titleId': 'PPSA05678',
            'names': {'en': 'Stray'},
            'iconUrl': null,
          },
        ],
      },
      ('GET', 'me/discovery') => {
        'discoverable': true,
        'chosen': null,
        'languages': ['tr'],
      },
      ('POST', 'lfg') => lfgPost(
        'm2',
        author: 'me',
        mine: true,
        requests: const [],
      ),
      ('GET', 'me/lfg') => {
        'posts': [lfgPost('m2', author: 'me', mine: true, requests: const [])],
        'asked': <Object>[],
      },
      _ => null,
    };
    await open(tester, hub);
    expect(
      find.text(
        'Nobody is looking right now. Post what you want to play and people will find you.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Post'));
    await settle(tester);
    onScreen(tester, ['Looking for players', 'Astro Bot', 'Stray']);
    await tester.tap(find.text('Stray'));
    await scrollTo(tester, find.text('Co-op'));
    await tester.tap(find.text('Co-op'));
    await tester.pump();
    await scrollTo(tester, find.byTooltip('+'));
    for (var n = 0; n < 4; n++) {
      await tester.tap(find.byTooltip('+'), warnIfMissed: false);
      await tester.pump();
    }
    // Co-op has room for three more.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('lfg slots'))).data,
      '3',
    );
    await scrollTo(tester, find.text('Post it'));
    await tester.enterText(find.byType(TextField).last, ' mics on ');
    await tester.tap(find.text('Post it'));
    await settle(tester);
    final sent = account.calls.lastWhere((c) => c.$1 == 'POST').$3!;
    expect(sent['titleId'], 'PPSA05678');
    expect(sent['purpose'], 'coop');
    expect(sent['slots'], 3);
    expect(sent['languages'], ['tr']);
    expect(sent['note'], 'mics on');
    expect(sent.containsKey('startsAt'), isFalse);
    // Posted: on to your posts.
    expect(find.text('YOUR POSTS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('your posts: who wants in, letting them in, closing one', (
    tester,
  ) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    Map<String, dynamic> request(String id, String status, [String? kind]) => {
      'user': card(id),
      'status': status,
      'invite': kind == null ? null : {'kind': kind, 'id': 'x'},
      'createdAt': '2026-10-25T18:00:00Z',
    };
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg') => {'posts': <Object>[], 'more': false},
      ('GET', 'me/lfg') => {
        'posts': [
          lfgPost(
            'm1',
            author: 'me',
            mine: true,
            filled: 1,
            requests: [
              request('ali', 'pending'),
              request('can', 'accepted', 'party'),
            ],
          ),
        ],
        'asked': [
          lfgPost(
            'l4',
            author: 'deniz',
            myRequest: {'status': 'declined', 'invite': null},
          ),
        ],
      },
      ('POST', 'lfg/m1/requests/ali/accept') => lfgPost(
        'm1',
        author: 'me',
        mine: true,
        filled: 2,
        requests: [
          request('ali', 'accepted', 'party'),
          request('can', 'accepted', 'party'),
        ],
      ),
      ('DELETE', 'lfg/m1') => const {},
      _ => null,
    };
    await open(tester, hub);
    await pickTab(tester, 'Your posts');
    onScreen(tester, [
      'Open',
      'Close post',
      'ALI',
      'Let in',
      'Decline',
      'Invited to your party',
    ]);
    // One waits: counted on the tab and on the rail.
    expect(find.text('1'), findsNWidgets(2));
    await scrollTo(tester, find.text('Not this time'));
    expect(find.text('YOU ASKED TO JOIN'), findsOneWidget);
    await scrollTo(tester, find.text('Let in'));
    await tester.tap(find.text('Let in'));
    await settle(tester);
    expect(account.paths('POST'), ['lfg/m1/requests/ali/accept']);
    expect(find.text('Invited to your party'), findsNWidgets(2));
    expect(find.text('1'), findsNothing);
    await tester.tap(find.text('Close post'));
    await settle(tester);
    expect(account.paths('DELETE'), ['lfg/m1']);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('Close post'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live now: a live share play, asking into a party, an open one', (
    tester,
  ) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg') => {'posts': <Object>[], 'more': false},
      ('GET', 'share-plays/public?live=1') => {
        'sharePlays': [publicShare('s1')],
      },
      ('GET', 'parties/public') => {
        'parties': [
          publicParty('p1', join: 'request'),
          publicParty('p2', host: 'deniz'),
        ],
      },
      ('POST', 'parties/p1/requests') => {'requested': true},
      ('POST', 'parties/p2/join') => {
        'id': 'p2',
        'leaderId': 'deniz',
        'privacy': 'invite',
        'members': [
          {...card('deniz'), 'joinedAt': '2026-10-25T18:00:00Z'},
          {...card('me'), 'joinedAt': '2026-10-25T18:01:00Z'},
        ],
        'invited': <Object>[],
        'call': null,
        'public': {'join': 'open', 'titleId': 'PPSA01234', 'language': 'tr'},
        'createdAt': '2026-10-25T18:00:00Z',
      },
      _ => null,
    };
    await open(tester, hub);
    await pickTab(tester, 'Live now');
    onScreen(tester, [
      'LIVE',
      'Watch',
      'with CAN · 1/4 watching · English',
      'PUBLIC PARTIES',
      'Ask first',
      'Ask to join',
    ]);
    await scrollTo(tester, find.text('Join'));
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Ask to join'));
    await settle(tester);
    expect(account.paths('POST'), ['parties/p1/requests']);
    expect(find.text('Asked'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await settle(tester);
    expect(account.paths('POST'), contains('parties/p2/join'));
    expect(hub.parties.party?.id, 'p2');
    // Joined: on to the party.
    expect(find.text('Join voice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('people: the discovery setting, languages, a suggestion added', (
    tester,
  ) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    var discovery = <String, dynamic>{
      'discoverable': false,
      'chosen': null,
      'languages': ['tr'],
    };
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg') => {'posts': <Object>[], 'more': false},
      ('GET', 'me/discovery') => discovery,
      ('PATCH', 'me/discovery') => discovery = {
        ...discovery,
        if (body!.containsKey('discoverable')) ...{
          'discoverable': body['discoverable'] ?? false,
          'chosen': body['discoverable'],
        },
        if (body.containsKey('languages')) 'languages': body['languages'],
      },
      ('GET', 'discover/suggestions') => {
        'suggestions': [
          {
            'user': card('zeynep'),
            'friendship': 'none',
            'reasons': [
              {
                'kind': 'game',
                'titleId': 'PPSA01234',
                'names': {'en': 'Astro Bot'},
              },
              {'kind': 'friends', 'count': 2},
              {'kind': 'language', 'language': 'tr'},
            ],
          },
        ],
      },
      ('POST', 'me/friends/requests') => {'state': 'pending'},
      ('GET', 'me/friends') => {'friends': <Object>[]},
      ('GET', 'me/friends/requests') => {
        'incoming': <Object>[],
        'outgoing': <Object>[],
      },
      _ => null,
    };
    await open(tester, hub);
    await pickTab(tester, 'People');
    onScreen(tester, [
      'SHOW ME IN DISCOVERY',
      'Like my games',
      'On',
      'Off',
      'You are hidden from discovery now.',
      'ZEYNEP',
      'You both play Astro Bot · 2 friends in common · Speaks Turkish',
      'Add friend',
    ]);
    await tester.tap(find.text('On'));
    await settle(tester);
    expect(account.calls.lastWhere((c) => c.$1 == 'PATCH').$3, {
      'discoverable': true,
    });
    expect(find.text('Others can find you now.'), findsOneWidget);
    await tester.ensureVisible(find.text('English'));
    await tester.pump();
    await tester.tap(find.text('English'));
    await settle(tester);
    expect(account.calls.lastWhere((c) => c.$1 == 'PATCH').$3, {
      'languages': ['tr', 'en'],
    });
    await tester.tap(find.text('Add friend'));
    await settle(tester);
    expect(account.calls.lastWhere((c) => c.$1 == 'POST').$3, {
      'handle': 'zeynep',
    });
    expect(find.text('Requested'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Turkish, the board and its tabs', (tester) async {
    sideways(tester);
    final (hub, account) = await scriptedHub();
    addTearDown(hub.dispose);
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'lfg') => {
        'posts': [lfgPost('l1', purpose: 'trophies')],
        'more': false,
      },
      _ => null,
    };
    await open(tester, hub, strings: Strings.turkish);
    onScreen(tester, [
      'Oyuncu bul',
      'Grup arayanlar',
      'İlan ver',
      'Tüm oyunlar',
      'Kupa yardımı',
      'Ben varım',
      'Şimdi · İngilizce, Türkçe · 3 kişilik yerden 3 boş',
    ]);
    expect(tester.takeException(), isNull);
  });
}
