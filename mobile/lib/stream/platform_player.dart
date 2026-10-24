import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'stream_packets.dart';
import 'stream_player.dart';

/// Remote Play drawn and heard on the phone: the phone's own video decoder draws into a Flutter
/// texture ([texture]), and the sound plays through its speaker, gathered 20 ms at a time.
class PlatformStreamPlayer implements StreamPlayer {
  static const channel = MethodChannel('org.anyps5.remote/stream');

  PlatformStreamPlayer() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'size') {
        final values = (call.arguments as List).cast<int>();
        size.value = Size(values[0].toDouble(), values[1].toDouble());
      }
    });
  }

  /// The texture the picture is in, once the first frame came.
  final texture = ValueNotifier<int?>(null);

  /// The picture's size, once the decoder knows it.
  final size = ValueNotifier<Size?>(null);

  bool _opening = false;
  final _sound = BytesBuilder(copy: false);
  int _soundPackets = 0;

  @override
  void frame(VideoFrame frame) {
    if (texture.value == null && !_opening) {
      // The decoder starts at a key frame. Calls arrive in order, so frames sent while the
      // texture opens follow it.
      if (!frame.key) return;
      _opening = true;
      channel
          .invokeMethod<int>('open')
          .then(
            (id) {
              _opening = false;
              texture.value = id;
            },
            onError: (Object _) {
              _opening = false;
            },
          );
    }
    channel.invokeMethod('frame', {
      'data': frame.data,
      'key': frame.key,
      'milliseconds': frame.milliseconds,
    });
  }

  @override
  void sound(AudioPacket packet) {
    _sound.add(packet.samples);
    if (++_soundPackets < 4) return;
    _soundPackets = 0;
    channel.invokeMethod('sound', {'data': _sound.takeBytes()});
  }

  @override
  void stop() {
    if (texture.value == null) return;
    texture.value = null;
    size.value = null;
    _sound.clear();
    _soundPackets = 0;
    channel.invokeMethod('close');
  }
}

/// Remote Play's picture, as large as fits with its shape kept, black around it.
class StreamView extends StatelessWidget {
  const StreamView({super.key, required this.player, this.notice});

  final PlatformStreamPlayer player;

  /// Said in the middle while there is no picture (no permission on the Mac).
  final String? notice;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF000000),
    child: ValueListenableBuilder<int?>(
      valueListenable: player.texture,
      builder: (context, texture, _) => texture == null
          ? Center(
              child: notice == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(48),
                      child: Text(
                        notice!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 14,
                        ),
                      ),
                    ),
            )
          : ValueListenableBuilder<Size?>(
              valueListenable: player.size,
              builder: (context, size, _) => Center(
                child: AspectRatio(
                  aspectRatio: size == null || size.height == 0
                      ? 16 / 9
                      : size.width / size.height,
                  child: Texture(textureId: texture),
                ),
              ),
            ),
    ),
  );
}
