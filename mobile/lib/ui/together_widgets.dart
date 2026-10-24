import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/people.dart';
import '../together/together_account.dart';

/// AnyTogether's colours on the phone, the same as its sheets.
const togetherAccent = Color(0xFF8AB4FF);
const togetherPanel = Color(0xFF101218);
const togetherInk = Color(0xFF07080B);
const togetherPlaying = Color(0xFF4CD964);
const togetherAway = Color(0xFFFFC266);
const togetherError = Color(0xFFFF8A80);

/// A person's picture, or their initials on a tinted disc; [ring] draws a coloured ring around
/// it (speaking), [presence] a dot at the bottom right.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.person,
    this.size = 40,
    this.ring,
    this.presence,
  });

  final Person person;
  final double size;
  final Color? ring;
  final PresenceState? presence;

  @override
  Widget build(BuildContext context) {
    final picture = person.avatar;
    final initials = Center(
      child: Text(
        person.initials,
        style: TextStyle(
          color: togetherAccent,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final dot = presence == null ? null : presenceColor(presence!);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            padding: EdgeInsets.all(ring == null ? 0 : 2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ring ?? Colors.transparent,
                width: ring == null ? 0 : 2.5,
              ),
            ),
            child: ClipOval(
              child: ColoredBox(
                color: const Color(0x228AB4FF),
                child: picture == null
                    ? initials
                    : Image.network(
                        picture,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        errorBuilder: (_, _, _) => initials,
                      ),
              ),
            ),
          ),
          if (dot != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: togetherPanel, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color presenceColor(PresenceState state) => switch (state) {
  PresenceState.inGame => togetherPlaying,
  PresenceState.online => togetherAccent,
  PresenceState.away => togetherAway,
  PresenceState.offline => const Color(0x40FFFFFF),
};

/// What a friend is doing, in words: the game by its name when the Mac knows it.
String presenceText(
  Strings texts,
  Presence presence,
  String? Function(String titleId)? gameName,
) => switch (presence.state) {
  PresenceState.inGame => texts.presencePlaying(
    presence.titleId == null
        ? '…'
        : gameName?.call(presence.titleId!) ?? presence.titleId!,
  ),
  PresenceState.online => texts.presenceOnline,
  PresenceState.away => texts.presenceAway,
  PresenceState.offline => texts.presenceOffline,
};

/// A small caps label over a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// A count on an icon or a tab: hidden at zero, "9+" past nine.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    backgroundColor: togetherAccent,
    textColor: togetherInk,
    label: Text(count > 9 ? '9+' : '$count'),
    child: child,
  );
}

/// The words for what went wrong with a call to AnyTogether.
String togetherFailure(Strings texts, Object error) => switch (error) {
  TogetherProblem(code: 'not_found') => texts.togetherNotFound,
  TogetherProblem(:final title) when title.isNotEmpty => title,
  _ => texts.togetherUnreachable,
};
