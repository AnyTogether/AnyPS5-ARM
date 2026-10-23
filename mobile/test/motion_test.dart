import 'dart:typed_data';

import 'package:anyps5_remote/feedback/motion.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a phone lying face up is a pad lying face up, whichever way it is turned',
    () {
      for (final rotation in PadRotation.values) {
        final pad = toPad(
          const Vector(0, 0, 9.81),
          const Vector(0, 0, 0),
          rotation,
        );
        expect(pad.accel.x, closeTo(0, 1e-9));
        expect(pad.accel.y, closeTo(9.81, 1e-9));
        expect(pad.accel.z, closeTo(0, 1e-9));
      }
    },
  );

  test('with its top to the left, the phone\'s top is the pad\'s left and its right edge points away', () {
    final pad = toPad(
      const Vector(1, 2, 3),
      const Vector(4, 5, 6),
      PadRotation.topLeft,
    );
    expect([pad.accel.x, pad.accel.y, pad.accel.z], [-2, 3, -1]);
    expect([pad.gyro.x, pad.gyro.y, pad.gyro.z], [-5, 6, -4]);
  });

  test('with its top to the right, the other way round', () {
    final pad = toPad(
      const Vector(1, 2, 3),
      const Vector(4, 5, 6),
      PadRotation.topRight,
    );
    expect([pad.accel.x, pad.accel.y, pad.accel.z], [2, 3, 1]);
    expect([pad.gyro.x, pad.gyro.y, pad.gyro.z], [5, 6, 4]);
  });

  Uint8List encode(Motion? motion) => encodeInput(
    sequence: 1,
    sentMicros: 0,
    session: BigInt.one,
    state: PadState(),
    motion: motion,
  );

  test('motion goes in the packet with its flag', () {
    final bytes = ByteData.sublistView(
      encode(const Motion(Vector(0.5, 9.0, -1.5), Vector(0.25, -0.75, 2))),
    );
    expect(bytes.getUint32(12, Endian.little) & 1, 1);
    expect(bytes.getFloat32(56, Endian.little), 0.5);
    expect(bytes.getFloat32(60, Endian.little), 9.0);
    expect(bytes.getFloat32(64, Endian.little), -1.5);
    expect(bytes.getFloat32(68, Endian.little), 0.25);
    expect(bytes.getFloat32(72, Endian.little), -0.75);
    expect(bytes.getFloat32(76, Endian.little), 2);
  });

  test('without motion the packet says so and holds a pad at rest', () {
    final bytes = ByteData.sublistView(encode(null));
    expect(bytes.getUint32(12, Endian.little) & 1, 0);
    expect(bytes.getFloat32(60, Endian.little), closeTo(9.80665, 1e-4));
  });
}
