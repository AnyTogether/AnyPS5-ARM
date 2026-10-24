import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../feedback/haptics.dart';
import '../protocol/packets.dart';
import '../strings.dart';
import '../together/share_play.dart';
import '../together/together_hub.dart';
import 'pad_screen.dart';
import 'setup_screen.dart' show StatusDot;
import 'together_widgets.dart';

/// Watches a friend's share play: the screen opens at once and the picture comes when the host
/// has called this phone.
Future<void> openShareWatch(
  BuildContext context, {
  required TogetherHub hub,
  required String sharePlayId,
  HapticsOutput? haptics,
}) {
  hub.sharePlays.watch(sharePlayId).catchError((_) {});
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => ShareWatchScreen(
        plays: hub.sharePlays,
        haptics: haptics ?? PlatformHaptics(),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// A friend's game on the phone, laid out as Remote Play: the picture fills the screen, and
/// while the host lets this phone play, the pad lies over it and drives that player.
class ShareWatchScreen extends StatefulWidget {
  const ShareWatchScreen({
    super.key,
    required this.plays,
    required this.haptics,
  });

  final SharePlays plays;
  final HapticsOutput haptics;

  @override
  State<ShareWatchScreen> createState() => _ShareWatchScreenState();
}

class _ShareWatchScreenState extends State<ShareWatchScreen> {
  late final HapticsDriver _haptics = HapticsDriver(widget.haptics);
  final _clock = Stopwatch()..start();
  int? _slot;
  String? _notice;
  Timer? _noticeTimer;

  SharePlays get plays => widget.plays;

  @override
  void initState() {
    super.initState();
    _slot = plays.slot;
    plays.addListener(_changed);
    plays.onOutput = (output, state) => _haptics.update(
      output,
      l2Held: state.l2 > 0 || state.buttons & PadButton.l2 != 0,
      r2Held: state.r2 > 0 || state.buttons & PadButton.r2 != 0,
      now: _clock.elapsed,
    );
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    plays.removeListener(_changed);
    plays.onOutput = null;
    _haptics.stop();
    _noticeTimer?.cancel();
    WakelockPlus.disable().catchError((_) {});
    if (plays.status != WatchStatus.ended) plays.leave().catchError((_) {});
    super.dispose();
  }

  /// A pad given or taken back is said for a moment.
  void _changed() {
    final slot = plays.slot;
    if (slot == _slot) return;
    final texts = Texts.of(context);
    final had = _slot;
    _slot = slot;
    if (slot == null) _haptics.stop();
    _say(
      slot != null
          ? texts.sharePlayer(slot)
          : had != null && plays.status != WatchStatus.ended
          ? texts.shareTaken
          : null,
    );
  }

  void _say(String? text) {
    if (text == null) return;
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _askToLeave() async {
    final texts = Texts.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: togetherPanel,
        content: Text(
          texts.shareLeave,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(texts.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(texts.shareLeave),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: plays,
    builder: (context, _) {
      final texts = Texts.of(context);
      final view = plays.watching;
      final slot = plays.slot;
      final video = _Picture(plays: plays, texts: texts);
      final Widget body = slot != null && plays.status != WatchStatus.ended
          ? PadScreen(
              onState: plays.update,
              onHome: _askToLeave,
              status: _Chip(plays: plays, texts: texts),
              glow: lightColor(plays.output),
              video: video,
            )
          : Stack(
              children: [
                Positioned.fill(child: video),
                if (view != null && plays.status != WatchStatus.ended)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: SafeArea(
                      child: Center(
                        child: _Chip(plays: plays, texts: texts),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: SafeArea(
                    child: IconButton(
                      tooltip: texts.shareLeave,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            );
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (_notice case final notice?)
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Center(child: _Pill(text: notice)),
              ),
          ],
        ),
      );
    },
  );
}

/// The picture, or what is happening while there is none: joining, connecting, why it ended.
class _Picture extends StatelessWidget {
  const _Picture({required this.plays, required this.texts});

  final SharePlays plays;
  final Strings texts;

  @override
  Widget build(BuildContext context) {
    final picture = plays.video();
    final host = plays.watching?.host?.displayName ?? '';
    final String? words = switch (plays.status) {
      WatchStatus.joining || WatchStatus.connecting => texts.shareConnecting(
        host.isEmpty ? texts.shareTitle : host,
      ),
      WatchStatus.ended => switch (plays.ended) {
        WatchEnd.removed => texts.shareRemoved(host),
        WatchEnd.full => texts.shareFull,
        WatchEnd.failed => texts.shareFailed,
        _ => texts.shareEnded(host.isEmpty ? texts.shareTitle : host),
      },
      WatchStatus.watching => null,
    };
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          if (picture != null && plays.status != WatchStatus.ended)
            Positioned.fill(child: picture),
          if (words != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (plays.status != WatchStatus.ended)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: togetherAccent,
                        ),
                      ),
                    ),
                  Text(
                    words,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0x99FFFFFF),
                      fontSize: 14,
                    ),
                  ),
                  if (plays.status == WatchStatus.ended)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(texts.back),
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

/// Whose game, as which player (or watching), and how the picture comes.
class _Chip extends StatelessWidget {
  const _Chip({required this.plays, required this.texts});

  final SharePlays plays;
  final Strings texts;

  @override
  Widget build(BuildContext context) {
    final view = plays.watching;
    final slot = plays.slot;
    final quality = plays.quality;
    final dot = switch (quality.bars) {
      3 => togetherPlaying,
      2 => togetherAway,
      _ => togetherError,
    };
    final parts = [
      view?.host?.displayName ?? '',
      slot != null ? texts.sharePlayer(slot) : texts.shareWatching,
      if (quality.roundTripMs != null) '${quality.roundTripMs!.round()} ms',
      if (quality.framesPerSecond != null)
        '${quality.framesPerSecond!.round()} fps',
      if (quality.height != null) '${quality.height}p',
    ].where((part) => part.isNotEmpty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(
            color: plays.status == WatchStatus.watching
                ? dot
                : const Color(0x66FFFFFF),
          ),
          const SizedBox(width: 8),
          Text(
            parts.join(' · '),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xE6101218),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x33FFFFFF)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
