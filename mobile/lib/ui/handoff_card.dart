import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../protocol/messages.dart';
import '../strings.dart';

/// The Mac asking to be signed in to AnyTogether as this phone's account: a card at the top of
/// the screen, over whatever the phone shows, until it is answered.
class HandoffCard extends StatelessWidget {
  const HandoffCard({
    super.key,
    required this.asked,
    required this.handle,
    required this.onAnswer,
  });

  final ValueListenable<TogetherHandoff?> asked;
  final String? handle;
  final Future<void> Function(TogetherHandoff ask, bool approve) onAnswer;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: asked,
    builder: (context, ask, _) {
      final texts = Texts.of(context);
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.2),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: ask == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(ask.id),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: const Color(0xF0101218),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x668AB4FF)),
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
                    const Icon(
                      Icons.laptop_mac_rounded,
                      color: Color(0xFF8AB4FF),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        texts.togetherMacAsks(ask.deviceName, handle ?? ''),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onAnswer(ask, false),
                      child: Text(
                        texts.notNow,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => onAnswer(ask, true),
                      child: Text(texts.allow),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
