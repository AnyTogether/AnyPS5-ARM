import 'dart:typed_data';

import 'package:anyps5_remote/stream/stream_packets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The launcher's video pieces, written as StreamPacket.video writes them.
List<Uint8List> pieces(
  List<int> frame, {
  required int number,
  bool key = false,
  int milliseconds = 0,
  int room = 1176,
}) {
  final count = (frame.length + room - 1) ~/ room;
  return [
    for (var index = 0; index < count; index++)
      () {
        final payload = frame.sublist(
          index * room,
          (index + 1) * room > frame.length ? frame.length : (index + 1) * room,
        );
        final bytes = Uint8List(24 + payload.length);
        final data = ByteData.sublistView(bytes);
        data.setUint32(0, 0x56525041, Endian.little);
        data.setUint16(4, 1, Endian.little);
        data.setUint16(6, 24, Endian.little);
        data.setUint32(8, number, Endian.little);
        data.setUint16(12, index, Endian.little);
        data.setUint16(14, count, Endian.little);
        data.setUint16(16, key ? 1 : 0, Endian.little);
        data.setUint32(20, milliseconds, Endian.little);
        bytes.setRange(24, bytes.length, payload);
        return bytes;
      }(),
  ];
}

void main() {
  test('a frame comes together from its pieces in any order', () {
    final frames = <VideoFrame>[];
    final assembler = FrameAssembler(onFrame: frames.add, onLoss: () {});
    final frame = List.generate(3000, (index) => index % 256);
    final parts = pieces(frame, number: 1, key: true, milliseconds: 40);
    for (final part in parts.reversed) {
      assembler.add(decodeVideo(part)!);
    }
    expect(frames, hasLength(1));
    expect(frames.single.data, frame);
    expect(frames.single.key, isTrue);
    expect(frames.single.milliseconds, 40);
  });

  /// A frame that never came whole is a hole in the picture: the frames after it wait for a key
  /// frame, which is asked for once.
  test('a lost piece asks for a key frame and skips frames until one', () {
    final frames = <VideoFrame>[];
    var losses = 0;
    final assembler = FrameAssembler(
      onFrame: frames.add,
      onLoss: () => losses++,
    );
    for (final part in pieces(List.filled(100, 1), number: 1, key: true)) {
      assembler.add(decodeVideo(part)!);
    }
    final second = pieces(List.filled(3000, 2), number: 2);
    assembler.add(decodeVideo(second.first)!);
    for (final part in pieces(List.filled(100, 3), number: 3)) {
      assembler.add(decodeVideo(part)!);
    }
    for (final part in pieces(List.filled(100, 4), number: 4)) {
      assembler.add(decodeVideo(part)!);
    }
    expect(frames.map((frame) => frame.data.first), [1]);
    expect(losses, 1);
    for (final part in pieces(List.filled(100, 5), number: 5, key: true)) {
      assembler.add(decodeVideo(part)!);
    }
    expect(frames.map((frame) => frame.data.first), [1, 5]);
  });

  test('a stream joined between key frames asks for one', () {
    final frames = <VideoFrame>[];
    var losses = 0;
    final assembler = FrameAssembler(
      onFrame: frames.add,
      onLoss: () => losses++,
    );
    for (final number in [8, 9, 10]) {
      for (final part in pieces([number], number: number)) {
        assembler.add(decodeVideo(part)!);
      }
    }
    expect(frames, isEmpty);
    expect(losses, 1);
  });

  test('sound packets are read', () {
    final bytes = Uint8List(16 + 960);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0x41525041, Endian.little);
    data.setUint16(4, 1, Endian.little);
    data.setUint16(6, 16, Endian.little);
    data.setUint32(8, 3, Endian.little);
    data.setUint32(12, 77, Endian.little);
    final sound = decodeAudio(bytes)!;
    expect(sound.number, 3);
    expect(sound.milliseconds, 77);
    expect(sound.samples, hasLength(960));
    expect(decodeVideo(bytes), isNull);
    expect(decodeAudio(pieces([1], number: 1).first), isNull);
  });
}
