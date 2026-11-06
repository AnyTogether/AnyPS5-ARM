import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/voice.dart';
import 'together_widgets.dart';

/// The party's voice beside the connection status, on the launcher and on the pad. In the voice
/// here: a microphone that turns green while this phone is heard; a tap mutes or unmutes it and
/// a long press leaves the voice on this phone. While the party talks and the voice is elsewhere
/// (on the computer this phone plays on, say): a headset; a tap brings the voice to the phone,
/// and the computer goes quiet for this person.
class VoicePill extends StatelessWidget {
  const VoicePill({super.key, required this.voice});

  final Voice voice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([voice, voice.parties]),
    builder: (context, _) {
      final texts = Texts.of(context);
      if (!voice.active) {
        final party = voice.parties.party;
        if (party == null || (party.inCall.isEmpty && !voice.joining)) {
          return const SizedBox.shrink();
        }
        return _Pill(
          tooltip: texts.voiceHere,
          color: togetherAccent,
          onTap: voice.joining ? null : () => voice.join(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (voice.joining)
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: togetherAccent,
                  ),
                )
              else
                const Icon(
                  Icons.headset_mic_rounded,
                  size: 14,
                  color: togetherAccent,
                ),
              const SizedBox(width: 5),
              Text(
                texts.voiceHereShort,
                style: const TextStyle(
                  color: togetherAccent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
      final muted = voice.muted;
      final color = muted
          ? togetherError
          : voice.speaking
          ? togetherPlaying
          : Colors.white70;
      return _Pill(
        tooltip: muted ? texts.voiceUnmute : texts.voiceMute,
        color: color,
        onTap: () => voice.setMuted(!muted),
        onLongPress: () => voice.leave(),
        semanticsHint: texts.voiceLeaveHere,
        child: Icon(
          muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          size: 14,
          color: color,
        ),
      );
    },
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.tooltip,
    required this.color,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.semanticsHint,
  });

  final String tooltip;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticsHint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        onLongPressHint: semanticsHint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
}
