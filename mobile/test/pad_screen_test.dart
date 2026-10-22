import 'package:anyps5_remote/protocol/packets.dart';
import 'package:anyps5_remote/ui/pad_layout.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const size = Size(800, 400);

Future<List<PadState>> show(WidgetTester tester) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final states = <PadState>[];
  await tester.pumpWidget(MaterialApp(home: PadScreen(onState: states.add)));
  return states;
}

Offset at(String id) => PadLayout.standard.center(id, size);

void main() {
  testWidgets('cross sets 0x4000 while held', (tester) async {
    final states = await show(tester);
    final finger = await tester.startGesture(at('cross'));
    expect(states.last.buttons & PadButton.cross, PadButton.cross);
    await finger.up();
    expect(states.last.buttons & PadButton.cross, 0);
  });

  testWidgets('PS goes home and is not sent to the game', (tester) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final states = <PadState>[];
    var home = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PadScreen(onState: states.add, onHome: () => home++),
      ),
    );
    await tester.tapAt(at('ps'));
    expect(home, 1);
    expect(states.every((state) => state.buttons == 0), isTrue);
  });

  testWidgets('two buttons at once', (tester) async {
    final states = await show(tester);
    final first = await tester.startGesture(at('cross'));
    final second = await tester.startGesture(at('r1'));
    expect(states.last.buttons, PadButton.cross | PadButton.r1);
    await first.up();
    await second.up();
    expect(states.last.buttons, 0);
  });

  testWidgets('left stick full right', (tester) async {
    final states = await show(tester);
    final radius = PadLayout.standard.radius('leftStick', size);
    final finger = await tester.startGesture(at('leftStick'));
    await finger.moveBy(Offset(radius, 0));
    expect(states.last.sticks[0], 255);
    expect(states.last.sticks[1], 128);
    await finger.up();
    expect(states.last.sticks.sublist(0, 2), [128, 128]);
  });

  testWidgets('stick up is 0', (tester) async {
    final states = await show(tester);
    final radius = PadLayout.standard.radius('rightStick', size);
    final finger = await tester.startGesture(at('rightStick'));
    await finger.moveBy(Offset(0, -radius * 1.5));
    expect(states.last.sticks[3], 0);
    expect(states.last.sticks[2], 128);
    await finger.up();
  });

  testWidgets('a double tap on a stick holds L3', (tester) async {
    final states = await show(tester);
    final tap = await tester.startGesture(at('leftStick'));
    await tap.up();
    await tester.pump(const Duration(milliseconds: 100));
    final hold = await tester.startGesture(at('leftStick'));
    expect(states.last.buttons & PadButton.l3, PadButton.l3);
    await hold.up();
    expect(states.last.buttons & PadButton.l3, 0);
  });

  testWidgets('L2 is analog full', (tester) async {
    final states = await show(tester);
    final finger = await tester.startGesture(at('l2'));
    expect(states.last.l2, 255);
    expect(states.last.buttons & PadButton.l2, PadButton.l2);
    await finger.up();
    expect(states.last.l2, 0);
  });

  testWidgets('touchpad reports a touch point', (tester) async {
    final states = await show(tester);
    final finger = await tester.startGesture(at('touchPad'));
    final touch = states.last.touch[0];
    expect(touch.active, isTrue);
    expect(touch.x, closeTo(960, 10));
    expect(touch.y, closeTo(540, 10));
    expect(states.last.buttons & PadButton.touchPad, PadButton.touchPad);
    await finger.up();
    expect(states.last.touch[0].active, isFalse);
  });

  testWidgets('leaving the pad releases it', (tester) async {
    final states = await show(tester);
    await tester.startGesture(at('cross'));
    expect(states.last.buttons, PadButton.cross);
    await tester.pumpWidget(const SizedBox());
    expect(states.last.buttons, 0);
  });

  testWidgets('a finger off every control does nothing', (tester) async {
    final states = await show(tester);
    final finger = await tester.startGesture(const Offset(400, 390));
    expect(states, isEmpty);
    await finger.up();
  });
}
