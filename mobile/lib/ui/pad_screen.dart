import 'package:flutter/material.dart';

import '../protocol/packets.dart';
import 'pad_layout.dart';

/// The pad: every finger is given to the control it lands on and keeps it until it lifts, so
/// any number of controls can be held at once. Each change hands [onState] the whole pad.
class PadScreen extends StatefulWidget {
  const PadScreen({
    super.key,
    required this.onState,
    this.layout = PadLayout.standard,
    this.status,
    this.onHome,
    this.glow,
  });

  /// The game's light bar colour, which the pad's background glows with.
  final Color? glow;

  final void Function(PadState state) onState;

  /// The PS button: the launcher, on the phone and on the Mac.
  final VoidCallback? onHome;
  final PadLayout layout;

  /// Drawn at the top: the connection dot and the latency.
  final Widget? status;

  @override
  State<PadScreen> createState() => _PadScreenState();
}

class _Finger {
  _Finger(this.control, this.start);

  final PadControl control;
  final Offset start;
  Offset position = Offset.zero;
  bool clicked = false;
}

class _PadScreenState extends State<PadScreen> {
  static const doubleTap = Duration(milliseconds: 300);
  final _fingers = <int, _Finger>{};
  final _released = <String, Duration>{};
  final _clock = Stopwatch()..start();
  PadState _state = PadState();

  /// A pad that goes away (the connection dropped) lets go of what was held on it.
  @override
  void dispose() {
    if (_fingers.isNotEmpty) widget.onState(PadState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => _down(event, size),
            onPointerMove: (event) => _move(event, size),
            onPointerUp: (event) => _up(event.pointer, size),
            onPointerCancel: (event) => _up(event.pointer, size),
            child: Stack(
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: widget.glow ?? _PadPainter.base),
                    duration: const Duration(milliseconds: 600),
                    builder: (context, glow, _) => CustomPaint(
                      painter: _PadPainter(
                        widget.layout,
                        _state,
                        _fingers.values.toList(),
                        glow,
                      ),
                    ),
                  ),
                ),
                if (widget.status != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: size.height * 0.20,
                    child: Center(child: widget.status!),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _down(PointerDownEvent event, Size size) {
    final control = widget.layout.hit(event.localPosition, size);
    if (control == null) return;
    if (control.id == 'ps') {
      widget.onHome?.call();
      return;
    }
    final finger = _Finger(control, event.localPosition)
      ..position = event.localPosition;
    final released = _released[control.id];
    finger.clicked =
        control.kind == ControlKind.stick &&
        released != null &&
        _clock.elapsed - released < doubleTap;
    _fingers[event.pointer] = finger;
    _publish(size);
  }

  void _move(PointerMoveEvent event, Size size) {
    final finger = _fingers[event.pointer];
    if (finger == null) return;
    finger.position = event.localPosition;
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
    _publish(size);
  }

  /// The pad from the fingers on it now.
  void _publish(Size size) {
    final state = PadState();
    var touchIndex = 0;
    for (final finger in _fingers.values) {
      final control = finger.control;
      switch (control.kind) {
        case ControlKind.button:
          state.buttons |= control.bit;
        case ControlKind.trigger:
          state.buttons |= control.bit;
          if (control.id == 'l2') state.l2 = 255;
          if (control.id == 'r2') state.r2 = 255;
        case ControlKind.stick:
          final centre = widget.layout.center(control.id, size);
          final radius = widget.layout.radius(control.id, size);
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
          final area = widget.layout.rect(control, size);
          state.buttons |= control.bit;
          state.touch[touchIndex] = TouchPoint(
            active: true,
            id: touchIndex,
            x: ((finger.position.dx - area.left) / area.width * 1920)
                .floor()
                .clamp(0, 1919),
            y: ((finger.position.dy - area.top) / area.height * 1080)
                .floor()
                .clamp(0, 1079),
          );
          touchIndex++;
      }
    }
    setState(() => _state = state);
    widget.onState(state.copy());
  }

  static int _axis(double fraction) =>
      (128 + fraction * 127.5).floor().clamp(0, 255);
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.layout, this.state, this.fingers, this.glow);

  final PadLayout layout;
  final Color? glow;
  final PadState state;
  final List<_Finger> fingers;

  static const base = Color(0xFF16181F);
  static const glass = Color(0x1AFFFFFF);
  static const edge = Color(0x24FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
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
    for (final control in layout.controls) {
      final pressed = fingers.any((finger) => finger.control.id == control.id);
      switch (control.kind) {
        case ControlKind.button || ControlKind.trigger:
          _button(canvas, size, control, pressed);
        case ControlKind.stick:
          _stick(canvas, size, control);
        case ControlKind.touchPad:
          final area = RRect.fromRectAndRadius(
            layout.rect(control, size),
            Radius.circular(size.height * 0.03),
          );
          canvas.drawRRect(
            area,
            Paint()
              ..color = pressed
                  ? const Color(0x33FFFFFF)
                  : const Color(0x12FFFFFF),
          );
          canvas.drawRRect(
            area,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = edge,
          );
      }
    }
  }

  void _button(Canvas canvas, Size size, PadControl control, bool pressed) {
    final fill = Paint()..color = pressed ? Colors.white : glass;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = pressed ? Colors.white : edge;
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
          color: pressed ? Colors.black : Colors.white.withValues(alpha: 0.9),
          fontSize: size.height * 0.05,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));
  }

  void _stick(Canvas canvas, Size size, PadControl control) {
    final centre = Offset(control.x * size.width, control.y * size.height);
    final radius = control.size * size.height;
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0x10FFFFFF));
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = edge,
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
      Paint()..color = held ? const Color(0xE6FFFFFF) : const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      !identical(old.state, state) ||
      old.fingers.length != fingers.length ||
      old.layout != layout ||
      old.glow != glow;
}
