import 'package:anyps5_remote/layout/layout_tweaks.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:anyps5_remote/ui/pad_layout.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const size = Size(800, 400);

class Pad {
  final states = <PadState>[];
  final tweaks = <LayoutTweaks>[];
}

Future<Pad> show(WidgetTester tester, LayoutTweaks tweaks) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pad = Pad();
  await tester.pumpWidget(
    MaterialApp(
      home: PadScreen(
        onState: pad.states.add,
        tweaks: tweaks,
        onTweaks: pad.tweaks.add,
      ),
    ),
  );
  return pad;
}

Offset at(String id) => PadLayout.standard.center(id, size);

bool cross(PadState state) => state.buttons & PadButton.cross != 0;

void main() {
  testWidgets('a toggle button stays pressed until it is tapped again', (
    tester,
  ) async {
    final pad = await show(
      tester,
      LayoutTweaks.none.change(
        'cross',
        (t) => t.copyWith(behavior: ButtonBehavior.toggle),
      ),
    );
    await tester.tapAt(at('cross'));
    expect(cross(pad.states.last), isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(cross(pad.states.last), isTrue);
    await tester.tapAt(at('cross'));
    expect(cross(pad.states.last), isFalse);
  });

  testWidgets('a turbo button presses again and again while held', (
    tester,
  ) async {
    final pad = await show(
      tester,
      LayoutTweaks.none.change(
        'cross',
        (t) => t.copyWith(behavior: ButtonBehavior.turbo),
      ),
    );
    final finger = await tester.startGesture(at('cross'));
    for (var step = 0; step < 12; step++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    final held = pad.states.map(cross).toList();
    expect(held, contains(true));
    expect(held.skip(1), contains(false));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cross(pad.states.last), isFalse);
  });

  testWidgets('a hidden button is not pressed', (tester) async {
    final pad = await show(
      tester,
      LayoutTweaks.none.change('cross', (t) => t.copyWith(hidden: true)),
    );
    await tester.tapAt(at('cross'));
    expect(pad.states.where(cross), isEmpty);
  });

  testWidgets('in the editor a control is dragged, and the game gets nothing', (
    tester,
  ) async {
    final pad = await show(tester, LayoutTweaks.none);
    await tester.tap(find.byIcon(Icons.lock_outline_rounded));
    await tester.pump();
    final finger = await tester.startGesture(at('cross'));
    await finger.moveBy(const Offset(-80, 0));
    await finger.up();
    await tester.pump();
    expect(pad.states.where(cross), isEmpty);
    final moved = pad.tweaks.last.of('cross');
    expect(moved.x, closeTo(PadLayout.standard.control('cross').x - 0.1, 0.01));
    expect(find.text('Toggle'), findsOneWidget);
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(pad.tweaks.last.of('cross').behavior, ButtonBehavior.toggle);
  });
}
