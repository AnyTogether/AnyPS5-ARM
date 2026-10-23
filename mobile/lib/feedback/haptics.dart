import 'package:flutter/services.dart';

import '../protocol/packets.dart';

/// What the phone's vibration does: how strong (0 to 255) and how sharp (0 dull to 1 crisp).
class Rumble {
  const Rumble(this.strength, this.sharpness);

  static const off = Rumble(0, 0);

  final int strength;
  final double sharpness;

  @override
  bool operator ==(Object other) =>
      other is Rumble &&
      other.strength == strength &&
      other.sharpness == sharpness;

  @override
  int get hashCode => Object.hash(strength, sharpness);
}

abstract interface class HapticsOutput {
  void set(Rumble rumble);
}

/// The game's pad output as the phone's vibration: the two motors (the large one dull, the
/// small one crisp) and, while L2 or R2 is held, a pulse where the DualSense trigger would push
/// back. Only changes are passed on.
class HapticsDriver {
  HapticsDriver(this.output);

  static const step = 8;
  static const pulsePeriod = Duration(milliseconds: 100);
  static const pulseOn = Duration(milliseconds: 40);

  final HapticsOutput output;
  bool enabled = true;
  Rumble _last = Rumble.off;

  void update(
    Output answer, {
    required bool l2Held,
    required bool r2Held,
    required Duration now,
  }) {
    var strength = answer.large > answer.small ? answer.large : answer.small;
    final motors = answer.large + answer.small;
    var sharpness = motors == 0 ? 0.5 : 0.15 + 0.75 * answer.small / motors;
    var trigger = 0;
    if (l2Held && answer.l2Fallback > trigger) trigger = answer.l2Fallback;
    if (r2Held && answer.r2Fallback > trigger) trigger = answer.r2Fallback;
    final pulsing =
        now.inMicroseconds % pulsePeriod.inMicroseconds <
        pulseOn.inMicroseconds;
    if (trigger > 0 && pulsing && trigger > strength) {
      strength = trigger;
      sharpness = 0.9;
    }
    _send(enabled ? strength : 0, sharpness);
  }

  void stop() => _send(0, 0);

  void _send(int strength, double sharpness) {
    final quantized = strength == 0
        ? 0
        : ((strength + step - 1) ~/ step * step).clamp(step, 255);
    final rumble = quantized == 0
        ? Rumble.off
        : Rumble(quantized, (sharpness * 4).round() / 4);
    if (rumble == _last) return;
    _last = rumble;
    output.set(rumble);
  }
}

/// The light bar's colour when the game sets one, for the pad's glow.
Color? lightColor(Output? answer) {
  if (answer == null || !answer.lightValid) return null;
  if (answer.r == 0 && answer.g == 0 && answer.b == 0) return null;
  return Color.fromARGB(255, answer.r, answer.g, answer.b);
}

/// The vibration through MainActivity (Android, amplitude-controlled) or AppDelegate (iOS,
/// Core Haptics).
class PlatformHaptics implements HapticsOutput {
  static const channel = MethodChannel('org.anyps5.remote/haptics');

  @override
  void set(Rumble rumble) {
    channel
        .invokeMethod<void>('set', {
          'strength': rumble.strength,
          'sharpness': rumble.sharpness,
        })
        .catchError((Object _) {});
  }
}
