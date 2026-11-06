import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/challenges.dart';
import '../together/together_hub.dart';
import 'activity_tile.dart';
import 'together_widgets.dart';

/// How long the challenges' own motion takes: none when the phone asks for less motion.
Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

IconData _metricIcon(ChallengeMetric metric) => switch (metric) {
  ChallengeMetric.points => Icons.emoji_events_rounded,
  ChallengeMetric.trophies => Icons.military_tech_rounded,
  ChallengeMetric.time => Icons.schedule_rounded,
};

/// The challenges over a leaderboard: a row of cards side by side, each with what counts, the
/// time left, who leads and the reader's place, and a hairline of how much of the window has
/// gone. Nothing at all when there are none.
class ChallengeStrip extends StatelessWidget {
  const ChallengeStrip({
    super.key,
    required this.challenges,
    required this.onOpen,
    this.now,
  });

  final List<ChallengeView> challenges;
  final ValueChanged<ChallengeView> onOpen;

  /// For tests and previews; the clock otherwise.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // One fills the row (up to a card's width); several peek past the edge, never so
        // narrow that a card's lines no longer fit.
        final width = challenges.length == 1
            ? box.maxWidth.clamp(0, 380).toDouble()
            : (box.maxWidth * 0.82).clamp(210, 268).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_score_rounded,
                    size: 14,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      texts.upper(texts.challenges),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Cards of one height side by side, sideways when there are more than fit.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, challenge) in challenges.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      SizedBox(
                        width: width,
                        child: _ChallengeCard(
                          challenge: challenge,
                          now: now,
                          onTap: () => onOpen(challenge),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.onTap,
    this.now,
  });

  final ChallengeView challenge;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final at = now ?? DateTime.now();
    final over = !challenge.open;
    final leader = challenge.leader;
    return Semantics(
      button: true,
      child: Material(
        color: const Color(0x0DFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: challenge.joined && !over
                ? const Color(0x4D8AB4FF)
                : const Color(0x14FFFFFF),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GameIcon(url: challenge.game.iconUrl, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  challenge.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                  ),
                                ),
                                Text(
                                  '${challenge.game.name(texts.language)} · '
                                  '${texts.challengeMetric(challenge.metric)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _WhenChip(challenge: challenge, now: at),
                          Text(
                            texts.challengeEntrants(challenge.entrants),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (leader != null) ...[
                        const SizedBox(height: 9),
                        _LeaderLine(
                          label: challenge.state == ChallengeState.ended
                              ? texts.challengeWinner
                              : texts.challengeLeading,
                          standing: leader,
                          metric: challenge.metric,
                        ),
                      ],
                      if (challenge.myRank case final rank?) ...[
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${texts.yourPlace}  '),
                              TextSpan(
                                text:
                                    '${texts.rankShort(rank)} · '
                                    '${texts.challengeValue(challenge.metric, challenge.myValue)}',
                                style: const TextStyle(
                                  color: togetherAccent,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // How much of the window has gone, along the card's foot.
              _WindowLine(value: challenge.progress(at), over: over),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Ends in 2 days" on a small pill: lit while it runs, amber before it starts, grey after.
class _WhenChip extends StatelessWidget {
  const _WhenChip({required this.challenge, required this.now});

  final ChallengeView challenge;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final color = switch (challenge.state) {
      ChallengeState.active => togetherAccent,
      ChallengeState.upcoming => togetherAway,
      _ => Colors.white54,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            challenge.state == ChallengeState.upcoming
                ? Icons.hourglass_top_rounded
                : Icons.timer_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texts.challengeWhen(challenge, now: now),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowLine extends StatelessWidget {
  const _WindowLine({required this.value, required this.over});

  final double value;
  final bool over;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 3,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0x0FFFFFFF))),
        FractionallySizedBox(
          widthFactor: value,
          heightFactor: 1,
          child: ColoredBox(
            color: over ? const Color(0x33FFFFFF) : const Color(0x998AB4FF),
          ),
        ),
      ],
    ),
  );
}

/// "LEADING  (Ece)  Ece  1,230 pts" on one line.
class _LeaderLine extends StatelessWidget {
  const _LeaderLine({
    required this.label,
    required this.standing,
    required this.metric,
  });

  final String label;
  final ChallengeStanding standing;
  final ChallengeMetric metric;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final person = standing.person;
    return Row(
      children: [
        if (person != null)
          Avatar(person: person, size: 18)
        else
          const _HiddenFace(size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${texts.upper(label)}  ',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
                TextSpan(text: person?.displayName ?? texts.hiddenPlayer),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: person == null ? Colors.white54 : Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 6),
        FittedValue(
          maxWidth: 92,
          child: Text(
            texts.challengeValue(metric, standing.value),
            style: const TextStyle(
              color: togetherGold,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// In place of a picture, someone the reader may not see.
class _HiddenFace extends StatelessWidget {
  const _HiddenFace({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Color(0x14FFFFFF),
      shape: BoxShape.circle,
    ),
    child: Icon(
      Icons.visibility_off_rounded,
      size: size * 0.5,
      color: Colors.white38,
    ),
  );
}

/// One challenge over the screen, the way a profile opens: a back button beside its panel.
Future<void> openChallenge(
  BuildContext context, {
  required TogetherHub hub,
  required String id,
  ChallengeView? shown,
  ValueChanged<String>? onProfile,
  Challenges? challenges,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: _motion(context, 240),
    reverseTransitionDuration: _motion(context, 180),
    pageBuilder: (context, _, _) => Scaffold(
      backgroundColor: togetherInk,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: IconButton(
                tooltip: Texts.of(context).back,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                decoration: BoxDecoration(
                  color: togetherPanel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ChallengePane(
                  hub: hub,
                  id: id,
                  shown: shown,
                  challenges: challenges,
                  onProfile: onProfile,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    transitionsBuilder: (_, animation, _, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  ),
);

/// A challenge: its game, what counts, who made it and for whom, the window with how far it has
/// gone, Join or Leave, and the standings with the reader's row lit; the winner once final.
class ChallengePane extends StatefulWidget {
  const ChallengePane({
    super.key,
    required this.hub,
    required this.id,
    this.shown,
    this.challenges,
    this.onProfile,
    this.now,
  });

  final TogetherHub hub;
  final String id;

  /// What the list already knows, shown while the standings load.
  final ChallengeView? shown;

  /// For tests; AnyTogether's own otherwise.
  final Challenges? challenges;
  final ValueChanged<String>? onProfile;

  /// For previews; the clock otherwise.
  final DateTime? now;

  @override
  State<ChallengePane> createState() => _ChallengePaneState();
}

class _ChallengePaneState extends State<ChallengePane> {
  late final Challenges _challenges =
      widget.challenges ?? Challenges(widget.hub.account);
  late ChallengeView? _view = widget.shown;
  ChallengeDetail? _detail;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await _challenges.detail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _view = detail.view;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _act({required bool join}) async {
    final texts = Texts.of(context);
    final mine = _view?.mine ?? false;
    setState(() => _busy = true);
    try {
      final view = join
          ? await _challenges.join(widget.id)
          : await _challenges.leave(widget.id);
      if (mounted) setState(() => _view = view);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              texts.challengeProblem(error, mine: mine) ??
                  togetherFailure(texts, error),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _website() async {
    final base = widget.hub.account.base.toString().replaceAll(
      RegExp(r'/$'),
      '',
    );
    await launchUrl(
      Uri.parse('$base/challenges?new=1'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final view = _view;
    final Widget body;
    if (view == null) {
      body = ListView(
        key: const ValueKey('loading'),
        padding: const EdgeInsets.fromLTRB(22, 14, 18, 18),
        children: [
          if (_error == null)
            const LoadingOrFailed(error: null, retry: _nothing)
          else
            _Failed(onRetry: _load),
        ],
      );
    } else {
      body = LayoutBuilder(
        key: const ValueKey('shown'),
        builder: (context, box) {
          final about = _about(texts, view);
          final standings = _standings(texts, view);
          if (box.maxWidth < 620) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 18, 18),
              children: [...about, const SizedBox(height: 8), ...standings],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: box.maxWidth < 760 ? 280 : 320,
                // Built whole: a few lines, and the note under Join is always there.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: about,
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 18, 18),
                  children: standings,
                ),
              ),
            ],
          );
        },
      );
    }
    return AnimatedSwitcher(duration: _motion(context, 200), child: body);
  }

  static void _nothing() {}

  List<Widget> _about(Strings texts, ChallengeView view) {
    final now = widget.now ?? DateTime.now();
    final creator = view.creator;
    final audience = texts.challengeFor(view);
    return [
      Row(
        children: [
          GameIcon(url: view.game.iconUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  view.game.name(texts.language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
      if (view.description case final description?) ...[
        const SizedBox(height: 10),
        Text(
          description,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Tag(
            icon: _metricIcon(view.metric),
            text: texts.challengeMetric(view.metric),
          ),
          if (audience != null)
            _Tag(
              icon: switch (view.audience) {
                ChallengeAudience.friends => Icons.people_alt_rounded,
                ChallengeAudience.community => Icons.forum_rounded,
                _ => Icons.public_rounded,
              },
              text: audience,
            ),
          _Tag(
            icon: Icons.flag_rounded,
            text: texts.challengeEntrants(view.entrants),
          ),
        ],
      ),
      if (creator != null) ...[
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onProfile == null
              ? null
              : () => widget.onProfile!(creator.handle),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Avatar(person: creator, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    texts.challengeMadeBy(creator.displayName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
      _Window(view: view, now: now),
      if (view.open) ...[
        const SizedBox(height: 14),
        if (!view.joined)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: togetherAccent,
              foregroundColor: togetherInk,
            ),
            onPressed: _busy ? null : () => _act(join: true),
            icon: const Icon(Icons.flag_rounded, size: 18),
            label: Text(texts.joinChallenge),
          )
        else if (!view.mine)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0x33FFFFFF)),
            ),
            onPressed: _busy ? null : () => _act(join: false),
            child: Text(texts.leaveChallenge),
          ),
        if (!view.joined || !view.mine) const SizedBox(height: 8),
        Text(
          texts.challengeJoinNote,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: togetherAccent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _website,
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(texts.makeChallenge),
        ),
      ),
    ];
  }

  List<Widget> _standings(Strings texts, ChallengeView view) {
    final detail = _detail;
    final ended = view.state == ChallengeState.ended;
    final leader = view.leader;
    return [
      if (ended && view.isFinal && leader != null) ...[
        SectionLabel(texts.challengeWinner),
        _Winner(standing: leader, metric: view.metric),
      ],
      SectionLabel(
        ended && view.isFinal
            ? texts.challengeFinalStandings
            : texts.challengeStandings,
      ),
      if (ended && !view.isFinal)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            texts.challengeNotFinal,
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
      if (detail == null)
        _error == null
            ? const LoadingOrFailed(error: null, retry: _nothing)
            : _Failed(onRetry: _load)
      else if (detail.standings.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            view.state == ChallengeState.upcoming
                ? texts.challengeNotStarted
                : texts.challengeNoScores,
            style: const TextStyle(color: Colors.white54, fontSize: 13.5),
          ),
        )
      else ...[
        for (final row in detail.standings) _row(texts, view, row),
        if (detail.around.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Center(
              child: Icon(
                Icons.more_vert_rounded,
                color: Colors.white24,
                size: 18,
              ),
            ),
          ),
          for (final row in detail.around) _row(texts, view, row),
        ],
      ],
    ];
  }

  Widget _row(Strings texts, ChallengeView view, ChallengeStanding row) {
    final person = row.person;
    final medal = row.value > 0 ? medalColor(row.rank) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: row.me ? const Color(0x1A8AB4FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: person == null || widget.onProfile == null
              ? null
              : () => widget.onProfile!(person.handle),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${row.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: medal ?? Colors.white54,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (person != null)
                  Avatar(person: person, size: 32)
                else
                  const _HiddenFace(size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    person?.displayName ?? texts.hiddenPlayer,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: person == null ? Colors.white54 : Colors.white,
                      fontSize: 14.5,
                      fontStyle: person == null ? FontStyle.italic : null,
                      fontWeight: row.me ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                FittedValue(
                  child: Text(
                    texts.challengeValue(view.metric, row.value),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
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

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            texts.challengeFailed,
            style: const TextStyle(color: Colors.white54, fontSize: 13.5),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(texts.retry)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
    decoration: BoxDecoration(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white54),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// The window from start to end as a track: how far it has gone, a finish flag at its end, the
/// two times under it and the time left over it.
class _Window extends StatelessWidget {
  const _Window({required this.view, required this.now});

  final ChallengeView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final progress = view.progress(now);
    final running = view.state == ChallengeState.active;
    final fill = switch (view.state) {
      ChallengeState.active => togetherAccent,
      ChallengeState.upcoming => togetherAway,
      _ => Colors.white38,
    };
    const small = TextStyle(
      color: Colors.white38,
      fontSize: 11,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          texts.challengeWhen(view, now: now),
          style: TextStyle(
            color: running ? Colors.white : Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: _motion(context, 520),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: const Color(0x14FFFFFF),
                    color: fill,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.sports_score_rounded,
              size: 16,
              color: progress >= 1 ? fill : Colors.white38,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(child: Text(texts.moment(view.startsAt), style: small)),
            const SizedBox(width: 8),
            Text(texts.moment(view.endsAt), style: small),
            const SizedBox(width: 22),
          ],
        ),
      ],
    );
  }
}

/// The winner, set apart in gold.
class _Winner extends StatelessWidget {
  const _Winner({required this.standing, required this.metric});

  final ChallengeStanding standing;
  final ChallengeMetric metric;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final person = standing.person;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            togetherGold.withValues(alpha: 0.16),
            togetherGold.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: togetherGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: togetherGold, size: 22),
          const SizedBox(width: 10),
          if (person != null)
            Avatar(person: person, size: 34)
          else
            const _HiddenFace(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              person?.displayName ?? texts.hiddenPlayer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FittedValue(
            child: Text(
              texts.challengeValue(metric, standing.value),
              style: const TextStyle(
                color: togetherGold,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
