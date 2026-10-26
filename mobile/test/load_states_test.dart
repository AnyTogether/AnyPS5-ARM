import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_hub.dart';

void main() {
  for (final (tab, path) in [
    (TogetherTab.friends, 'me/friends'),
    (TogetherTab.messages, 'me/conversations'),
  ]) {
    testWidgets(
      '${tab.name}: a list that does not load says so, and Try Again loads it',
      (tester) async {
        tester.view.physicalSize = const Size(1334, 750);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final (hub, account) = await scriptedHub();
        var up = false;
        account.answer = (method, path, body) => switch ((method, path)) {
          _ when !up => null,
          ('GET', 'me/friends') => {'friends': []},
          ('GET', 'me/friends/requests') => {'incoming': [], 'outgoing': []},
          ('GET', 'me/conversations') => {'conversations': []},
          ('GET', 'me/conversations/unread') => {'messages': 0},
          _ => null,
        };
        await tester.pumpWidget(
          Texts(
            strings: Strings.english,
            child: MaterialApp(
              home: TogetherScreen(hub: hub, tab: tab),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(Strings.english.retry), findsOneWidget);
        expect(account.paths('GET'), contains(path));
        up = true;
        await tester.tap(find.text(Strings.english.retry));
        await tester.pumpAndSettle();
        expect(find.text(Strings.english.retry), findsNothing);
        expect(
          find.text(
            tab == TogetherTab.friends
                ? Strings.english.friendsNone
                : Strings.english.messagesNone,
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        hub.dispose();
      },
    );
  }
}
