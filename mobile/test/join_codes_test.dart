import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/join_codes.dart';
import 'package:anyps5_remote/together/parties.dart';
import 'package:anyps5_remote/ui/join_code_view.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart' show card;
import 'support/scripted_hub.dart';

Map<String, dynamic> party({
  String leader = 'me',
  Map<String, dynamic>? joinCode,
  String? discord,
  Map<String, dynamic>? call,
}) => {
  'id': 'p1',
  'leaderId': leader,
  'privacy': 'invite',
  'members': [card('me'), card('ece')],
  'invited': [],
  'call': call,
  'public': null,
  'requests': [],
  'joinCode': joinCode,
  'discord': discord,
  'createdAt': '2026-10-24T12:00:00Z',
};

final _code = {
  'code': 'K7QM3XPA',
  'url': 'https://anytogether.net/join/K7QM3XPA',
  'expiresAt': DateTime.now()
      .add(const Duration(hours: 24))
      .toUtc()
      .toIso8601String(),
};

void main() {
  group('a code as typed', () {
    test('any case, with the dash, spaces or the whole link', () {
      expect(JoinCode.normalize('k7qm-3xpa'), 'K7QM3XPA');
      expect(JoinCode.normalize(' K7QM 3XPA '), 'K7QM3XPA');
      expect(
        JoinCode.normalize(
          'https://anytogether.net/join/K7QM3XPA?from=discord',
        ),
        'K7QM3XPA',
      );
      expect(JoinCode.format('K7QM3XPA'), 'K7QM-3XPA');
    });

    test('anything that cannot be one is not', () {
      expect(JoinCode.normalize('K7QM3XP'), isNull);
      expect(JoinCode.normalize('K7QM3XPO'), isNull, reason: 'no O');
      expect(JoinCode.normalize('K7QM3XP1'), isNull, reason: 'no 1');
      expect(JoinCode.normalize(''), isNull);
    });
  });

  test('Discord links as the server keeps them', () {
    expect(discordLinkOf('discord.gg/anyps5'), 'https://discord.gg/anyps5');
    expect(
      discordLinkOf('https://discord.com/invite/abc-12/'),
      'https://discord.com/invite/abc-12',
    );
    expect(
      discordLinkOf('https://discord.com/channels/123456/7654321'),
      'https://discord.com/channels/123456/7654321',
    );
    expect(discordLinkOf('http://discord.gg/anyps5'), isNull);
    expect(discordLinkOf('https://evil.example/discord.gg'), isNull);
    expect(discordLinkOf('https://discord.com/app'), isNull);
  });

  group('the party', () {
    test('its code, Discord link and who is deafened come with it', () {
      final p = Party.fromJson(
        party(
          joinCode: _code,
          discord: 'https://discord.gg/anyps5',
          call: {
            'id': 'c1',
            'in': ['me', 'ece'],
            'muted': ['ece'],
            'deafened': ['ece'],
          },
        ),
      );
      expect(p.joinCode?.display, 'K7QM-3XPA');
      expect(p.joinCode?.works(), isTrue);
      expect(p.discord, 'https://discord.gg/anyps5');
      expect(p.deafened, {'ece'});
    });

    test(
      'the leader makes a code, stops it, and sets the Discord link',
      () async {
        final (hub, account) = await scriptedHub();
        account.answer = (method, path, body) => switch ((method, path)) {
          ('GET', 'me/party') => {'party': party(), 'invites': []},
          ('POST', 'parties/p1/code') => _code,
          ('DELETE', 'parties/p1/code') => {},
          ('PATCH', 'parties/p1') => party(
            discord: body?['discord'] as String?,
          ),
          _ => null,
        };
        await hub.parties.refresh();
        final made = await hub.parties.makeCode();
        expect(made?.code, 'K7QM3XPA');
        expect(hub.parties.party?.joinCode?.code, 'K7QM3XPA');
        expect(account.calls.last.$3, isEmpty);
        await hub.parties.stopCode();
        expect(account.paths('DELETE'), ['parties/p1/code']);
        expect(hub.parties.party?.joinCode, isNull);
        await hub.parties.setDiscord('https://discord.gg/anyps5');
        expect(account.calls.last.$3, {'discord': 'https://discord.gg/anyps5'});
        expect(hub.parties.party?.discord, 'https://discord.gg/anyps5');
        hub.dispose();
      },
    );
  });

  Widget host(Widget child, {String language = 'en'}) => Texts(
    strings: Strings.of(language),
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    ),
  );

  testWidgets('joining with a code: what it opens, then asking', (
    tester,
  ) async {
    final (hub, account) = await scriptedHub();
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'join/K7QM3XPA') => {
        'code': 'K7QM3XPA',
        'kind': 'party',
        'id': 'p9',
        'host': card('ece'),
        'game': {
          'titleId': 'PPSA01234',
          'title': 'Astro Bot',
          'names': {'en': 'Astro Bot'},
          'iconUrl': null,
        },
        'size': 2,
        'max': 8,
        'expiresAt': '2999-01-01T00:00:00Z',
        'state': 'none',
      },
      ('POST', 'join/K7QM3XPA') => {
        'kind': 'party',
        'id': 'p9',
        'state': 'requested',
      },
      _ => null,
    };
    await tester.pumpWidget(host(JoinWithCode(codes: JoinCodes(account))));
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Look up'));
    await tester.pump();
    expect(find.text('A code is 8 letters and numbers'), findsOneWidget);
    expect(account.calls, isEmpty);

    await tester.enterText(
      find.byType(TextField),
      'https://anytogether.net/join/k7qm-3xpa',
    );
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();
    expect(account.calls.single.$2, 'join/K7QM3XPA');
    expect(find.text("ECE's party"), findsOneWidget);
    expect(find.text('Astro Bot'), findsOneWidget);
    expect(find.textContaining('2 of 8'), findsOneWidget);

    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    expect(account.paths('POST'), ['join/K7QM3XPA']);
    expect(
      find.text("Asked. You'll hear when the leader answers"),
      findsOneWidget,
    );
    expect(find.text('Ask to join'), findsNothing);
    hub.dispose();
  });

  testWidgets('a code that does not work says so, in Turkish too', (
    tester,
  ) async {
    final (hub, account) = await scriptedHub();
    await tester.pumpWidget(
      host(JoinWithCode(codes: JoinCodes(account)), language: 'tr'),
    );
    await tester.enterText(find.byType(TextField), 'K7QM3XPA');
    await tester.tap(find.text('Bak'));
    await tester.pumpAndSettle();
    expect(
      find.text('Böyle bir kod yok ya da artık çalışmıyor'),
      findsOneWidget,
    );
    hub.dispose();
  });

  testWidgets('the leader makes a code and copies it; a member only sees it', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    final (hub, account) = await scriptedHub();
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'me/party') => {'party': party(), 'invites': []},
      ('POST', 'parties/p1/code') => _code,
      _ => null,
    };
    await hub.parties.refresh();
    Future<void> run(Future<void> Function() step) => step();
    Widget code() => ListenableBuilder(
      listenable: hub.parties,
      builder: (context, _) => PartyCode(
        parties: hub.parties,
        party: hub.parties.party!,
        leader: hub.parties.party!.leaderId == 'me',
        run: run,
      ),
    );
    await tester.pumpWidget(host(code()));
    await tester.tap(find.text('Make a join code'));
    await tester.pumpAndSettle();
    expect(find.text('K7QM-3XPA'), findsOneWidget);
    expect(find.text('New code: K7QM-3XPA'), findsOneWidget);
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied, ['K7QM-3XPA']);
    expect(find.text('Stop code'), findsOneWidget);

    // A member sees the code to pass on, but cannot stop it.
    final member = Party.fromJson(party(leader: 'ece', joinCode: _code));
    await tester.pumpWidget(
      host(
        PartyCode(parties: hub.parties, party: member, leader: false, run: run),
      ),
    );
    expect(find.text('K7QM-3XPA'), findsOneWidget);
    expect(find.text('Stop code'), findsNothing);
    // No code and not the leader: nothing at all.
    await tester.pumpWidget(
      host(
        PartyCode(
          parties: hub.parties,
          party: Party.fromJson(party(leader: 'ece')),
          leader: false,
          run: run,
        ),
      ),
    );
    expect(find.text('Make a join code'), findsNothing);
    hub.dispose();
  });

  testWidgets('the party pane offers joining with a code', (tester) async {
    tester.view.physicalSize = const Size(1334, 750);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final (hub, account) = await scriptedHub();
    account.answer = (method, path, body) => switch ((method, path)) {
      ('GET', 'me/party') => {'party': null, 'invites': []},
      ('GET', 'me/friends') => {'friends': [], 'incoming': [], 'outgoing': []},
      _ => null,
    };
    await tester.pumpWidget(
      Texts(
        strings: Strings.english,
        child: MaterialApp(
          home: TogetherScreen(hub: hub, tab: TogetherTab.party),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
  });
}
