import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/push.dart';
import 'together_widgets.dart';

/// Offers push once the person reached out to someone: a card at the top of the screen, over
/// whatever the phone shows, the way the Mac's sign-in question comes. Turn on asks the phone.
class PushOfferCard extends StatelessWidget {
  const PushOfferCard({super.key, required this.push});

  final PhonePush push;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: push,
    builder: (context, _) {
      final texts = Texts.of(context);
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      return AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 0 : 280),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.2),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: !push.offering
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('push-offer'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                constraints: const BoxConstraints(maxWidth: 600),
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
                    const _LockScreenBell(),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            texts.pushOffer,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            texts.pushOfferDetail,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: push.notNow,
                      child: Text(
                        texts.notNow,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => push.turnOn().catchError((_) => false),
                      child: Text(texts.turnOn),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

/// A phone's lock screen with a notification on it: the thing being offered, drawn small.
class _LockScreenBell extends StatelessWidget {
  const _LockScreenBell();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 44,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: Colors.white30, width: 1.4),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1B2440), Color(0xFF0B0E16)],
      ),
    ),
    child: Column(
      children: [
        const SizedBox(height: 6),
        // The time on the lock screen.
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 6),
        // The notification that arrived.
        Container(
          width: 22,
          height: 9,
          decoration: BoxDecoration(
            color: togetherAccent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 2.5),
        Container(
          width: 22,
          height: 6,
          decoration: BoxDecoration(
            color: togetherAccent.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ),
  );
}
