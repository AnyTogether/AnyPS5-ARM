import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/voice.dart';
import 'together_widgets.dart';

/// The party's voice beside the connection status, on the launcher and on the pad: a
/// microphone that turns green while this phone is heard; a tap mutes or unmutes it.
class VoicePill extends StatelessWidget {
  const VoicePill({super.key, required this.voice});

  final Voice voice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: voice,
    builder: (context, _) {
      if (!voice.active) return const SizedBox.shrink();
      final texts = Texts.of(context);
      final muted = voice.muted;
      final color = muted
          ? togetherError
          : voice.speaking
          ? togetherPlaying
          : Colors.white70;
      return Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Tooltip(
          message: muted ? texts.voiceUnmute : texts.voiceMute,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => voice.setMuted(!muted),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x33000000),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.6)),
              ),
              child: Icon(
                muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 14,
                color: color,
              ),
            ),
          ),
        ),
      );
    },
  );
}
