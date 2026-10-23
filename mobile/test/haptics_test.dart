import 'package:anyps5_remote/feedback/haptics.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class Recorder implements HapticsOutput {
  final sent = <Rumble>[];

  @override
  void set(Rumble rumble) => sent.add(rumble);
}

Output output({
  int large = 0,
  int small = 0,
  int l2 = 0,
  int r2 = 0,
  bool light = false,
  int r = 0,
  int g = 0,
  int b = 0,
}) => Output(
  sequence: 1,
  waitMicros: 0,
  sentMicros: 0,
  large: large,
  small: small,
  lightValid: light,
  r: r,
  g: g,
  b: b,
  l2Fallback: l2,
  r2Fallback: r2,
);

void main() {
  late Recorder out;
  late HapticsDriver driver;

  setUp(() {
    out = Recorder();
    driver = HapticsDriver(out);
  });

  void feed(Output o, {int ms = 0, bool l2 = false, bool r2 = false}) =>
      driver.update(
        o,
        l2Held: l2,
        r2Held: r2,
        now: Duration(milliseconds: ms),
      );

  test('the large motor is a strong, dull rumble, sent once', () {
    feed(output(large: 200));
    feed(output(large: 200), ms: 8);
    expect(out.sent.length, 1);
    expect(out.sent.single.strength, closeTo(200, 8));
    expect(out.sent.single.sharpness, lessThan(0.4));
  });

  test('the small motor alone is sharp', () {
    feed(output(small: 120));
    expect(out.sent.single.sharpness, greaterThan(0.6));
  });

  test('motors that stop stop the phone once', () {
    feed(output(large: 90));
    feed(output(), ms: 8);
    feed(output(), ms: 16);
    expect(out.sent.map((r) => r.strength).toList(), [isNonZero, 0]);
  });

  test('a held trigger with an effect pulses', () {
    feed(output(l2: 160), l2: true);
    feed(output(l2: 160), ms: 60, l2: true);
    feed(output(l2: 160), ms: 100, l2: true);
    expect(out.sent.map((r) => r.strength).toList(), [
      closeTo(160, 8),
      0,
      closeTo(160, 8),
    ]);
  });

  test('a trigger effect is not felt until the trigger is held', () {
    feed(output(r2: 200));
    feed(output(r2: 200), ms: 30);
    expect(out.sent, isEmpty);
  });

  test('turned off, nothing is felt', () {
    feed(output(large: 200));
    driver.enabled = false;
    feed(output(large: 200), ms: 8);
    expect(out.sent.last.strength, 0);
  });

  test('the light bar colour, when the game gives one', () {
    expect(
      lightColor(output(light: true, r: 255, g: 64, b: 0)),
      const Color(0xFFFF4000),
    );
    expect(lightColor(output(light: false, r: 255)), isNull);
    expect(lightColor(output(light: true)), isNull);
    expect(lightColor(null), isNull);
  });

  test('a trophy is felt as two short taps, then nothing', () async {
    driver.celebrate();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(out.sent.map((r) => r.strength > 0).toList(), [
      true,
      false,
      true,
      false,
    ]);
  });

  test('turned off, a trophy is not felt', () async {
    driver.enabled = false;
    driver.celebrate();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(out.sent, isEmpty);
  });
}
