import 'dart:typed_data';

import '../feedback/motion.dart';

/// The engine's pad button bits (libScePad PadButton).
abstract final class PadButton {
  static const l3 = 0x0002;
  static const r3 = 0x0004;
  static const options = 0x0008;
  static const up = 0x0010;
  static const right = 0x0020;
  static const down = 0x0040;
  static const left = 0x0080;
  static const l2 = 0x0100;
  static const r2 = 0x0200;
  static const l1 = 0x0400;
  static const r1 = 0x0800;
  static const triangle = 0x1000;
  static const circle = 0x2000;
  static const cross = 0x4000;
  static const square = 0x8000;
  static const touchPad = 0x100000;
}

/// A finger on the DualSense touchpad, in its 1920 × 1080 space.
class TouchPoint {
  TouchPoint({this.active = false, this.id = 0, this.x = 0, this.y = 0});

  bool active;
  int id;
  int x;
  int y;

  TouchPoint copy() => TouchPoint(active: active, id: id, x: x, y: y);
}

/// The whole pad as the phone holds it: every packet carries all of it.
class PadState {
  int buttons = 0;

  /// Left x, left y, right x, right y: 0 to 255, 128 at the centre, up is 0.
  List<int> sticks = [128, 128, 128, 128];
  int l2 = 0;
  int r2 = 0;
  List<TouchPoint> touch = [TouchPoint(), TouchPoint()];

  PadState copy() => PadState()
    ..buttons = buttons
    ..sticks = List.of(sticks)
    ..l2 = l2
    ..r2 = r2
    ..touch = touch.map((point) => point.copy()).toList();
}

const inputMagic = 0x49525041;
const outputMagic = 0x4F525041;
const protocolVersion = 1;
const inputSize = 80;
const outputSize = 32;

/// The 80-byte input packet of the engine's RemotePad wire format.
Uint8List encodeInput({
  required int sequence,
  required int sentMicros,
  required BigInt session,
  required PadState state,
  Motion? motion,
}) {
  final bytes = Uint8List(inputSize);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, inputMagic, Endian.little);
  data.setUint16(4, protocolVersion, Endian.little);
  data.setUint16(6, inputSize, Endian.little);
  data.setUint32(8, sequence & 0xFFFFFFFF, Endian.little);
  data.setUint64(16, sentMicros, Endian.little);
  data.setUint64(
    24,
    session.toUnsigned(64).toSigned(64).toInt(),
    Endian.little,
  );
  data.setUint32(32, state.buttons, Endian.little);
  for (var axis = 0; axis < 4; axis++) {
    bytes[36 + axis] = state.sticks[axis].clamp(0, 255);
  }
  bytes[40] = state.l2.clamp(0, 255);
  bytes[41] = state.r2.clamp(0, 255);
  for (var point = 0; point < 2; point++) {
    final touch = state.touch[point];
    final offset = 44 + point * 6;
    bytes[offset] = touch.active ? 1 : 0;
    bytes[offset + 1] = touch.id & 0xFF;
    data.setUint16(offset + 2, touch.x.clamp(0, 1919), Endian.little);
    data.setUint16(offset + 4, touch.y.clamp(0, 1079), Endian.little);
  }
  if (motion == null) {
    data.setFloat32(60, 9.80665, Endian.little);
    return bytes;
  }
  data.setUint32(12, 1, Endian.little);
  final values = [
    motion.accel.x,
    motion.accel.y,
    motion.accel.z,
    motion.gyro.x,
    motion.gyro.y,
    motion.gyro.z,
  ];
  for (var index = 0; index < values.length; index++) {
    data.setFloat32(56 + index * 4, values[index], Endian.little);
  }
  return bytes;
}

/// What the game sends back for an input: its vibration, light bar and trigger fallbacks, and
/// the echo the phone measures latency from.
class Output {
  Output({
    required this.sequence,
    required this.waitMicros,
    required this.sentMicros,
    required this.large,
    required this.small,
    required this.lightValid,
    required this.r,
    required this.g,
    required this.b,
    required this.l2Fallback,
    required this.r2Fallback,
  });

  final int sequence;

  /// How long the input waited in the engine's socket before the game read it.
  final int waitMicros;
  final int sentMicros;
  final int large;
  final int small;
  final bool lightValid;
  final int r;
  final int g;
  final int b;
  final int l2Fallback;
  final int r2Fallback;
}

Output? decodeOutput(Uint8List bytes) {
  if (bytes.length != outputSize) return null;
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != outputMagic ||
      data.getUint16(4, Endian.little) != protocolVersion ||
      data.getUint16(6, Endian.little) != outputSize) {
    return null;
  }
  return Output(
    sequence: data.getUint32(8, Endian.little),
    waitMicros: data.getUint32(12, Endian.little),
    sentMicros: data.getUint64(16, Endian.little),
    large: bytes[24],
    small: bytes[25],
    lightValid: bytes[26] != 0,
    r: bytes[27],
    g: bytes[28],
    b: bytes[29],
    l2Fallback: bytes[30],
    r2Fallback: bytes[31],
  );
}
