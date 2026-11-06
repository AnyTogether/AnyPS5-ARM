import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media_strings.dart';
import '../strings.dart';
import '../together/e2ee.dart';
import '../together/messages.dart';
import '../together/sealed_media.dart';
import '../together/storage.dart';
import 'together_widgets.dart';

/// "1:05"
String clockOf(Duration duration) {
  final seconds = duration.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The media a message holds, as its bubble shows it: a photo, a clip's poster, a voice note
/// to play, or why it is not there. The links are signed and need no token. Sealed media is
/// downloaded and opened on the phone, and shown from memory.
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
    if (local == null && attachment.sealed) {
      return _SealedPicture(
        media: attachment,
        part: FilePart.file,
        onOpen: (bytes) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PhotoScreen(bytes: bytes),
          ),
        ),
      );
    }
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
          builder: (_) => attachment.sealed
              ? ClipScreen(sealed: attachment)
              : ClipScreen(url: attachment.url!),
        ),
      ),
      child: _Frame(
        aspect: attachment.aspect ?? 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (attachment.sealed)
              attachment.posterFile == null
                  ? const SizedBox.expand()
                  : _SealedBytes(media: attachment, part: FilePart.poster)
            else
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
  File? _opened;

  @override
  void dispose() {
    _player?.dispose();
    _forget(_opened);
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.attachment.url;
    if (url == null || _starting) return;
    var player = _player;
    if (player == null) {
      setState(() => _starting = true);
      try {
        if (widget.attachment.sealed) {
          final file = await SealedMedia.shared.temporaryFile(
            widget.attachment,
          );
          _opened = file;
          player = VideoPlayerController.file(file);
        } else {
          player = VideoPlayerController.networkUrl(Uri.parse(url));
        }
        await player.initialize();
      } on Object {
        await player?.dispose();
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

/// A photo over the whole screen, to pinch and pan: from its link, or a sealed one's opened
/// [bytes].
class PhotoScreen extends StatelessWidget {
  const PhotoScreen({super.key, this.url, this.bytes});

  final String? url;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: bytes != null
                  ? Image.memory(bytes!, fit: BoxFit.contain)
                  : _picture(url, fit: BoxFit.contain),
            ),
          ),
        ),
        const _Close(),
      ],
    ),
  );
}

/// A clip playing over the whole screen: tap to pause, the bar to seek. A [sealed] one is opened
/// into a temporary file first (the player plays only files and links), deleted after.
class ClipScreen extends StatefulWidget {
  const ClipScreen({super.key, this.url, this.sealed})
    : assert(url != null || sealed != null);

  final String? url;
  final Attachment? sealed;

  @override
  State<ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<ClipScreen> {
  VideoPlayerController? _player;
  File? _opened;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final sealed = widget.sealed;
      final VideoPlayerController player;
      if (sealed != null) {
        final file = await SealedMedia.shared.temporaryFile(sealed);
        if (!mounted) {
          _forget(file);
          return;
        }
        _opened = file;
        player = VideoPlayerController.file(file);
      } else {
        player = VideoPlayerController.networkUrl(Uri.parse(widget.url!));
      }
      setState(() => _player = player);
      player.addListener(_changed);
      await player.initialize();
      if (!mounted) return;
      setState(() {});
      await player.play();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.dispose();
    _forget(_opened);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final player = _player;
    final value = player?.value ?? const VideoPlayerValue.uninitialized();
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
                : player == null || !value.isInitialized
                ? const CircularProgressIndicator(strokeWidth: 2)
                : GestureDetector(
                    onTap: () =>
                        value.isPlaying ? player.pause() : player.play(),
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          VideoPlayer(player),
                          if (!value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white70,
                                size: 64,
                              ),
                            ),
                          VideoProgressIndicator(
                            player,
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

/// An opened clip or voice note's temporary file, gone once it is not played any more.
void _forget(File? file) {
  if (file == null) return;
  file.parent.delete(recursive: true).catchError((Object _) => file.parent);
}

/// A sealed picture (a photo, or a clip's poster) downloaded and opened, filling its place.
class _SealedBytes extends StatefulWidget {
  const _SealedBytes({required this.media, required this.part, this.onOpen});

  final Attachment media;
  final FilePart part;
  final ValueChanged<Uint8List>? onOpen;

  @override
  State<_SealedBytes> createState() => _SealedBytesState();
}

class _SealedBytesState extends State<_SealedBytes> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() =>
      SealedMedia.shared.open(widget.media, part: widget.part);

  @override
  void didUpdateWidget(_SealedBytes old) {
    super.didUpdateWidget(old);
    if (old.media.id != widget.media.id ||
        old.media.file?.key != widget.media.file?.key) {
      _bytes = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (snapshot.hasError) {
        return Center(
          child: IconButton(
            tooltip: MaterialLocalizations.of(context)
                .refreshIndicatorSemanticLabel,
            onPressed: () => setState(() => _bytes = _load()),
            icon: const Icon(
              Icons.broken_image_outlined,
              color: Colors.white24,
            ),
          ),
        );
      }
      if (bytes == null) {
        return const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final image = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
      final open = widget.onOpen;
      return open == null
          ? image
          : GestureDetector(onTap: () => open(bytes), child: image);
    },
  );
}

/// A sealed photo in its frame.
class _SealedPicture extends StatelessWidget {
  const _SealedPicture({
    required this.media,
    required this.part,
    required this.onOpen,
  });

  final Attachment media;
  final FilePart part;
  final ValueChanged<Uint8List> onOpen;

  @override
  Widget build(BuildContext context) => _Frame(
    aspect: media.aspect,
    child: _SealedBytes(media: media, part: part, onOpen: onOpen),
  );
}
