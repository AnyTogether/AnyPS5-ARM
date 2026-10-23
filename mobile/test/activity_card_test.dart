import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/ui/activity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 23, 21, 0);

  Activity activity(ActivityPhase phase, {double? fraction}) => Activity(
    id: 'cat',
    phase: phase,
    updating: true,
    fraction: fraction,
    elapsed: Duration.zero,
  );

  Future<ValueNotifier<({Activity activity, DateTime since})?>> show(
    WidgetTester tester,
    DateTime Function() now,
  ) async {
    final shown = ValueNotifier<({Activity activity, DateTime since})?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityCard(
            activity: shown,
            game: (id) => (name: 'Cat Quest III', icon: null),
            now: now,
          ),
        ),
      ),
    );
    return shown;
  }

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('an update shows its step, how far along and the time taken', (
    tester,
  ) async {
    var now = start.add(const Duration(seconds: 83));
    final shown = await show(tester, () => now);
    shown.value = (
      activity: activity(ActivityPhase.relink, fraction: 0.425),
      since: start,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Updating'), findsOneWidget);
    expect(find.text('Cat Quest III'), findsOneWidget);
    expect(find.text('Converting for Mac · 42%'), findsOneWidget);
    expect(find.text('1:23'), findsOneWidget);
    expect(opacity(tester), 1);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1:25'), findsOneWidget);
    shown.value = null;
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(tester), 0, reason: 'a cancelled update just goes');
  });

  testWidgets('a game that starts says it is ready, then goes', (tester) async {
    final shown = await show(tester, () => start);
    shown.value = (activity: activity(ActivityPhase.starting), since: start);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Starting'), findsOneWidget);
    expect(find.text('Opening the game on the Mac'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    shown.value = null;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ready'), findsOneWidget);
    expect(opacity(tester), 1);
    await tester.pump(ActivityCard.readyShown);
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(tester), 0);
  });
}
