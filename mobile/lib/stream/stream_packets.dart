import 'dart:typed_data';

/// Remote Play's datagrams from the launcher (StreamPacket on the Mac): video frames in pieces
/// and sound, little-endian with a magic, a version and the header's size up front.
const videoMagic = 0x56525041;
const audioMagic = 0x41525041;
const videoHeader = 24;
const audioHeader = 16;

class VideoPiece {
  VideoPiece({
    required this.number,
    required this.index,
    required this.count,
    required this.key,
    required this.milliseconds,
    required this.payload,
  });

  final int number;
  final int index;
  final int count;
  final bool key;
  final int milliseconds;
  final Uint8List payload;
}

class AudioPacket {
  AudioPacket(this.number, this.milliseconds, this.samples);

  final int number;
  final int milliseconds;

  /// 16-bit stereo at 48 kHz.
  final Uint8List samples;
}

/// A whole frame: start-code H.264, a key frame with its parameter sets.
class VideoFrame {
  VideoFrame(this.data, {required this.key, required this.milliseconds});

  final Uint8List data;
  final bool key;
  final int milliseconds;
}

bool _header(ByteData data, int magic, int size) =>
    data.lengthInBytes >= size &&
    data.getUint32(0, Endian.little) == magic &&
    data.getUint16(4, Endian.little) == 1 &&
    data.getUint16(6, Endian.little) == size;

VideoPiece? decodeVideo(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (!_header(data, videoMagic, videoHeader)) return null;
  final index = data.getUint16(12, Endian.little);
  final count = data.getUint16(14, Endian.little);
  if (count == 0 || index >= count) return null;
  return VideoPiece(
    number: data.getUint32(8, Endian.little),
    index: index,
    count: count,
    key: data.getUint16(16, Endian.little) & 1 != 0,
    milliseconds: data.getUint32(20, Endian.little),
    payload: Uint8List.sublistView(bytes, videoHeader),
  );
}

AudioPacket? decodeAudio(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (!_header(data, audioMagic, audioHeader)) return null;
  return AudioPacket(
    data.getUint32(8, Endian.little),
    data.getUint32(12, Endian.little),
    Uint8List.sublistView(bytes, audioHeader),
  );
}

/// Puts frames together from their pieces. A frame that a newer one overtook before it came
/// whole is lost: the frames after it would show a broken picture, so they are skipped until a
/// key frame, which [onLoss] asks for.
class FrameAssembler {
  FrameAssembler({required this.onFrame, required this.onLoss});

  final void Function(VideoFrame frame) onFrame;
  final void Function() onLoss;

  final _pending = <int, List<Uint8List?>>{};
  final _keys = <int>{};
  final _times = <int, int>{};
  int _last = -1;
  bool _waitingForKey = true;
  bool _asked = false;

  void add(VideoPiece piece) {
    if (_last >= 0 && piece.number <= _last) return;
    final parts = _pending.putIfAbsent(
      piece.number,
      () => List<Uint8List?>.filled(piece.count, null),
    );
    if (parts.length != piece.count) return;
    parts[piece.index] = piece.payload;
    if (piece.key) _keys.add(piece.number);
    _times[piece.number] = piece.milliseconds;
    if (parts.contains(null)) return;
    final number = piece.number;
    final key = _keys.contains(number);
    // Older frames still in pieces will never be shown.
    final lost = _pending.keys.where((other) => other < number).toList();
    for (final other in [...lost, number]) {
      _pending.remove(other);
      _keys.remove(other);
    }
    final milliseconds = _times.remove(number) ?? 0;
    _times.removeWhere((other, _) => other < number);
    final gap = _last >= 0 && number != _last + 1;
    _last = number;
    if ((gap || lost.isNotEmpty) && !key) _waitingForKey = true;
    if (_waitingForKey && !key) {
      // Joined mid-stream or lost a frame: one key frame is asked for until it comes.
      if (!_asked) onLoss();
      _asked = true;
      return;
    }
    _waitingForKey = false;
    _asked = false;
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part!);
    }
    onFrame(
      VideoFrame(builder.takeBytes(), key: key, milliseconds: milliseconds),
    );
  }
}
