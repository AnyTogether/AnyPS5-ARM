import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../safety_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/discover.dart';
import '../together/people.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import 'discover_people_view.dart';
import 'lfg_form.dart';
import 'live_now_view.dart';
import 'share_watch_screen.dart';
import 'together_widgets.dart';
import 'ask_first.dart';

/// Find players: the looking-for-group board, the reader's own posts, Live now (public share
/// plays and parties) and people to meet, one at a time under a row of tabs. What is on screen
/// is what the gateway tells about.
class FindPlayersPane extends StatefulWidget {
  const FindPlayersPane({
    super.key,
    required this.hub,
    this.view = DiscoverView.board,
    this.onView,
    this.gameName,
    this.onProfile,
    this.onParty,
  });

  final TogetherHub hub;
  final DiscoverView view;

  /// Told when another tab is picked, so the screen opens on it next time.
  final ValueChanged<DiscoverView>? onView;
  final String? Function(String titleId)? gameName;

  /// Opens someone's profile, by handle.
  final ValueChanged<String>? onProfile;

  /// Goes to the party, after joining one or being invited to one.
  final VoidCallback? onParty;

  @override
  State<FindPlayersPane> createState() => _FindPlayersPaneState();
}

class _FindPlayersPaneState extends State<FindPlayersPane> {
  late DiscoverView _view = widget.view;
  bool _composing = false;

  Discover get _discover => widget.hub.discover;

  @override
  void initState() {
    super.initState();
    _discover.show(_view, by: this);
    _discover.loadBoardGames().catchError((_) {});
  }

  @override
  void didUpdateWidget(FindPlayersPane old) {
    super.didUpdateWidget(old);
    if (widget.view != old.view && widget.view != _view) _pick(widget.view);
  }

  @override
  void dispose() {
    _discover.hide(this);
    super.dispose();
  }

  void _pick(DiscoverView view) {
    setState(() {
      _view = view;
      _composing = false;
    });
    _discover.show(view, by: this);
    widget.onView?.call(view);
  }

  /// A game's name: the Mac's, then the catalogue's in the app's language, then its title ID.
  String _name(GameRef game, String language) =>
      widget.gameName?.call(game.titleId) ?? game.name(language);

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: _discover,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (view, label) in [
                          (DiscoverView.board, texts.tabBoard),
                          (DiscoverView.mine, texts.tabMine),
                          (DiscoverView.live, texts.tabLive),
                          (DiscoverView.people, texts.tabPeople),
                        ])
                          _Tab(
                            label: label,
                            selected: _view == view,
                            count: view == DiscoverView.mine
                                ? _discover.waiting
                                : 0,
                            onTap: () => _pick(view),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_composing &&
                    (_view == DiscoverView.board || _view == DiscoverView.mine))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilledButton.icon(
                      onPressed: () => setState(() {
                        _view = DiscoverView.board;
                        _composing = true;
                      }),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(texts.lfgPost),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: KeyedSubtree(
                key: ValueKey((_view, _composing)),
                child: switch (_view) {
                  DiscoverView.board when _composing => LfgForm(
                    hub: widget.hub,
                    gameName: widget.gameName,
                    onCancel: () => setState(() => _composing = false),
                    onPosted: () => _pick(DiscoverView.mine),
                  ),
                  DiscoverView.board => _Board(
                    hub: widget.hub,
                    name: _name,
                    onProfile: widget.onProfile,
                    onParty: widget.onParty,
                  ),
                  DiscoverView.mine => _Mine(
                    hub: widget.hub,
                    name: _name,
                    onProfile: widget.onProfile,
                    onParty: widget.onParty,
                  ),
                  DiscoverView.live => LiveNowPane(
                    hub: widget.hub,
                    gameName: widget.gameName,
                    onProfile: widget.onProfile,
                    onParty: widget.onParty,
                  ),
                  DiscoverView.people => DiscoverPeoplePane(
                    hub: widget.hub,
                    gameName: widget.gameName,
                    onProfile: widget.onProfile,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
  });

  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0x268AB4FF) : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? togetherAccent : Colors.white60,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: togetherAccent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: togetherInk,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A choice among a few, or one of several: a pill, lit while picked. Without [onTap] it
/// cannot be picked (a full list of languages).
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? const Color(0x268AB4FF) : const Color(0x0FFFFFFF),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? const Color(0x668AB4FF) : Colors.transparent,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? togetherAccent
                  : onTap == null
                  ? Colors.white24
                  : Colors.white70,
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

/// A row of [ChoicePill]s that wraps onto the next line.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: children);
}

/// A small rounded label: a post's purpose, a list's way in, a status.
class DiscoverPill extends StatelessWidget {
  const DiscoverPill(this.text, {super.key, this.color = togetherAccent});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A card in the lists of Find players: a picture, what it is in two or three lines, and
/// what one can do with it on the right.
class DiscoverCard extends StatelessWidget {
  const DiscoverCard({
    super.key,
    required this.leading,
    required this.title,
    required this.lines,
    this.pill,
    this.trailing,
    this.below,
  });

  final Widget leading;
  final String title;
  final Widget? pill;
  final List<String> lines;
  final Widget? trailing;

  /// More under the card's own lines (the requests on a post of one's own).
  final Widget? below;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
    decoration: BoxDecoration(
      color: const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x12FFFFFF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (pill != null) ...[const SizedBox(width: 8), pill!],
                    ],
                  ),
                  for (final (index, line) in lines.indexed)
                    if (line.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: index == 0 ? Colors.white60 : Colors.white38,
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
        ?below,
      ],
    ),
  );
}

/// What went wrong, a quiet line with another try.
class DiscoverFailure extends StatelessWidget {
  const DiscoverFailure({super.key, required this.error, required this.retry});

  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              togetherFailure(texts, error),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(onPressed: retry, child: Text(texts.retry)),
        ],
      ),
    );
  }
}

/// A quiet line for a list with nothing in it.
class DiscoverEmpty extends StatelessWidget {
  const DiscoverEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.35),
    ),
  );
}

const _spinner = Padding(
  padding: EdgeInsets.symmetric(vertical: 30),
  child: Center(
    child: SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  ),
);

/// The words for an answer AnyTogether gave a post or an "I'm in".
String lfgFailure(Strings texts, Object error) => switch (error) {
  TogetherProblem(code: 'conflict', extra: final extra?)
      when extra['postStatus'] != null =>
    texts.postClosed,
  TogetherProblem(code: 'conflict', :final title)
      when title.startsWith('At most') =>
    texts.tooManyOpen,
  TogetherProblem(code: 'full') => texts.spotsFull,
  TogetherProblem(code: 'link_blocked', :final extra) => texts.linkBlocked(
    extra?['domain'] as String?,
  ),
  _ => togetherFailure(texts, error),
};

/// When, in which languages, and how many spots are left.
String lfgLine(Strings texts, LfgPost post) {
  final start = post.startsAt;
  return [
    start == null || !start.isAfter(DateTime.now())
        ? texts.startsNow
        : texts.startsAt(start),
    post.languages.map(texts.languageName).join(', '),
    post.left == 0 ? texts.spotsFull : texts.spotsLeft(post.left, post.slots),
  ].where((part) => part.isNotEmpty).join(' · ');
}

/// The board: filters, then the open posts newest first, a page at a time.
class _Board extends StatefulWidget {
  const _Board({
    required this.hub,
    required this.name,
    this.onProfile,
    this.onParty,
  });

  final TogetherHub hub;
  final String Function(GameRef game, String language) name;
  final ValueChanged<String>? onProfile;
  final VoidCallback? onParty;

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  Object? _error;
  bool _older = false;

  Discover get _discover => widget.hub.discover;

  Future<void> _filter(LfgFilter filter) async {
    setState(() => _error = null);
    try {
      await _discover.loadBoard(filter: filter);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    try {
      await step();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(lfgFailure(texts, error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final discover = _discover;
    final filter = discover.filter;
    final filtered =
        filter.titleId != null ||
        filter.purpose != null ||
        filter.language != null ||
        filter.now;
    final games = discover.boardGames;
    final picked = games
        .where((game) => game.game.titleId == filter.titleId)
        .firstOrNull;
    return RefreshIndicator(
      onRefresh: () => _filter(filter),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 16, 16),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Menu<String?>(
                  label: filter.titleId == null
                      ? texts.allGames
                      : picked == null
                      ? filter.titleId!
                      : widget.name(picked.game, texts.language),
                  active: filter.titleId != null,
                  items: [
                    (null, texts.allGames),
                    for (final game in games)
                      (
                        game.game.titleId,
                        '${widget.name(game.game, texts.language)} · ${game.posts}',
                      ),
                  ],
                  onPicked: (titleId) =>
                      _filter(filter.copyWith(titleId: () => titleId)),
                ),
                _Menu<LfgPurpose?>(
                  label: filter.purpose == null
                      ? texts.anything
                      : texts.purpose(filter.purpose!),
                  active: filter.purpose != null,
                  items: [
                    (null, texts.anything),
                    for (final purpose in LfgPurpose.values)
                      (purpose, texts.purpose(purpose)),
                  ],
                  onPicked: (purpose) =>
                      _filter(filter.copyWith(purpose: () => purpose)),
                ),
                _Menu<String?>(
                  label: filter.language == null
                      ? texts.anyLanguage
                      : texts.languageName(filter.language!),
                  active: filter.language != null,
                  items: [
                    (null, texts.anyLanguage),
                    for (final code in offeredLanguages)
                      (code, texts.languageName(code)),
                  ],
                  onPicked: (language) =>
                      _filter(filter.copyWith(language: () => language)),
                ),
                ChoicePill(
                  label: texts.nowOnly,
                  selected: filter.now,
                  onTap: () => _filter(filter.copyWith(now: !filter.now)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!discover.boardLoaded && _error == null) _spinner,
          if (_error != null && discover.board.isEmpty)
            DiscoverFailure(error: _error!, retry: () => _filter(filter)),
          if (discover.boardLoaded && discover.board.isEmpty)
            DiscoverEmpty(filtered ? texts.noPostsFiltered : texts.noPosts),
          for (final post in discover.board)
            LfgCard(
              key: ValueKey(post.id),
              hub: widget.hub,
              post: post,
              name: widget.name,
              onProfile: widget.onProfile,
              onParty: widget.onParty,
              run: _try,
            ),
          if (discover.boardMore)
            Center(
              child: TextButton(
                onPressed: _older
                    ? null
                    : () async {
                        setState(() => _older = true);
                        await discover.olderBoard().catchError((_) {});
                        if (mounted) setState(() => _older = false);
                      },
                child: Text(texts.loadMore),
              ),
            ),
        ],
      ),
    );
  }
}

/// A filter on the board as a chip that opens its choices.
class _Menu<T> extends StatelessWidget {
  const _Menu({
    required this.label,
    required this.items,
    required this.onPicked,
    this.active = false,
  });

  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onPicked;
  final bool active;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: PopupMenuButton<int>(
      color: const Color(0xFF1A1D27),
      tooltip: label,
      onSelected: (index) => onPicked(items[index].$1),
      itemBuilder: (context) => [
        for (final (index, item) in items.indexed)
          PopupMenuItem(value: index, child: Text(item.$2)),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x268AB4FF) : const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? togetherAccent : Colors.white70,
                  fontSize: 13.5,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 20,
              color: active ? togetherAccent : Colors.white38,
            ),
          ],
        ),
      ),
    ),
  );
}

/// A post on the board: the game and what for, when, languages and spots, the note, who
/// posted it; and "I'm in", or where the reader's own "I'm in" stands.
class LfgCard extends StatelessWidget {
  const LfgCard({
    super.key,
    required this.hub,
    required this.post,
    required this.name,
    required this.run,
    this.onProfile,
    this.onParty,
  });

  final TogetherHub hub;
  final LfgPost post;
  final String Function(GameRef game, String language) name;
  final Future<void> Function(Future<void> Function() step) run;
  final ValueChanged<String>? onProfile;
  final VoidCallback? onParty;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final discover = hub.discover;
    final note = post.note;
    return DiscoverCard(
      leading: GestureDetector(
        onTap: onProfile == null ? null : () => onProfile!(post.author.handle),
        child: Avatar(person: post.author, size: 38),
      ),
      title: name(post.game, texts.language),
      pill: DiscoverPill(texts.purpose(post.purpose)),
      lines: [
        lfgLine(texts, post),
        if (note != null && note.isNotEmpty) '“$note”',
        '${post.author.displayName} · @${post.author.handle}',
      ],
      trailing: _action(context, texts, discover),
    );
  }

  Widget _action(BuildContext context, Strings texts, Discover discover) {
    if (post.mine) {
      return Text(
        texts.yourPost,
        style: const TextStyle(color: Colors.white38, fontSize: 12.5),
      );
    }
    final mine = post.myRequest;
    switch (mine?.status) {
      case null:
        final open = post.status == LfgStatus.open && post.left > 0;
        return open
            ? FilledButton.tonal(
                onPressed: () => run(() => discover.imIn(post.id)),
                child: Text(texts.imIn),
              )
            : Text(
                texts.lfgStatus(
                  post.status == LfgStatus.open ? LfgStatus.full : post.status,
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              );
      case LfgAnswer.pending:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texts.askedState,
              style: const TextStyle(color: togetherAccent, fontSize: 13),
            ),
            TextButton(
              onPressed: () => run(() => discover.takeBack(post.id)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.white60,
              ),
              child: Text(texts.takeBack),
            ),
          ],
        );
      case LfgAnswer.accepted:
        final invite = mine!.invite;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texts.youreIn,
              style: const TextStyle(color: togetherPlaying, fontSize: 13),
            ),
            if (invite != null && invite.share)
              TextButton.icon(
                onPressed: () =>
                    openShareWatch(context, hub: hub, sharePlayId: invite.id),
                icon: const Icon(Icons.live_tv_rounded, size: 16),
                label: Text(texts.shareWatch),
              )
            else if (invite != null && onParty != null)
              TextButton.icon(
                onPressed: onParty,
                icon: const Icon(Icons.celebration_rounded, size: 16),
                label: Text(texts.goToParty),
              ),
          ],
        );
      case LfgAnswer.declined:
        return Text(
          texts.notThisTime,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        );
    }
  }
}

/// The reader's own posts with who wants in (let in, or not), closing one; and the posts they
/// said "I'm in" to.
class _Mine extends StatefulWidget {
  const _Mine({
    required this.hub,
    required this.name,
    this.onProfile,
    this.onParty,
  });

  final TogetherHub hub;
  final String Function(GameRef game, String language) name;
  final ValueChanged<String>? onProfile;
  final VoidCallback? onParty;

  @override
  State<_Mine> createState() => _MineState();
}

class _MineState extends State<_Mine> {
  Object? _error;

  Discover get _discover => widget.hub.discover;

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await _discover.loadMine();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    try {
      await step();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(lfgFailure(texts, error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final discover = _discover;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 16, 16),
        children: [
          SectionLabel(texts.yourPosts),
          if (!discover.mineLoaded && _error == null) _spinner,
          if (_error != null && !discover.mineLoaded)
            DiscoverFailure(error: _error!, retry: _load),
          if (discover.mineLoaded && discover.mine.isEmpty)
            DiscoverEmpty(texts.noPostsOfMine),
          for (final post in discover.mine) _myPost(texts, post),
          if (discover.asked.isNotEmpty) ...[
            SectionLabel(texts.yourRequests),
            for (final post in discover.asked)
              LfgCard(
                key: ValueKey('asked ${post.id}'),
                hub: widget.hub,
                post: post,
                name: widget.name,
                onProfile: widget.onProfile,
                onParty: widget.onParty,
                run: _try,
              ),
          ],
        ],
      ),
    );
  }

  Widget _myPost(Strings texts, LfgPost post) {
    final open = post.status == LfgStatus.open;
    final note = post.note;
    return DiscoverCard(
      key: ValueKey('mine ${post.id}'),
      leading: SizedBox.square(
        dimension: 38,
        child: Icon(
          Icons.campaign_rounded,
          color: open ? togetherAccent : Colors.white24,
        ),
      ),
      title: widget.name(post.game, texts.language),
      pill: DiscoverPill(
        texts.lfgStatus(post.status),
        color: open ? togetherPlaying : Colors.white54,
      ),
      lines: [
        '${texts.purpose(post.purpose)} · ${lfgLine(texts, post)}',
        if (note != null && note.isNotEmpty) '“$note”',
      ],
      trailing: open
          ? TextButton(
              onPressed: () async {
                final sure = await askFirst(
                  context,
                  question: texts.askClosePost,
                  action: texts.closePost,
                );
                if (sure && mounted) await _try(() => _discover.close(post.id));
              },
              style: TextButton.styleFrom(foregroundColor: togetherError),
              child: Text(texts.closePost),
            )
          : null,
      below: Padding(
        padding: const EdgeInsets.only(left: 50, top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (post.requests.isEmpty && open)
              Text(
                texts.noRequestsYet,
                style: const TextStyle(color: Colors.white38, fontSize: 12.5),
              ),
            for (final request in post.requests)
              _RequestRow(
                person: request.person,
                onProfile: widget.onProfile,
                trailing: switch (request.status) {
                  LfgAnswer.pending when open => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _try(
                          () => _discover.answer(
                            post.id,
                            request.person.id,
                            accept: false,
                          ),
                        ),
                        child: Text(
                          texts.decline,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => _try(
                          () => _discover.answer(
                            post.id,
                            request.person.id,
                            accept: true,
                          ),
                        ),
                        child: Text(texts.letIn),
                      ),
                    ],
                  ),
                  LfgAnswer.pending => Text(
                    texts.wantsIn,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12.5,
                    ),
                  ),
                  LfgAnswer.accepted => Text(
                    request.invite?.share == true
                        ? texts.invitedToShare
                        : texts.invitedToParty,
                    style: const TextStyle(
                      color: togetherPlaying,
                      fontSize: 12.5,
                    ),
                  ),
                  LfgAnswer.declined => Text(
                    texts.requestNo,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12.5,
                    ),
                  ),
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Someone who asked: their picture and name, and the answer on the right.
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.person,
    required this.trailing,
    this.onProfile,
  });

  final Person person;
  final Widget trailing;
  final ValueChanged<String>? onProfile;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onProfile == null ? null : () => onProfile!(person.handle),
            child: Row(
              children: [
                Avatar(person: person, size: 28),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    person.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '@${person.handle}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        trailing,
      ],
    ),
  );
}
