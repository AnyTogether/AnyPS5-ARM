import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/profiles.dart';
import 'activity_tile.dart';
import 'profile_look.dart';
import 'together_widgets.dart';

/// Picking what goes on one's own showcase, on its own screen; true once it was saved.
Future<bool> openShowcaseEdit(
  BuildContext context, {
  required Profiles profiles,
  required Showcase current,
  required List<EarnedTrophy> trophies,
  required List<LibraryGame> games,
  Color accent = togetherAccent,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ShowcaseEditScreen(
          profiles: profiles,
          current: current,
          trophies: trophies,
          games: games,
          accent: accent,
        ),
      ),
    ) ==
    true;

/// Earned trophies on the left, games on the right; six pins in all, saved together with Save.
/// What is pinned now stays in the lists even when it is no longer among them.
class ShowcaseEditScreen extends StatefulWidget {
  const ShowcaseEditScreen({
    super.key,
    required this.profiles,
    required this.current,
    required this.trophies,
    required this.games,
    this.accent = togetherAccent,
  });

  final Profiles profiles;
  final Showcase current;
  final List<EarnedTrophy> trophies;
  final List<LibraryGame> games;
  final Color accent;

  @override
  State<ShowcaseEditScreen> createState() => _ShowcaseEditScreenState();
}

class _ShowcaseEditScreenState extends State<ShowcaseEditScreen> {
  late final ShowcasePicks _picks = widget.current.picks;
  late final List<EarnedTrophy> _trophies = [
    for (final pinned in widget.current.trophies ?? const <EarnedTrophy>[])
      if (!widget.trophies.any((t) => _pinOf(t) == _pinOf(pinned))) pinned,
    ...widget.trophies,
  ];
  late final List<LibraryGame> _games = [
    for (final pinned in widget.current.games ?? const <LibraryGame>[])
      if (!widget.games.any((g) => g.game.titleId == pinned.game.titleId))
        pinned,
    ...widget.games,
  ];
  bool _saving = false;
  String? _error;

  static ShowcasePin _pinOf(EarnedTrophy trophy) =>
      ShowcasePin.trophy(trophy.game.titleId, trophy.trophyId);

  void _toggle(ShowcasePin pin) {
    if (!_picks.toggle(pin)) return;
    HapticFeedback.selectionClick();
    setState(() => _error = null);
  }

  Future<void> _save() async {
    final texts = Texts.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.profiles.saveShowcase(_picks);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = togetherFailure(texts, error);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final accent = widget.accent;
    return Scaffold(
      backgroundColor: togetherInk,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: texts.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white70,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      texts.showcaseEdit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Count(count: _picks.count, accent: accent),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _error ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: togetherError,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(texts.save),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
              child: Text(
                texts.showcaseHint,
                style: const TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _column(
                      texts.recentTrophies,
                      texts.noTrophiesYet,
                      const EdgeInsets.fromLTRB(22, 0, 10, 24),
                      [
                        for (final trophy in _trophies)
                          _pick(
                            _pinOf(trophy),
                            _TrophyLead(trophy: trophy),
                            localTexts(trophy.texts, texts.language)?.name ??
                                texts.hiddenTrophy,
                            trophy.game.name(texts.language),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _column(
                      texts.library,
                      texts.noGamesYet,
                      const EdgeInsets.fromLTRB(10, 0, 22, 24),
                      [
                        for (final game in _games)
                          _pick(
                            ShowcasePin.game(game.game.titleId),
                            GameIcon(url: game.game.iconUrl, size: 36),
                            game.game.name(texts.language),
                            texts.playTime(game.secondsPlayed),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
    String label,
    String empty,
    EdgeInsets padding,
    List<Widget> rows,
  ) => ListView(
    padding: padding,
    children: [
      SectionLabel(label),
      if (rows.isEmpty)
        Text(
          empty,
          style: const TextStyle(color: Colors.white38, fontSize: 13.5),
        ),
      ...rows,
    ],
  );

  Widget _pick(ShowcasePin pin, Widget lead, String title, String detail) {
    final picked = _picks.has(pin);
    final open = picked || !_picks.full;
    return _PickRow(
      key: ValueKey(
        pin.isGame
            ? 'pick-${pin.titleId}'
            : 'pick-${pin.titleId}-${pin.trophyId}',
      ),
      lead: lead,
      title: title,
      detail: detail,
      picked: picked,
      accent: widget.accent,
      onTap: open && !_saving ? () => _toggle(pin) : null,
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final full = count >= ShowcasePicks.max;
    return AnimatedContainer(
      duration: motion(context, 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: full ? 0.24 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ShowcasePicks.max; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < count ? accent : const Color(0x33FFFFFF),
              ),
            ),
          const SizedBox(width: 5),
          Text(
            Texts.of(context).showcasePinned(count),
            style: TextStyle(
              color: full ? Colors.white : accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrophyLead extends StatelessWidget {
  const _TrophyLead({required this.trophy});

  final EarnedTrophy trophy;

  @override
  Widget build(BuildContext context) {
    final tone = gradeColor(trophy.grade);
    final hidden =
        trophy.hidden &&
        localTexts(trophy.texts, Texts.of(context).language) == null;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        hidden ? Icons.lock_rounded : Icons.emoji_events_rounded,
        color: tone,
        size: 19,
      ),
    );
  }
}

/// A trophy or game that can be pinned: dimmed once six are and it is not one of them.
class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.lead,
    required this.title,
    required this.detail,
    required this.picked,
    required this.accent,
    required this.onTap,
  });

  final Widget lead;
  final String title;
  final String detail;
  final bool picked;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final duration = motion(context, 160);
    return Semantics(
      button: true,
      selected: picked,
      enabled: onTap != null,
      child: AnimatedOpacity(
        duration: duration,
        opacity: onTap == null && !picked ? 0.38 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: picked
                ? accent.withValues(alpha: 0.1)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
                child: Row(
                  children: [
                    lead,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOut,
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: picked ? accent : const Color(0x00000000),
                        border: Border.all(
                          color: picked ? accent : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: picked
                          ? const Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: togetherInk,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
