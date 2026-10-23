import 'dart:ui';

import 'package:anyps5_remote/layout/layout_tweaks.dart';
import 'package:anyps5_remote/ui/pad_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const size = Size(800, 400);

  test('no tweaks is the default layout, saved as nothing', () {
    const tweaks = LayoutTweaks.none;
    expect(tweaks.toJson(), isNull);
    expect(LayoutTweaks.fromJson(null).isEmpty, isTrue);
    expect(LayoutTweaks.fromJson('not json').isEmpty, isTrue);
    final layout = tweaks.apply(PadLayout.standard);
    expect(layout.control('cross').x, PadLayout.standard.control('cross').x);
  });

  test('tweaks survive the trip through the launcher', () {
    final tweaks = LayoutTweaks.none
        .change('cross', (t) => t.copyWith(x: 0.7, y: 0.5, scale: 1.3))
        .change('r1', (t) => t.copyWith(hidden: true))
        .change(
          'square',
          (t) => t.copyWith(opacity: 0.4, behavior: ButtonBehavior.turbo),
        )
        .change('triangle', (t) => t.copyWith(behavior: ButtonBehavior.toggle));
    final again = LayoutTweaks.fromJson(tweaks.toJson());
    expect(again.of('cross').x, 0.7);
    expect(again.of('cross').scale, 1.3);
    expect(again.of('r1').hidden, isTrue);
    expect(again.of('square').opacity, 0.4);
    expect(again.of('square').behavior, ButtonBehavior.turbo);
    expect(again.of('triangle').behavior, ButtonBehavior.toggle);
    expect(again.of('circle').behavior, ButtonBehavior.normal);
  });

  test('a moved, bigger button is where and as big as its tweak says', () {
    final layout = LayoutTweaks.none
        .change('cross', (t) => t.copyWith(x: 0.5, y: 0.5, scale: 2))
        .apply(PadLayout.standard);
    final cross = layout.control('cross');
    expect(cross.x, 0.5);
    expect(
      cross.size,
      closeTo(PadLayout.standard.control('cross').size * 2, 1e-9),
    );
    expect(layout.hit(const Offset(400, 200), size)?.id, 'cross');
  });

  test('a hidden control is not drawn for play and not pressed', () {
    final layout = LayoutTweaks.none
        .change('cross', (t) => t.copyWith(hidden: true))
        .apply(PadLayout.standard);
    expect(layout.control('cross').hidden, isTrue);
    expect(
      layout.hit(PadLayout.standard.center('cross', size), size)?.id,
      isNot('cross'),
    );
    expect(
      layout
          .hit(
            PadLayout.standard.center('cross', size),
            size,
            includeHidden: true,
          )
          ?.id,
      'cross',
    );
  });

  test('going back to the default drops a control\'s tweak', () {
    final tweaks = LayoutTweaks.none
        .change('cross', (t) => t.copyWith(scale: 1.5))
        .change('cross', (_) => const ControlTweak());
    expect(tweaks.isEmpty, isTrue);
  });
}
