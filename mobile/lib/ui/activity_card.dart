import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../protocol/messages.dart';
import '../strings.dart';

/// What the launcher is doing with a game — waiting, unlocking or updating it, starting it —
/// at the top of the screen over whatever the phone shows: the step, a bar that fills and the
/// time it has taken so far. When the game is ready it says so for a moment, then goes.
class ActivityCard extends StatefulWidget {
  const ActivityCard({
    super.key,
    required this.activity,
    required this.game,
    this.now = DateTime.now,
  });

  final ValueListenable<({Activity activity, DateTime since})?> activity;

  /// The game's name and icon, by id.
  final ({String name, Uint8List? icon})? Function(String id) game;

  final DateTime Function() now;

  static const readyShown = Duration(milliseconds: 1600);

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  ({Activity activity, DateTime since})? _shown;
  bool _visible = false;
  bool _ready = false;
  Timer? _tick;
  Timer? _hide;

  static const _blue = Color(0xFF5AA9FF);
  static const _green = Color(0xFF4CD964);

  @override
  void initState() {
    super.initState();
    widget.activity.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.activity.removeListener(_changed);
    _tick?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  void _changed() {
    final now = widget.activity.value;
    if (now != null) {
      _hide?.cancel();
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
      setState(() {
        _shown = now;
        _visible = true;
        _ready = false;
      });
      return;
    }
    final last = _shown?.activity;
    if (last == null || !_visible) return;
    _tick?.cancel();
    _tick = null;
    // Done only when it got to the end; a cancelled unlock just goes.
    final finished =
        last.phase == ActivityPhase.starting || (last.fraction ?? 0) >= 0.99;
    setState(() => finished ? _ready = true : _visible = false);
    if (!finished) return;
    _hide = Timer(ActivityCard.readyShown, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  static String _clock(Duration elapsed) {
    final seconds = elapsed.inSeconds.clamp(0, 359999);
    final hours = seconds ~/ 3600;
    final minutes = (seconds ~/ 60) % 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest'
        : '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final texts = Texts.of(context);
    final activity = shown.activity;
    final game = widget.game(activity.id);
    final installing =
        activity.phase != ActivityPhase.queued &&
        activity.phase != ActivityPhase.starting;
    final color = _ready
        ? _green
        : switch (activity.phase) {
            ActivityPhase.starting => _green,
            ActivityPhase.queued => Colors.white70,
            _ => _blue,
          };
    final title = _ready
        ? texts.activityReady
        : switch (activity.phase) {
            ActivityPhase.queued => texts.activityQueued,
            ActivityPhase.starting => texts.activityStarting,
            _ =>
              activity.updating
                  ? texts.activityUpdating
                  : texts.activityUnlocking,
          };
    final step = switch (activity.phase) {
      ActivityPhase.queued => texts.activityStep('wait'),
      ActivityPhase.starting => texts.activityStep('launch'),
      final phase => texts.activityStep(phase.name),
    };
    final fraction = _ready ? 1.0 : activity.fraction;
    final detail = installing && fraction != null && !_ready
        ? '$step · ${texts.percent((fraction * 100).floor())}'
        : step;
    final elapsed = widget.now().difference(shown.since);
    return IgnorePointer(
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, -1.4),
        duration: const Duration(milliseconds: 380),
        curve: _visible ? Curves.easeOutBack : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 12),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: const Color(0xF0101218),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: game?.icon != null
                        ? Image.memory(
                            game!.icon!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : ColoredBox(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Icon(
                              Icons.sports_esports_rounded,
                              color: Colors.white54,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 220),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (_ready) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: _green,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Text(
                              title,
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _clock(elapsed),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          game?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 9),
                        _Bar(fraction: fraction, color: color),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin bar: filled to `fraction`, or sweeping while how long is not known.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double? fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: fraction == null
            ? LinearProgressIndicator(
                color: color,
                backgroundColor: track,
                minHeight: 4,
              )
            : ColoredBox(
                color: track,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: fraction!.clamp(0, 1)),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      heightFactor: 1,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
