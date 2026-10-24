import 'dart:async';

import 'package:flutter/material.dart';

import '../layout/layout_tweaks.dart';
import '../protocol/packets.dart';
import '../strings.dart';
import 'pad_layout.dart';

/// The pad: every finger is given to the control it lands on and keeps it until it lifts, so
/// any number of controls can be held at once. Each change hands [onState] the whole pad.
/// The lock opens the layout editor, where controls are moved, sized, faded, hidden and given a
/// behaviour; each change goes to [onTweaks].
class PadScreen extends StatefulWidget {
  const PadScreen({
    super.key,
    required this.onState,
    this.layout = PadLayout.standard,
    this.tweaks = LayoutTweaks.none,
    this.onTweaks,
    this.status,
    this.onHome,
    this.onCapture,
    this.glow,
    this.video,
  });

  final void Function(PadState state) onState;
  final PadLayout layout;

  /// The player's changes to [layout] for this game.
  final LayoutTweaks tweaks;
  final ValueChanged<LayoutTweaks>? onTweaks;

  /// Drawn at the top: the connection dot and the latency.
  final Widget? status;

  /// The PS button: the launcher, on the phone and on the Mac.
  final VoidCallback? onHome;

  /// Create: the Mac saves the last seconds of the game as a clip.
  final VoidCallback? onCapture;

  /// The game's light bar colour, which the pad's background glows with.
  final Color? glow;

  /// Remote Play's picture, drawn behind the controls in place of the pad's background.
  final Widget? video;

  @override
  State<PadScreen> createState() => _PadScreenState();
}

class _Finger {
  _Finger(this.control, this.start);

  final PadControl control;
  final Offset start;
  Offset position = Offset.zero;
  bool clicked = false;

  /// On the touchpad: it slid, so it is a touch and never a click.
  bool moved = false;
  Timer? hold;
}

class _Drag {
  _Drag(this.id, this.start, this.from);

  final String id;
  final Offset start;
  final Offset from;
}

class _PadScreenState extends State<PadScreen> {
  static const doubleTap = Duration(milliseconds: 300);

  /// The touchpad, like the DualSense's: a touch reports where it is, a tap clicks briefly and a
  /// finger held still clicks until it lifts.
  static const touchHold = Duration(milliseconds: 400);
  static const tapClick = Duration(milliseconds: 100);
  static const tapSlop = 0.04;
  static const scaleStep = 0.1;

  final _fingers = <int, _Finger>{};
  final _released = <String, Duration>{};
  final _latched = <String>{};
  final _clock = Stopwatch()..start();
  PadState _state = PadState();
  Timer? _turbo;
  int _turboTicks = 0;
  TouchPoint? _tap;
  Timer? _tapRelease;
  Size _size = Size.zero;

  bool _editing = false;
  String? _selected;
  final _drags = <int, _Drag>{};
  late LayoutTweaks _tweaks = widget.tweaks;

  PadLayout get _layout => _tweaks.apply(widget.layout);

  @override
  void didUpdateWidget(PadScreen old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.tweaks != old.tweaks) _tweaks = widget.tweaks;
  }

  /// A pad that goes away (the connection dropped) lets go of what was held on it.
  @override
  void dispose() {
    _turbo?.cancel();
    _tapRelease?.cancel();
    for (final finger in _fingers.values) {
      finger.hold?.cancel();
    }
    if (_fingers.isNotEmpty || _latched.isNotEmpty) widget.onState(PadState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final layout = _layout;
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          _size = size;
          return Stack(
            children: [
              if (widget.video != null) Positioned.fill(child: widget.video!),
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) =>
                      _editing ? _editDown(event, size) : _down(event, size),
                  onPointerMove: (event) =>
                      _editing ? _editMove(event, size) : _move(event, size),
                  onPointerUp: (event) => _editing
                      ? _drags.remove(event.pointer)
                      : _up(event.pointer, size),
                  onPointerCancel: (event) => _editing
                      ? _drags.remove(event.pointer)
                      : _up(event.pointer, size),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: widget.glow ?? _PadPainter.base),
                    duration: const Duration(milliseconds: 600),
                    builder: (context, glow, _) => CustomPaint(
                      painter: _PadPainter(
                        layout,
                        _state,
                        {
                          ..._fingers.values.map((finger) => finger.control.id),
                          ..._latched,
                        },
                        glow,
                        editing: _editing,
                        selected: _selected,
                        clear: widget.video != null,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.status != null && !_editing)
                Positioned(
                  left: 0,
                  right: 0,
                  top: size.height * 0.20,
                  child: Center(child: widget.status!),
                ),
              if (widget.onTweaks != null)
                Positioned(
                  left: 6,
                  bottom: 2,
                  child: IconButton(
                    tooltip: _editing ? texts.done : texts.editLayout,
                    onPressed: _toggleEditing,
                    icon: Icon(
                      _editing
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded,
                      color: _editing ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              if (_editing)
                Positioned(
                  left: 0,
                  right: 0,
                  // Out of the way of the control being changed: at the top, or at the bottom
                  // for the controls along the top edge.
                  top: _panelBelow(layout) ? null : 8,
                  bottom: _panelBelow(layout) ? 8 : null,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: size.width - 24),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _inspector(texts, layout),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _panelBelow(PadLayout layout) =>
      _selected != null && layout.control(_selected!).y < 0.3;

  static String _badge(PadControl control) => control.label.isNotEmpty
      ? control.label
      : switch (control.id) {
          'leftStick' => 'L',
          'rightStick' => 'R',
          _ => '▭',
        };

  void _toggleEditing() {
    setState(() {
      _editing = !_editing;
      _selected = null;
      _drags.clear();
      _fingers.clear();
      _latched.clear();
    });
    _turbo?.cancel();
    _publish(_size);
  }

  // MARK: Playing

  void _down(PointerDownEvent event, Size size) {
    final control = _layout.hit(event.localPosition, size);
    if (control == null) return;
    if (control.id == 'ps') {
      widget.onHome?.call();
      return;
    }
    if (control.id == 'create') {
      widget.onCapture?.call();
      return;
    }
    if (control.behavior == ButtonBehavior.toggle &&
        control.kind != ControlKind.stick &&
        control.kind != ControlKind.touchPad) {
      _latched.contains(control.id)
          ? _latched.remove(control.id)
          : _latched.add(control.id);
      _publish(size);
      return;
    }
    final finger = _Finger(control, event.localPosition)
      ..position = event.localPosition;
    final released = _released[control.id];
    finger.clicked =
        control.kind == ControlKind.stick &&
        released != null &&
        _clock.elapsed - released < doubleTap;
    if (control.kind == ControlKind.touchPad) {
      finger.hold = Timer(touchHold, () {
        if (!finger.moved && _fingers.containsValue(finger)) {
          finger.clicked = true;
          _publish(_size);
        }
      });
    }
    _fingers[event.pointer] = finger;
    _publish(size);
  }

  void _move(PointerMoveEvent event, Size size) {
    final finger = _fingers[event.pointer];
    if (finger == null) return;
    finger.position = event.localPosition;
    if (finger.control.kind == ControlKind.touchPad &&
        !finger.moved &&
        (finger.position - finger.start).distance >
            tapSlop * _layout.rect(finger.control, size).width) {
      finger.moved = true;
      finger.hold?.cancel();
    }
    if (finger.control.kind == ControlKind.stick ||
        finger.control.kind == ControlKind.touchPad) {
      _publish(size);
    }
  }

  void _up(int pointer, Size size) {
    final finger = _fingers.remove(pointer);
    if (finger == null) return;
    if (finger.control.kind == ControlKind.stick) {
      _released[finger.control.id] = _clock.elapsed;
    }
    finger.hold?.cancel();
    if (finger.control.kind == ControlKind.touchPad &&
        !finger.moved &&
        !finger.clicked) {
      _tap = _touchPoint(finger, size, 0);
      _tapRelease?.cancel();
      _tapRelease = Timer(tapClick, () {
        _tap = null;
        _publish(_size);
      });
    }
    _publish(size);
  }

  /// Turbo buttons are pressed for two ticks of the turbo timer, then let go for two.
  bool get _turboOn => (_turboTicks ~/ 2).isEven;

  /// The pad from the fingers on it now, the latched buttons, and the turbo buttons in their
  /// pressed half.
  void _publish(Size size) {
    final layout = _layout;
    final state = PadState();
    var touchIndex = 0;
    var turbo = false;
    void press(PadControl control) {
      state.buttons |= control.bit;
      if (control.id == 'l2') state.l2 = 255;
      if (control.id == 'r2') state.r2 = 255;
    }

    for (final id in _latched) {
      press(layout.control(id));
    }
    for (final finger in _fingers.values) {
      final control = finger.control;
      switch (control.kind) {
        case ControlKind.button || ControlKind.trigger:
          if (control.behavior == ButtonBehavior.turbo) {
            turbo = true;
            if (!_turboOn) break;
          }
          press(control);
        case ControlKind.stick:
          final centre = layout.center(control.id, size);
          final radius = layout.radius(control.id, size);
          var offset = finger.position - centre;
          if (offset.distance > radius) {
            offset = offset / offset.distance * radius;
          }
          final axis = control.id == 'leftStick' ? 0 : 2;
          state.sticks[axis] = _axis(offset.dx / radius);
          state.sticks[axis + 1] = _axis(offset.dy / radius);
          if (finger.clicked) state.buttons |= control.bit;
        case ControlKind.touchPad:
          if (touchIndex > 1) break;
          if (finger.clicked) state.buttons |= control.bit;
          state.touch[touchIndex] = _touchPoint(finger, size, touchIndex);
          touchIndex++;
      }
    }
    if (_tap case final tap?) {
      state.buttons |= PadButton.touchPad;
      if (!state.touch[0].active) state.touch[0] = tap;
    }
    if (turbo) {
      _turbo ??= Timer.periodic(const Duration(milliseconds: 25), (_) {
        _turboTicks++;
        _publish(_size);
      });
    } else {
      _turbo?.cancel();
      _turbo = null;
      _turboTicks = 0;
    }
    if (mounted) setState(() => _state = state);
    widget.onState(state.copy());
  }

  TouchPoint _touchPoint(_Finger finger, Size size, int id) {
    final area = _layout.rect(finger.control, size);
    return TouchPoint(
      active: true,
      id: id,
      x: ((finger.position.dx - area.left) / area.width * 1920).floor().clamp(
        0,
        1919,
      ),
      y: ((finger.position.dy - area.top) / area.height * 1080).floor().clamp(
        0,
        1079,
      ),
    );
  }

  static int _axis(double fraction) =>
      (128 + fraction * 127.5).floor().clamp(0, 255);

  // MARK: Editing

  void _editDown(PointerDownEvent event, Size size) {
    final control = _layout.hit(event.localPosition, size, includeHidden: true);
    if (control == null) return;
    setState(() => _selected = control.id);
    _drags[event.pointer] = _Drag(
      control.id,
      event.localPosition,
      Offset(control.x, control.y),
    );
  }

  void _editMove(PointerMoveEvent event, Size size) {
    final drag = _drags[event.pointer];
    if (drag == null || size.isEmpty) return;
    final delta = event.localPosition - drag.start;
    _change(
      drag.id,
      (tweak) => tweak.copyWith(
        x: (drag.from.dx + delta.dx / size.width).clamp(0.03, 0.97),
        y: (drag.from.dy + delta.dy / size.height).clamp(0.05, 0.95),
      ),
    );
  }

  void _change(String id, ControlTweak Function(ControlTweak) edit) {
    setState(() => _tweaks = _tweaks.change(id, edit));
    widget.onTweaks?.call(_tweaks);
  }

  Widget _inspector(Strings texts, PadLayout layout) {
    final id = _selected;
    final control = id == null ? null : layout.control(id);
    final tweak = id == null ? const ControlTweak() : _tweaks.of(id);
    Widget pill(String label, bool on, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? Colors.white : const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    final pressable =
        control != null &&
        (control.kind == ControlKind.button ||
            control.kind == ControlKind.trigger);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6101218),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: control == null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texts.editHint,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 12),
                pill(texts.resetAll, false, () {
                  setState(() => _tweaks = LayoutTweaks.none);
                  widget.onTweaks?.call(_tweaks);
                }),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 34),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: const Color(0xFF8AB4FF),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    _badge(control),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _change(
                    control.id,
                    (t) => t.copyWith(
                      scale: (t.scale - scaleStep).clamp(0.5, 2.0),
                    ),
                  ),
                  icon: const Icon(Icons.remove_rounded, color: Colors.white),
                ),
                Text(
                  '${(tweak.scale * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _change(
                    control.id,
                    (t) => t.copyWith(
                      scale: (t.scale + scaleStep).clamp(0.5, 2.0),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                ),
                SizedBox(
                  width: 110,
                  child: Slider(
                    value: tweak.opacity,
                    min: 0.2,
                    onChanged: (value) =>
                        _change(control.id, (t) => t.copyWith(opacity: value)),
                  ),
                ),
                pill(
                  texts.hide,
                  tweak.hidden,
                  () =>
                      _change(control.id, (t) => t.copyWith(hidden: !t.hidden)),
                ),
                if (pressable) ...[
                  const SizedBox(width: 6),
                  for (final behavior in ButtonBehavior.values)
                    pill(
                      texts.behavior(behavior),
                      tweak.behavior == behavior,
                      () => _change(
                        control.id,
                        (t) => t.copyWith(behavior: behavior),
                      ),
                    ),
                ],
                const SizedBox(width: 6),
                pill(
                  texts.reset,
                  false,
                  () => _change(control.id, (_) => const ControlTweak()),
                ),
              ],
            ),
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(
    this.layout,
    this.state,
    this.pressed,
    this.glow, {
    required this.editing,
    required this.selected,
    this.clear = false,
  });

  final PadLayout layout;
  final PadState state;
  final Set<String> pressed;
  final Color? glow;
  final bool editing;
  final String? selected;

  /// The game shows behind: no background of its own.
  final bool clear;

  static const base = Color(0xFF16181F);
  static const glass = Color(0x1AFFFFFF);
  static const edge = Color(0x24FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    if (!clear) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(base, glow ?? base, 0.38)!,
              const Color(0xFF07080B),
            ],
            radius: 1.1,
          ).createShader(Offset.zero & size),
      );
    }
    for (final control in layout.controls) {
      if (control.hidden && !editing) continue;
      final fade = control.hidden ? 0.25 : control.opacity;
      final down = pressed.contains(control.id);
      switch (control.kind) {
        case ControlKind.button || ControlKind.trigger:
          _button(canvas, size, control, down, fade);
        case ControlKind.stick:
          _stick(canvas, size, control, fade);
        case ControlKind.touchPad:
          final area = RRect.fromRectAndRadius(
            layout.rect(control, size),
            Radius.circular(size.height * 0.03),
          );
          canvas.drawRRect(
            area,
            Paint()
              ..color = _fade(
                down ? const Color(0x33FFFFFF) : const Color(0x12FFFFFF),
                fade,
              ),
          );
          canvas.drawRRect(
            area,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = _fade(edge, fade),
          );
      }
      if (editing && control.id == selected) _outline(canvas, size, control);
    }
  }

  static Color _fade(Color color, double fade) =>
      color.withValues(alpha: color.a * fade);

  void _outline(Canvas canvas, Size size, PadControl control) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF8AB4FF);
    if (control.isRect) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          layout.rect(control, size).inflate(5),
          Radius.circular(size.height * 0.03),
        ),
        paint,
      );
    } else {
      canvas.drawCircle(
        Offset(control.x * size.width, control.y * size.height),
        control.size * size.height + 5,
        paint,
      );
    }
  }

  void _button(
    Canvas canvas,
    Size size,
    PadControl control,
    bool down,
    double fade,
  ) {
    final fill = Paint()..color = _fade(down ? Colors.white : glass, fade);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _fade(down ? Colors.white : edge, fade);
    final centre = Offset(control.x * size.width, control.y * size.height);
    if (control.isRect) {
      final area = RRect.fromRectAndRadius(
        layout.rect(control, size),
        Radius.circular(size.height * 0.025),
      );
      canvas.drawRRect(area, fill);
      canvas.drawRRect(area, stroke);
    } else {
      final radius = control.size * size.height;
      canvas.drawCircle(centre, radius, fill);
      canvas.drawCircle(centre, radius, stroke);
    }
    final text = TextPainter(
      text: TextSpan(
        text: control.label,
        style: TextStyle(
          color: _fade(
            down ? Colors.black : Colors.white.withValues(alpha: 0.9),
            fade,
          ),
          fontSize:
              size.height *
              0.05 *
              (control.isRect ? control.height / 0.07 : control.size / 0.065)
                  .clamp(0.7, 1.6),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));
  }

  void _stick(Canvas canvas, Size size, PadControl control, double fade) {
    final centre = Offset(control.x * size.width, control.y * size.height);
    final radius = control.size * size.height;
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = _fade(const Color(0x10FFFFFF), fade),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _fade(edge, fade),
    );
    final axis = control.id == 'leftStick' ? 0 : 2;
    final knob =
        centre +
        Offset(
          (state.sticks[axis] - 128) / 127.5 * radius,
          (state.sticks[axis + 1] - 128) / 127.5 * radius,
        );
    final held = state.sticks[axis] != 128 || state.sticks[axis + 1] != 128;
    canvas.drawCircle(
      knob,
      radius * 0.48,
      Paint()
        ..color = _fade(
          held ? const Color(0xE6FFFFFF) : const Color(0x33FFFFFF),
          fade,
        ),
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      !identical(old.state, state) ||
      old.pressed.length != pressed.length ||
      old.layout != layout ||
      old.glow != glow ||
      old.editing != editing ||
      old.selected != selected ||
      old.clear != clear;
}
