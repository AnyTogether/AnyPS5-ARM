import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/ui/trophy_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a trophy drops in, then goes', (tester) async {
    final trophy = ValueNotifier<TrophyEarned?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TrophyCard(trophy: trophy)),
      ),
    );
    expect(find.text('Bound'), findsNothing);
    trophy.value = const TrophyEarned(
      name: 'Bound',
      detail: 'Bind your first Silk Skill',
      grade: 'bronze',
      icon: null,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bound'), findsOneWidget);
    expect(find.text('Trophy earned'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    await tester.pump(TrophyCard.shown + const Duration(milliseconds: 400));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });
}
