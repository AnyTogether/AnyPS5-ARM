import 'dart:ui';

import '../protocol/packets.dart';

enum ControlKind { button, trigger, stick, touchPad }

/// How a button acts on its press: held while touched, latched by one tap and let go by the
/// next, or pressed again and again while touched.
enum ButtonBehavior { normal, toggle, turbo }

/// One control of the pad: where it sits as a fraction of the screen, and how big it is as a
/// fraction of the screen's height (a radius, or a width and height for rectangles).
class PadControl {
  const PadControl(
    this.id,
    this.kind,
    this.x,
    this.y, {
    this.size = 0.065,
    this.width = 0,
    this.height = 0,
    this.bit = 0,
    this.label = '',
    this.opacity = 1,
    this.hidden = false,
    this.behavior = ButtonBehavior.normal,
  });

  final String id;
  final ControlKind kind;
  final double x;
  final double y;
  final double size;
  final double width;
  final double height;
  final int bit;
  final String label;
  final double opacity;
  final bool hidden;
  final ButtonBehavior behavior;

  bool get isRect => width > 0;

  PadControl copyWith({
    double? x,
    double? y,
    double? size,
    double? width,
    double? height,
    double? opacity,
    bool? hidden,
    ButtonBehavior? behavior,
  }) => PadControl(
    id,
    kind,
    x ?? this.x,
    y ?? this.y,
    size: size ?? this.size,
    width: width ?? this.width,
    height: height ?? this.height,
    bit: bit,
    label: label,
    opacity: opacity ?? this.opacity,
    hidden: hidden ?? this.hidden,
    behavior: behavior ?? this.behavior,
  );
}

/// The fixed DualSense layout of phase 1, landscape.
class PadLayout {
  const PadLayout(this.controls);

  final List<PadControl> controls;

  static const standard = PadLayout([
    PadControl(
      'l1',
      ControlKind.button,
      0.08,
      0.06,
      width: 0.10,
      height: 0.09,
      bit: PadButton.l1,
      label: 'L1',
    ),
    PadControl(
      'l2',
      ControlKind.trigger,
      0.20,
      0.06,
      width: 0.10,
      height: 0.09,
      bit: PadButton.l2,
      label: 'L2',
    ),
    PadControl(
      'r2',
      ControlKind.trigger,
      0.80,
      0.06,
      width: 0.10,
      height: 0.09,
      bit: PadButton.r2,
      label: 'R2',
    ),
    PadControl(
      'r1',
      ControlKind.button,
      0.92,
      0.06,
      width: 0.10,
      height: 0.09,
      bit: PadButton.r1,
      label: 'R1',
    ),
    PadControl(
      'touchPad',
      ControlKind.touchPad,
      0.50,
      0.10,
      width: 0.30,
      height: 0.14,
      bit: PadButton.touchPad,
    ),
    // Not a pad button: it takes the phone back to the launcher.
    PadControl('ps', ControlKind.button, 0.50, 0.86, size: 0.055, label: 'PS'),
    // Not a pad button either: Create, as on the DualSense, saves the last seconds as a clip.
    PadControl(
      'create',
      ControlKind.button,
      0.28,
      0.16,
      size: 0.045,
      label: '◉',
    ),
    PadControl(
      'options',
      ControlKind.button,
      0.72,
      0.16,
      size: 0.045,
      bit: PadButton.options,
      label: '≡',
    ),
    PadControl(
      'up',
      ControlKind.button,
      0.14,
      0.17,
      size: 0.055,
      bit: PadButton.up,
      label: '▲',
    ),
    PadControl(
      'down',
      ControlKind.button,
      0.14,
      0.37,
      size: 0.055,
      bit: PadButton.down,
      label: '▼',
    ),
    PadControl(
      'left',
      ControlKind.button,
      0.14 - 0.10 * 0.5,
      0.27,
      size: 0.055,
      bit: PadButton.left,
      label: '◀',
    ),
    PadControl(
      'right',
      ControlKind.button,
      0.14 + 0.10 * 0.5,
      0.27,
      size: 0.055,
      bit: PadButton.right,
      label: '▶',
    ),
    PadControl(
      'triangle',
      ControlKind.button,
      0.86,
      0.30,
      bit: PadButton.triangle,
      label: '△',
    ),
    PadControl(
      'circle',
      ControlKind.button,
      0.86 + 0.12 * 0.5,
      0.42,
      bit: PadButton.circle,
      label: '○',
    ),
    PadControl(
      'cross',
      ControlKind.button,
      0.86,
      0.54,
      bit: PadButton.cross,
      label: '✕',
    ),
    PadControl(
      'square',
      ControlKind.button,
      0.86 - 0.12 * 0.5,
      0.42,
      bit: PadButton.square,
      label: '□',
    ),
    PadControl(
      'leftStick',
      ControlKind.stick,
      0.18,
      0.62,
      size: 0.13,
      bit: PadButton.l3,
    ),
    PadControl(
      'rightStick',
      ControlKind.stick,
      0.68,
      0.72,
      size: 0.13,
      bit: PadButton.r3,
    ),
  ]);

  PadControl control(String id) =>
      controls.firstWhere((control) => control.id == id);

  Offset center(String id, Size size) {
    final control = this.control(id);
    return Offset(control.x * size.width, control.y * size.height);
  }

  double radius(String id, Size size) => control(id).size * size.height;

  Rect rect(PadControl control, Size size) => Rect.fromCenter(
    center: Offset(control.x * size.width, control.y * size.height),
    width: control.width * size.width,
    height: control.height * size.height,
  );

  /// The control a finger at [point] presses: buttons first, then sticks (which take a finger a
  /// little outside their ring), then the touchpad.
  /// Hidden controls are left out unless [includeHidden], for the layout editor.
  PadControl? hit(Offset point, Size size, {bool includeHidden = false}) {
    final shown = controls.where((control) => includeHidden || !control.hidden);
    for (final control in shown.where(
      (control) =>
          control.kind == ControlKind.button ||
          control.kind == ControlKind.trigger,
    )) {
      if (control.isRect
          ? rect(control, size).inflate(4).contains(point)
          : (point - Offset(control.x * size.width, control.y * size.height))
                    .distance <=
                control.size * size.height * 1.25) {
        return control;
      }
    }
    for (final control in shown.where(
      (control) => control.kind == ControlKind.stick,
    )) {
      if ((point - Offset(control.x * size.width, control.y * size.height))
              .distance <=
          control.size * size.height * 1.5) {
        return control;
      }
    }
    for (final control in shown.where(
      (control) => control.kind == ControlKind.touchPad,
    )) {
      if (rect(control, size).contains(point)) return control;
    }
    return null;
  }
}
