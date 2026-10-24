import 'stream_packets.dart';

/// Where Remote Play's frames and sound go: the phone's video decoder and speaker.
abstract class StreamPlayer {
  void frame(VideoFrame frame);
  void sound(AudioPacket packet);

  /// The stream ended: the picture goes and the sound stops.
  void stop();
}
