import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/people.dart';
import 'together_widgets.dart';

/// A trophy grade's colour, the same everywhere a trophy shows.
Color gradeColor(Grade grade) => switch (grade) {
  Grade.platinum => const Color(0xFFB8C7FF),
  Grade.gold => const Color(0xFFFFC94D),
  Grade.silver => const Color(0xFFC9D1DC),
  Grade.bronze => const Color(0xFFD08A5A),
};

/// Rarer is warmer: common grey to ultra rare violet.
Color rarityColor(Rarity? rarity) => switch (rarity) {
  Rarity.ultraRare => const Color(0xFFC79BFF),
  Rarity.veryRare => const Color(0xFFFF9BB0),
  Rarity.rare => const Color(0xFFFFC266),
  Rarity.uncommon => const Color(0xFF8AB4FF),
  _ => Colors.white54,
};

/// A game's icon from the catalogue, or a quiet tile without one.
class GameIcon extends StatelessWidget {
  const GameIcon({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    const empty = ColoredBox(
      color: Color(0x14FFFFFF),
      child: Center(
        child: Icon(
          Icons.sports_esports_rounded,
          color: Colors.white30,
          size: 18,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? empty
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => empty,
              ),
      ),
    );
  }
}

/// One item of the activity feed: who did what, when, the trophies it holds, and the
/// reactions; with [onReact] the reactions can be picked (and picked again to take back).
class ActivityTile extends StatelessWidget {
  const ActivityTile({
    super.key,
    required this.item,
    this.onReact,
    this.onPerson,
  });

  final Activity item;
  final ValueChanged<Reaction?>? onReact;
  final ValueChanged<Person>? onPerson;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final language = texts.language;
    final first = item.trophies.firstOrNull;
    final trophyName = first == null
        ? '…'
        : localTexts(first.texts, language)?.name ?? texts.hiddenTrophy;
    final bold = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );
    final names = {
      '{name}': item.actor.displayName,
      '{game}': item.game?.name(language) ?? '…',
      '{trophy}': trophyName,
      '{friend}': item.friend?.displayName ?? '…',
    };
    final line = texts.activityLine(item);
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in RegExp(
      r'\{(name|game|trophy|friend)\}',
    ).allMatches(line)) {
      if (match.start > at) {
        spans.add(TextSpan(text: line.substring(at, match.start)));
      }
      spans.add(TextSpan(text: names[match.group(0)], style: bold));
      at = match.end;
    }
    if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
    final tag = switch (item.highlight) {
      'platinum' => (texts.platinumTag, gradeColor(Grade.platinum)),
      'rare' => (texts.rare, rarityColor(Rarity.rare)),
      _ when item.kind == ActivityKind.milestone => (
        texts.milestoneTag,
        togetherAccent,
      ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onPerson == null ? null : () => onPerson!(item.actor),
            child: Avatar(person: item.actor, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: spans),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      texts.ago(item.createdAt),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    if (tag case (final label, final color)) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.trophies.length > 1 ||
                    (first != null && first.rarity != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final trophy in item.trophies.take(3))
                          _TrophyChip(trophy: trophy),
                        if (item.trophyCount > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              texts.andMore(item.trophyCount - 3),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                _ReactionBar(reactions: item.reactions, onReact: onReact),
              ],
            ),
          ),
          if (item.game != null) ...[
            const SizedBox(width: 10),
            GameIcon(url: item.game!.iconUrl, size: 36),
          ],
        ],
      ),
    );
  }
}

class _TrophyChip extends StatelessWidget {
  const _TrophyChip({required this.trophy});

  final ActivityTrophy trophy;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final name =
        localTexts(trophy.texts, texts.language)?.name ?? texts.hiddenTrophy;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 13,
            color: gradeColor(trophy.grade),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          if (trophy.rarity != null) ...[
            const SizedBox(width: 6),
            Text(
              texts.rarityPercent(trophy.rarity!),
              style: TextStyle(
                color: rarityColor(trophy.rarityLabel),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 🔥 👏 😮 ❤️ with their counts; the reader's own stands out. Without [onReact] only the ones
/// someone picked show, and nothing can be tapped.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.reactions, required this.onReact});

  final Reactions reactions;
  final ValueChanged<Reaction?>? onReact;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final shown = onReact == null
        ? Reaction.values.where((r) => (reactions.counts[r] ?? 0) > 0)
        : Reaction.values;
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        children: [
          for (final reaction in shown)
            _ReactionChip(
              reaction: reaction,
              count: reactions.counts[reaction] ?? 0,
              mine: reactions.mine == reaction,
              label: texts.reactionName(reaction),
              onTap: onReact == null
                  ? null
                  : () =>
                        onReact!(reactions.mine == reaction ? null : reaction),
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.reaction,
    required this.count,
    required this.mine,
    required this.label,
    required this.onTap,
  });

  final Reaction reaction;
  final int count;
  final bool mine;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    selected: mine,
    label: '$label: $count',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? const Color(0x2E8AB4FF) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: mine ? const Color(0x998AB4FF) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 13)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: mine ? togetherAccent : Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
