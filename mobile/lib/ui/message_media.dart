import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media_strings.dart';
import '../strings.dart';
import '../together/messages.dart';
import '../together/storage.dart';
import 'together_widgets.dart';

/// "1:05"
String clockOf(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The media a message holds, as its bubble shows it: a photo, a clip's poster, a voice note
/// to play, or why it is not there. The links are signed and need no token.
class MessageMedia extends StatelessWidget {
  const MessageMedia({super.key, required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final attachment = message.attachments.firstOrNull;
    if (attachment == null) return const SizedBox.shrink();
    if (attachment.removed || attachment.blocked || !attachment.shown) {
      return _Gone(
        text: attachment.blocked ? texts.mediaBlocked : texts.mediaRemoved,
      );
    }
    return switch (attachment.kind) {
      MediaKind.voice => _VoiceNote(attachment: attachment, mine: mine),
      MediaKind.clip => _ClipTile(attachment: attachment),
      _ => _PhotoTile(attachment: attachment),
    };
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.hide_image_outlined, size: 16, color: Colors.white38),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 13.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    ),
  );
}

/// A picture or poster at the size a bubble has room for, kept to its shape.
class _Frame extends StatelessWidget {
  const _Frame({required this.aspect, required this.child});

  final double? aspect;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260, maxHeight: 240),
    child: AspectRatio(
      aspectRatio: (aspect ?? 4 / 3).clamp(0.5, 2.2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(color: const Color(0x14FFFFFF), child: child),
      ),
    ),
  );
}

Widget _picture(String? url, {BoxFit fit = BoxFit.cover}) => url == null
    ? const SizedBox.expand()
    : Image.network(
        url,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white24),
        ),
      );

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final local = attachment.local;
    return GestureDetector(
      onTap: local != null || attachment.url == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => PhotoScreen(url: attachment.url!),
              ),
            ),
      child: _Frame(
        aspect: attachment.aspect,
        child: local != null
            ? Image.memory(local, fit: BoxFit.cover, gaplessPlayback: true)
            : _picture(attachment.thumb ?? attachment.url),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final duration = attachment.duration;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ClipScreen(url: attachment.url!),
        ),
      ),
      child: _Frame(
        aspect: attachment.aspect ?? 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _picture(attachment.poster ?? attachment.thumb),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0x99000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            if (duration != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    clockOf(duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A voice note: play and pause, how far it is, and how long. The player is made on the first
/// tap, so a thread full of them loads nothing.
class _VoiceNote extends StatefulWidget {
  const _VoiceNote({required this.attachment, required this.mine});

  final Attachment attachment;
  final bool mine;

  @override
  State<_VoiceNote> createState() => _VoiceNoteState();
}

class _VoiceNoteState extends State<_VoiceNote> {
  VideoPlayerController? _player;
  bool _failed = false;
  bool _starting = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.attachment.url;
    if (url == null || _starting) return;
    var player = _player;
    if (player == null) {
      setState(() => _starting = true);
      player = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await player.initialize();
      } on Object {
        await player.dispose();
        if (mounted) {
          setState(() {
            _failed = true;
            _starting = false;
          });
        }
        return;
      }
      if (!mounted) {
        await player.dispose();
        return;
      }
      player.addListener(_changed);
      setState(() {
        _player = player;
        _starting = false;
      });
    }
    final value = player.value;
    if (value.isPlaying) {
      await player.pause();
    } else {
      if (value.duration > Duration.zero && value.position >= value.duration) {
        await player.seekTo(Duration.zero);
      }
      await player.play();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final value = _player?.value;
    final total = value != null && value.duration > Duration.zero
        ? value.duration
        : widget.attachment.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final playing = value?.isPlaying ?? false;
    final progress = total > Duration.zero
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            tooltip: texts.mediaVoice,
            visualDensity: VisualDensity.compact,
            onPressed: _failed ? null : _toggle,
            icon: _starting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: togetherAccent,
                    size: 28,
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: const Color(0x26FFFFFF),
                    color: togetherAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _failed
                      ? texts.mediaUnplayable
                      : clockOf(
                          playing || position > Duration.zero
                              ? position
                              : total,
                        ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo over the whole screen, to pinch and pan.
class PhotoScreen extends StatelessWidget {
  const PhotoScreen({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(child: _picture(url, fit: BoxFit.contain)),
          ),
        ),
        const _Close(),
      ],
    ),
  );
}

/// A clip playing over the whole screen: tap to pause, the bar to seek.
class ClipScreen extends StatefulWidget {
  const ClipScreen({super.key, required this.url});

  final String url;

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<ClipScreen> {
  late final VideoPlayerController _player = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _player.play();
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
    _player.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final value = _player.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _failed
                ? Text(
                    texts.mediaUnplayable,
                    style: const TextStyle(color: Colors.white60),
                  )
                : !value.isInitialized
                ? const CircularProgressIndicator(strokeWidth: 2)
                : GestureDetector(
                    onTap: () =>
                        value.isPlaying ? _player.pause() : _player.play(),
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(_player),
                          if (!value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white70,
                                size: 64,
                              ),
                            ),
                          VideoProgressIndicator(
                            _player,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: togetherAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const _Close(),
        ],
      ),
    );
  }
}

class _Close extends StatelessWidget {
  const _Close();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ),
    ),
  );
}
