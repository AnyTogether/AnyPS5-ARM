import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/profiles.dart';
import 'activity_tile.dart';
import 'together_widgets.dart';

/// The colour a profile's highlights are drawn in: its accent, its theme's, or the app's.
Color lookAccent(ProfileLook look) => switch (look.accentColor) {
  final value? => Color(value),
  null => togetherAccent,
};

Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// A picture that fades in once it has loaded, and is nothing when it cannot load.
class FadeInPicture extends StatelessWidget {
  const FadeInPicture({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
    frameBuilder: (_, child, frame, synchronous) => synchronous
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: motion(context, 260),
            curve: Curves.easeOut,
            child: child,
          ),
  );
}

/// The header a profile wears: its cover or its theme's still behind the card, the theme's deep
/// to middle tint over it, and which theme it is. A profile with the default look is the card
/// alone, as before.
class LookHeader extends StatelessWidget {
  const LookHeader({super.key, required this.look, required this.child});

  final ProfileLook look;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final picture = look.picture;
    final theme = look.theme;
    if (picture == null && theme == null) return child;
    final accent = lookAccent(look);
    return Container(
      key: ValueKey(theme == null ? 'profile-look' : 'profile-look-theme'),
      decoration: BoxDecoration(
        color: theme == null ? togetherPanel : Color(theme.colors.deep),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (picture != null)
            Positioned.fill(child: FadeInPicture(url: picture)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: theme == null
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Color(0xC70B0D12)],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(theme.colors.deep).withValues(alpha: 0.9),
                          Color(theme.colors.middle).withValues(alpha: 0.55),
                        ],
                      ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.4, 1],
                  colors: [Color(0x00000000), Color(0x8C07080B)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                if (theme != null) ...[
                  const SizedBox(height: 12),
                  ThemeChip(theme: theme, accent: accent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Theme: Nebula" with the theme's four colours as overlapping swatches.
class ThemeChip extends StatelessWidget {
  const ThemeChip({super.key, required this.theme, required this.accent});

  final ProfileTheme theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = theme.colors;
    final swatches = [colors.deep, colors.middle, colors.bright, colors.accent];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 11, 5),
      decoration: BoxDecoration(
        color: const Color(0x52000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14.0 + 9 * (swatches.length - 1),
            height: 14,
            child: Stack(
              children: [
                for (var i = 0; i < swatches.length; i++)
                  Positioned(
                    left: 9.0 * i,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(swatches[i]),
                        border: Border.all(
                          color: const Color(0xFF0B0D12),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              Texts.of(context).themeWorn(theme.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a profile pinned to its top: up to six trophies and games in one row, each in its own
/// tile; a part the asker may not see is left out. Its owner gets the button to change it.
class ShowcaseStrip extends StatelessWidget {
  const ShowcaseStrip({
    super.key,
    required this.showcase,
    required this.accent,
    this.onEdit,
  });

  final Showcase showcase;
  final Color accent;
  final VoidCallback? onEdit;

  static const gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final tiles = <Widget>[
      for (final trophy in showcase.trophies ?? const <EarnedTrophy>[])
        TrophyPinTile(
          key: ValueKey('pin-${trophy.game.titleId}-${trophy.trophyId}'),
          trophy: trophy,
        ),
      for (final game in showcase.games ?? const <LibraryGame>[])
        GamePinTile(
          key: ValueKey('pin-${game.game.titleId}'),
          game: game,
          accent: accent,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          texts.showcase,
          trailing: onEdit == null
              ? null
              : TextButton.icon(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.push_pin_outlined, size: 15),
                  label: Text(
                    texts.showcaseEdit,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        if (tiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              texts.showcaseEmpty,
              style: const TextStyle(color: Colors.white38, fontSize: 13.5),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              const most = ShowcasePicks.max;
              final fits = (box.maxWidth - gap * (most - 1)) / most;
              final width = fits < 96 ? 104.0 : fits.clamp(96.0, 160.0);
              final height = 56 + MediaQuery.textScalerOf(context).scale(68);
              final row = Row(
                children: [
                  for (final (index, tile) in tiles.indexed) ...[
                    if (index > 0) const SizedBox(width: gap),
                    SizedBox(width: width, height: height, child: tile),
                  ],
                ],
              );
              return fits < 96
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: row,
                    )
                  : row;
            },
          ),
      ],
    );
  }
}

class _PinFrame extends StatelessWidget {
  const _PinFrame({required this.tone, required this.children});

  final Color tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: tone.withValues(alpha: 0.26)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tone.withValues(alpha: 0.16), const Color(0x08FFFFFF)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// A pinned trophy: its grade's colour, its name and game, and how rare it is.
class TrophyPinTile extends StatelessWidget {
  const TrophyPinTile({super.key, required this.trophy});

  final EarnedTrophy trophy;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final local = localTexts(trophy.texts, texts.language);
    final tone = gradeColor(trophy.grade);
    final rarity = trophy.rarity;
    return Semantics(
      label: [
        local?.name ?? texts.hiddenTrophy,
        texts.grade(trophy.grade),
        trophy.game.name(texts.language),
      ].join(', '),
      excludeSemantics: true,
      child: _PinFrame(
        tone: tone,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  trophy.hidden && local == null
                      ? Icons.lock_rounded
                      : Icons.emoji_events_rounded,
                  color: tone,
                  size: 17,
                ),
              ),
              const Spacer(),
              if (rarity != null)
                Flexible(
                  child: Text(
                    texts.rarityPercent(rarity),
                    maxLines: 1,
                    style: TextStyle(
                      color: rarityColor(trophy.rarityLabel),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            local?.name ?? texts.hiddenTrophy,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trophy.game.name(texts.language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// A pinned game: its icon, its name, play time and how far its trophies are.
class GamePinTile extends StatelessWidget {
  const GamePinTile({super.key, required this.game, required this.accent});

  final LibraryGame game;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final progress = game.progress;
    final complete = progress == 100;
    final bar = complete ? gradeColor(Grade.platinum) : accent;
    return Semantics(
      label: [
        game.game.name(texts.language),
        texts.playTime(game.secondsPlayed),
      ].join(', '),
      excludeSemantics: true,
      child: _PinFrame(
        tone: accent,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameIcon(url: game.game.iconUrl, size: 34),
              const SizedBox(width: 6),
              if (progress != null)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topRight,
                    child: Text(
                      '$progress%',
                      maxLines: 1,
                      style: TextStyle(
                        color: bar,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            game.game.name(texts.language),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            texts.playTime(game.secondsPlayed),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress / 100,
                minHeight: 3,
                backgroundColor: const Color(0x14FFFFFF),
                color: bar,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
