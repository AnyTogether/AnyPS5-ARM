import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

class Vector {
  const Vector(this.x, this.y, this.z);

  static const zero = Vector(0, 0, 0);

  final double x;
  final double y;
  final double z;
}

/// The pad's motion as the engine reads it: acceleration in m/s², gravity included, and angular
/// velocity in rad/s, in the DualSense's frame (x left to right, y up out of its face, z toward
/// the player).
class Motion {
  const Motion(this.accel, this.gyro);

  final Vector accel;
  final Vector gyro;
}

/// Which way the phone is turned to be held like a pad: its top edge to the left or the right.
enum PadRotation { topLeft, topRight }

/// The phone's sensors (x right, y up and z out of the screen when held upright) as the pad's.
Motion toPad(Vector accel, Vector gyro, PadRotation rotation) {
  Vector turn(Vector v) => switch (rotation) {
    PadRotation.topLeft => Vector(-v.y, v.z, -v.x),
    PadRotation.topRight => Vector(v.y, v.z, v.x),
  };
  return Motion(turn(accel), turn(gyro));
}

/// The phone's accelerometer and gyroscope while the pad shows, turned into the pad's frame.
class MotionSource {
  static const rotationChannel = MethodChannel('org.anyps5.remote/device');
  static const interval = Duration(milliseconds: 10);

  bool enabled = true;
  Vector _accel = const Vector(0, 0, 9.80665);
  Vector _gyro = Vector.zero;
  bool _seen = false;
  PadRotation _rotation = PadRotation.topLeft;
  final _subscriptions = <StreamSubscription<Object>>[];
  Timer? _rotationCheck;

  /// The latest motion, nil while off or before the sensors have spoken.
  Motion? get latest =>
      enabled && _seen ? toPad(_accel, _gyro, _rotation) : null;

  void start() {
    if (_subscriptions.isNotEmpty) return;
    try {
      _subscriptions
        ..add(
          accelerometerEventStream(samplingPeriod: interval).listen((event) {
            _accel = Vector(event.x, event.y, event.z);
            _seen = true;
          }, onError: (Object _) {}),
        )
        ..add(
          gyroscopeEventStream(samplingPeriod: interval).listen((event) {
            _gyro = Vector(event.x, event.y, event.z);
          }, onError: (Object _) {}),
        );
    } on Object {
      return;
    }
    _readRotation();
    _rotationCheck = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _readRotation(),
    );
  }

  void stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _rotationCheck?.cancel();
    _rotationCheck = null;
    _seen = false;
  }

  Future<void> _readRotation() async {
    try {
      final answer = await rotationChannel.invokeMethod<String>('rotation');
      _rotation = answer == 'topRight'
          ? PadRotation.topRight
          : PadRotation.topLeft;
    } on Object {
      return;
    }
  }
}
