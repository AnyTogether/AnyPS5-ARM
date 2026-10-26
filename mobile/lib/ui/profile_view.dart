import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/people.dart';
import '../together/profiles.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import 'activity_tile.dart';
import 'together_widgets.dart';

/// Someone's profile on its own screen, over AnyTogether's: a back button and the profile.
Future<void> openProfile(
  BuildContext context, {
  required TogetherHub hub,
  required String handle,
  String? Function(String titleId)? gameName,
  ValueChanged<String>? onMessage,
  ValueChanged<Person>? onCall,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 180),
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
                child: ProfileView(
                  hub: hub,
                  handle: handle,
                  gameName: gameName,
                  onMessage: onMessage == null
                      ? null
                      : (id) {
                          Navigator.of(context).maybePop();
                          onMessage(id);
                        },
                  onCall: onCall,
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
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  ),
);

enum _Part { games, trophies, activity, friends }

/// A profile: the card (picture, name, handle, country, what they are doing, bio) with what
/// can be done with them, the totals, and their games, trophies, activity and friends, each
/// behind a lock when they keep it to themselves.
class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.hub,
    required this.handle,
    this.gameName,
    this.onEdit,
    this.onMessage,
    this.onCall,
    this.profiles,
  });

  final TogetherHub hub;
  final String handle;
  final String? Function(String titleId)? gameName;

  /// Your own profile: the edit button, which reloads it after.
  final Future<void> Function()? onEdit;
  final ValueChanged<String>? onMessage;
  final ValueChanged<Person>? onCall;

  /// For tests; AnyTogether's own otherwise.
  final Profiles? profiles;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final Profiles _profiles =
      widget.profiles ?? Profiles(widget.hub.account);
  ProfilePage? _page;
  Object? _error;
  _Part _part = _Part.games;
  bool _busy = false;
  List<Activity> _activity = const [];
  String? _next;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProfileView old) {
    super.didUpdateWidget(old);
    if (old.handle != widget.handle) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await _profiles.load(widget.handle);
      if (!mounted) return;
      setState(() {
        _page = page;
        _activity = page.activity.items;
        _next = page.activity.next;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _older() async {
    final next = _next;
    if (next == null || _busy) return;
    setState(() => _busy = true);
    try {
      final page = await _profiles.activity(widget.handle, before: next);
      if (mounted) {
        setState(() {
          _activity = [..._activity, ...page.items];
          _next = page.next;
        });
      }
    } on Object {
      // The button stays for another try.
    }
    if (mounted) setState(() => _busy = false);
  }

  /// A reaction on one of their items, shown at once, put back when the server says no.
  Future<void> _react(Activity item, Reaction? reaction) async {
    void show(Reactions reactions) => setState(
      () => _activity = [
        for (final i in _activity)
          if (i.id == item.id) i.withReactions(reactions) else i,
      ],
    );
    show(item.reactions.picked(reaction));
    try {
      final counted = reaction == null
          ? await widget.hub.account.call(
              'DELETE',
              'activities/${item.id}/reaction',
            )
          : await widget.hub.account.call(
              'PUT',
              'activities/${item.id}/reaction',
              {'reaction': reaction.name},
            );
      if (mounted) show(Reactions.fromJson(counted));
    } on Object {
      if (mounted) show(item.reactions);
    }
  }

  Future<void> _friendAction(Future<void> Function() step) async {
    setState(() => _busy = true);
    try {
      await step();
      await _load();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(togetherFailure(Texts.of(context), error))),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final page = _page;
    if (page == null) {
      return Center(
        child: _error == null
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error is TogetherProblem
                        ? togetherFailure(texts, _error!)
                        : texts.profileFailed,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: Text(texts.retry)),
                ],
              ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
        children: [
          _card(texts, page.profile),
          if (page.totals case final totals?) ...[
            const SizedBox(height: 14),
            _Totals(totals: totals),
          ],
          const SizedBox(height: 16),
          _tabs(texts),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: KeyedSubtree(
              key: ValueKey(_part),
              child: _partBody(texts, page),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Strings texts, UserProfile profile) {
    final person = profile.person;
    final presence = profile.presence;
    final where = [
      '@${person.handle}',
      if (profile.country case final code?) '${flagOf(code)} $code',
    ].join('  ·  ');
    // On a small phone the buttons go under the bio, not beside a squeezed name.
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 460;
        final details = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              person: person,
              size: 68,
              presence:
                  presence == null || presence.state == PresenceState.offline
                  ? null
                  : presence.state,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    where,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  if (profile.trophyLevel case final level?) ...[
                    const SizedBox(height: 8),
                    LevelLine(level: level),
                  ],
                  if (presence != null &&
                      presence.state != PresenceState.offline) ...[
                    const SizedBox(height: 4),
                    Text(
                      presenceText(texts, presence, widget.gameName),
                      style: TextStyle(
                        color: presenceColor(presence.state),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    profile.bio?.isNotEmpty == true
                        ? profile.bio!
                        : texts.noBio,
                    style: TextStyle(
                      color: profile.bio?.isNotEmpty == true
                          ? Colors.white70
                          : Colors.white30,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (!narrow) ...[
              const SizedBox(width: 10),
              _actions(texts, profile),
            ],
          ],
        );
        if (!narrow) return details;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            details,
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 84),
              child: _actions(texts, profile),
            ),
          ],
        );
      },
    );
  }

  Widget _actions(Strings texts, UserProfile profile) {
    final person = profile.person;
    final friends = widget.hub.friends;
    return switch (profile.friendship) {
      Friendship.me =>
        widget.onEdit == null
            ? _Tag(texts.thisIsYou)
            : OutlinedButton.icon(
                onPressed: () async {
                  await widget.onEdit!();
                  await _load();
                },
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: Text(texts.editProfile),
              ),
      Friendship.friends => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onMessage case final message?)
            IconButton.filledTonal(
              tooltip: texts.messagesWrite,
              onPressed: () => message(person.id),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
            ),
          if (widget.onCall case final call?)
            IconButton.filledTonal(
              tooltip: texts.voice,
              onPressed: () => call(person),
              icon: const Icon(Icons.call_rounded, size: 19),
            ),
          const SizedBox(width: 4),
          _Tag(texts.areFriends),
        ],
      ),
      Friendship.pendingOut => _Tag(texts.requestPending),
      Friendship.pendingIn => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => _friendAction(
                    () => friends.answer(person.id, accept: false),
                  ),
            child: Text(
              texts.decline,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _friendAction(
                    () => friends.answer(person.id, accept: true),
                  ),
            child: Text(texts.accept),
          ),
        ],
      ),
      Friendship.none => FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _friendAction(() => friends.add(person.handle)),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
        label: Text(texts.addFriend),
      ),
    };
  }

  Widget _tabs(Strings texts) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final part in _Part.values)
        _Pill(
          label: switch (part) {
            _Part.games => texts.library,
            _Part.trophies => texts.recentTrophies,
            _Part.activity => texts.recentActivity,
            _Part.friends => texts.friendsList,
          },
          selected: _part == part,
          onTap: () => setState(() => _part = part),
        ),
    ],
  );

  Widget _partBody(Strings texts, ProfilePage page) {
    final name = page.profile.person.displayName;
    Widget empty(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 13.5),
      ),
    );
    switch (_part) {
      case _Part.games:
        final games = page.games;
        if (games == null) return _Private(texts.privateSection(name));
        if (games.isEmpty) return empty(texts.noGamesYet);
        return Column(
          children: [for (final game in games) _GameRow(game: game)],
        );
      case _Part.trophies:
        final trophies = page.trophies;
        if (trophies == null) return _Private(texts.privateSection(name));
        if (trophies.isEmpty) return empty(texts.noTrophiesYet);
        return Column(
          children: [
            for (final trophy in trophies.take(60)) _TrophyRow(trophy: trophy),
          ],
        );
      case _Part.activity:
        if (_activity.isEmpty) return empty(texts.noActivity);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in _activity)
              ActivityTile(
                key: ValueKey(item.id),
                item: item,
                onReact: (reaction) => _react(item, reaction),
              ),
            if (_next != null)
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _older,
                  child: Text(texts.loadMore),
                ),
              ),
          ],
        );
      case _Part.friends:
        final friends = page.friends;
        if (friends == null) return _Private(texts.privateSection(name));
        if (friends.isEmpty) return empty(texts.friendsNone);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final person in friends)
              _PersonChip(
                person: person,
                onTap: () => openProfile(
                  context,
                  hub: widget.hub,
                  handle: person.handle,
                  gameName: widget.gameName,
                  onMessage: widget.onMessage,
                  onCall: widget.onCall,
                ),
              ),
          ],
        );
    }
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final ProfileTotals totals;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final stats = [
      (texts.statGames, texts.number(totals.games)),
      (texts.statPlayed, texts.totalTime(totals.seconds)),
      (
        texts.statTrophies,
        totals.countsHidden ? '–' : texts.number(totals.trophies),
      ),
      (
        texts.statPoints,
        totals.countsHidden ? '–' : texts.number(totals.points),
      ),
      if (totals.platinums case final platinums? when platinums > 0)
        (texts.statPlatinums, texts.number(platinums)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final (label, value) in stats)
            Expanded(
              child: Column(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // One line, shrunk to fit: a long label never breaks inside a word.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      texts.upper(label),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game});

  final LibraryGame game;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final last = game.lastPlayedAt;
    final progress = game.progress;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GameIcon(url: game.game.iconUrl, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.game.name(texts.language),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  [
                    texts.playTime(game.secondsPlayed),
                    if (last != null) texts.lastPlayed(last),
                  ].join('  ·  '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (game.trophiesEarned != null && (game.trophiesTotal ?? 0) > 0) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  texts.trophiesOf(game.trophiesEarned!, game.trophiesTotal!),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (progress ?? 0) / 100,
                      minHeight: 4,
                      backgroundColor: const Color(0x14FFFFFF),
                      color: progress == 100
                          ? gradeColor(Grade.platinum)
                          : togetherAccent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrophyRow extends StatelessWidget {
  const _TrophyRow({required this.trophy});

  final EarnedTrophy trophy;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final local = localTexts(trophy.texts, texts.language);
    final rarity = trophy.rarity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: gradeColor(trophy.grade).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              trophy.hidden && local == null
                  ? Icons.lock_rounded
                  : Icons.emoji_events_rounded,
              color: gradeColor(trophy.grade),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  local?.name ?? texts.hiddenTrophy,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  [
                    trophy.game.name(texts.language),
                    texts.daysAgo(trophy.earnedAt),
                  ].join('  ·  '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (rarity != null) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  texts.ofPlayers(rarity),
                  style: TextStyle(
                    color: rarityColor(trophy.rarityLabel),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trophy.rarityLabel case final label?)
                  Text(
                    texts.rarity(label),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Private extends StatelessWidget {
  const _Private(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white54, fontSize: 13.5),
          ),
        ),
      ],
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0x148AB4FF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: togetherAccent,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0x268AB4FF) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x0AFFFFFF),
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(person: person, size: 26),
            const SizedBox(width: 8),
            Text(
              person.displayName,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The colours a tier is drawn in: the ring's light and dark ends.
const levelTierColors = <LevelTier, (Color, Color)>{
  LevelTier.bronze: (Color(0xFFE2A271), Color(0xFF8A4E2B)),
  LevelTier.silver: (Color(0xFFE8EDF5), Color(0xFF8C96A8)),
  LevelTier.gold: (Color(0xFFFFDC7A), Color(0xFFB7862C)),
  LevelTier.platinum: (Color(0xFFDDE9FF), Color(0xFF7FA2D9)),
};

/// The trophy level as a badge in its tier's ring (one more notch for each hundred levels), with
/// the way to the next one.
class LevelLine extends StatelessWidget {
  const LevelLine({super.key, required this.level});

  final TrophyLevel level;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final (light, dark) = levelTierColors[level.tier]!;
    final top = level.nextLevelPoints == null;
    return Row(
      children: [
        Container(
          key: ValueKey('level-badge-${level.tier.name}'),
          width: 30,
          height: 30,
          padding: EdgeInsets.all(level.frame >= 5 ? 2.5 : 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, dark],
            ),
            boxShadow: [
              BoxShadow(color: dark.withValues(alpha: 0.45), blurRadius: 8),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0B0D12),
            ),
            child: Text(
              '${level.level}',
              style: TextStyle(
                color: light,
                fontSize: level.level >= 100 ? 10.5 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texts.trophyLevel(level.level),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: level.progress / 100,
                  minHeight: 3,
                  backgroundColor: const Color(0x1FFFFFFF),
                  valueColor: AlwaysStoppedAnimation(light),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                top
                    ? texts.levelTop
                    : texts.levelProgress(level.progress, level.level + 1),
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
