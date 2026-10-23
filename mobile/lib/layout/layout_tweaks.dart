import 'dart:convert';

import '../ui/pad_layout.dart';

export '../ui/pad_layout.dart' show ButtonBehavior;

/// What the player changed about one control: where it sits, how big and see-through it is,
/// whether it shows, and how it acts. Unset values keep the default layout's.
class ControlTweak {
  const ControlTweak({
    this.x,
    this.y,
    this.scale = 1,
    this.opacity = 1,
    this.hidden = false,
    this.behavior = ButtonBehavior.normal,
  });

  final double? x;
  final double? y;
  final double scale;
  final double opacity;
  final bool hidden;
  final ButtonBehavior behavior;

  bool get isDefault =>
      x == null &&
      y == null &&
      scale == 1 &&
      opacity == 1 &&
      !hidden &&
      behavior == ButtonBehavior.normal;

  ControlTweak copyWith({
    double? x,
    double? y,
    double? scale,
    double? opacity,
    bool? hidden,
    ButtonBehavior? behavior,
  }) => ControlTweak(
    x: x ?? this.x,
    y: y ?? this.y,
    scale: scale ?? this.scale,
    opacity: opacity ?? this.opacity,
    hidden: hidden ?? this.hidden,
    behavior: behavior ?? this.behavior,
  );

  Map<String, Object> toJson() => {
    'x': ?x,
    'y': ?y,
    if (scale != 1) 'scale': scale,
    if (opacity != 1) 'opacity': opacity,
    if (hidden) 'hidden': true,
    if (behavior != ButtonBehavior.normal) 'behavior': behavior.name,
  };

  factory ControlTweak.fromJson(Map<String, dynamic> json) => ControlTweak(
    x: (json['x'] as num?)?.toDouble(),
    y: (json['y'] as num?)?.toDouble(),
    scale: (json['scale'] as num?)?.toDouble() ?? 1,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
    hidden: json['hidden'] == true,
    behavior: ButtonBehavior.values.firstWhere(
      (behavior) => behavior.name == json['behavior'],
      orElse: () => ButtonBehavior.normal,
    ),
  );
}

/// A game's pad layout as the player made it: the default layout plus each control's tweak.
/// It travels as JSON to the launcher, which keeps it with the game's settings.
class LayoutTweaks {
  const LayoutTweaks(this.controls);

  static const none = LayoutTweaks({});

  final Map<String, ControlTweak> controls;

  bool get isEmpty => controls.isEmpty;

  ControlTweak of(String id) => controls[id] ?? const ControlTweak();

  LayoutTweaks change(String id, ControlTweak Function(ControlTweak) edit) {
    final next = edit(of(id));
    return LayoutTweaks({
      for (final entry in controls.entries)
        if (entry.key != id) entry.key: entry.value,
      if (!next.isDefault) id: next,
    });
  }

  PadLayout apply(PadLayout base) => PadLayout([
    for (final control in base.controls)
      if (controls[control.id] case final tweak?)
        control.copyWith(
          x: tweak.x,
          y: tweak.y,
          size: control.size * tweak.scale,
          width: control.width * tweak.scale,
          height: control.height * tweak.scale,
          opacity: tweak.opacity,
          hidden: tweak.hidden,
          behavior: tweak.behavior,
        )
      else
        control,
  ]);

  /// Nothing to save for the default layout.
  String? toJson() => isEmpty
      ? null
      : jsonEncode({
          for (final entry in controls.entries) entry.key: entry.value.toJson(),
        });

  static LayoutTweaks fromJson(String? text) {
    if (text == null) return none;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return none;
      return LayoutTweaks({
        for (final entry in json.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: ControlTweak.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      });
    } on FormatException {
      return none;
    }
  }
}
