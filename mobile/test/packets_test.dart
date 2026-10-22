import 'dart:typed_data';

import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/protocol/packets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes the input packet of the engine test', () {
    final state = PadState()
      ..buttons = PadButton.cross | PadButton.up
      ..sticks = [255, 0, 128, 64]
      ..l2 = 200;
    state.touch[0] = TouchPoint(active: true, id: 3, x: 1919, y: 1079);
    final bytes = encodeInput(
      sequence: 7,
      sentMicros: 123456,
      session: BigInt.from(99),
      state: state,
    );
    expect(bytes.length, 80);
    expect(bytes.sublist(0, 4), [0x41, 0x50, 0x52, 0x49]);
    expect(bytes.sublist(4, 6), [1, 0]);
    expect(bytes.sublist(6, 8), [0x50, 0]);
    expect(bytes.sublist(8, 12), [7, 0, 0, 0]);
    expect(ByteData.sublistView(bytes).getUint64(16, Endian.little), 123456);
    expect(ByteData.sublistView(bytes).getUint64(24, Endian.little), 99);
    expect(bytes.sublist(32, 36), [0x10, 0x40, 0, 0]);
    expect(bytes.sublist(36, 40), [0xFF, 0, 0x80, 0x40]);
    expect(bytes[40], 200);
    expect(bytes.sublist(44, 50), [1, 3, 0x7F, 0x07, 0x37, 0x04]);
  });

  test('encodes a session above 2^63', () {
    final bytes = encodeInput(
      sequence: 0,
      sentMicros: 0,
      session: BigInt.parse('18446744073709551615'),
      state: PadState(),
    );
    expect(bytes.sublist(24, 32), List.filled(8, 0xFF));
  });

  test('decodes the output packet of the engine test', () {
    final bytes = Uint8List(32);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0x4F525041, Endian.little);
    data.setUint16(4, 1, Endian.little);
    data.setUint16(6, 32, Endian.little);
    data.setUint32(8, 9, Endian.little);
    data.setUint32(12, 1500, Endian.little);
    data.setUint64(16, 555, Endian.little);
    bytes.setAll(24, [40, 3, 1, 1, 2, 3, 7, 8]);
    final output = decodeOutput(bytes)!;
    expect(output.sequence, 9);
    expect(output.waitMicros, 1500);
    expect(output.sentMicros, 555);
    expect([output.large, output.small], [40, 3]);
    expect(output.lightValid, isTrue);
    expect([output.r, output.g, output.b], [1, 2, 3]);
    expect([output.l2Fallback, output.r2Fallback], [7, 8]);
    expect(decodeOutput(Uint8List.sublistView(bytes, 0, 31)), isNull);
    bytes[0] = 0;
    expect(decodeOutput(bytes), isNull);
  });

  test('messages round trip as the launcher writes them', () {
    final hello = Hello(deviceID: 'A', deviceName: 'Pixel', key: null);
    expect(Message.fromJson(hello.toJson()), isA<Hello>());
    final welcome = Message.fromJson(
      '{"type":"welcome","session":"18446744073709551615","udpPort":5000,"macName":"Mac","key":"a2V5"}',
    ) as Welcome;
    expect(welcome.session, BigInt.parse('18446744073709551615'));
    expect(welcome.udpPort, 5000);
    expect(
      (Message.fromJson('{"type":"pairing","code":"0042"}') as Pairing).code,
      '0042',
    );
    expect(
      (Message.fromJson(
        '{"type":"rejected","reason":"busy"}',
      ) as Rejected).reason,
      'busy',
    );
    expect(Message.fromJson('{"type":"bogus"}'), isNull);
    expect(Message.fromJson('not json'), isNull);
    expect(Latency(9.5).toJson(), '{"type":"latency","milliseconds":9.5}');
  });
}
