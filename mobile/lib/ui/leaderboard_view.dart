import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/leaderboards.dart';
import '../together/together_hub.dart';
import 'activity_tile.dart';
import 'together_widgets.dart';

/// Leaderboards: the boards on the left (all games, then your games and the most played), the
/// board picked on the right with friends or global, points, time or completion for a game,
/// your own rank on top and the people around you when you are further down.
class LeaderboardPane extends StatefulWidget {
  const LeaderboardPane({
    super.key,
    required this.hub,
    this.onProfile,
    this.boards,
  });

  final TogetherHub hub;
  final ValueChanged<String>? onProfile;

  /// For tests; AnyTogether's own otherwise.
  final Leaderboards? boards;

  @override
  State<LeaderboardPane> createState() => _LeaderboardPaneState();
}

class _LeaderboardPaneState extends State<LeaderboardPane> {
  late final Leaderboards _boards =
      widget.boards ?? Leaderboards(widget.hub.account);
  List<BoardGame> _games = const [];

  /// null: all games by trophy points.
  BoardGame? _game;
  BoardKind _kind = BoardKind.points;
  BoardScope _scope = BoardScope.friends;
  Leaderboard? _board;
  Object? _error;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _boards
        .games()
        .then((games) {
          if (mounted) setState(() => _games = games);
        })
        .catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    final mine = ++_asked;
    setState(() => _error = null);
    try {
      final game = _game;
      final board = game == null
          ? await _boards.overall(_scope)
          : await _boards.game(game.game.titleId, _kind, _scope);
      if (mounted && mine == _asked) setState(() => _board = board);
    } on Object catch (error) {
      if (mounted && mine == _asked) {
        setState(() {
          _error = error;
          _board = null;
        });
      }
    }
  }

  void _pick(BoardGame? game) {
    setState(() {
      _game = game;
      if (game == null) _kind = BoardKind.points;
      _board = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 180, child: _picker(texts)),
        const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
        Expanded(child: _boardView(texts)),
      ],
    );
  }

  Widget _picker(Strings texts) {
    final mine = _games.where((g) => g.mine).toList();
    final others = _games.where((g) => !g.mine).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: Text(
            texts.leaderboards,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _BoardRow(
          title: texts.overall,
          icon: const SizedBox.square(
            dimension: 30,
            child: Icon(Icons.emoji_events_rounded, color: togetherAccent),
          ),
          selected: _game == null,
          onTap: () => _pick(null),
        ),
        if (mine.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: SectionLabel(texts.yourGames),
          ),
          for (final game in mine) _gameRow(texts, game),
        ],
        if (others.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: SectionLabel(texts.mostPlayed),
          ),
          for (final game in others) _gameRow(texts, game),
        ],
      ],
    );
  }

  Widget _gameRow(Strings texts, BoardGame game) => _BoardRow(
    title: game.game.name(texts.language),
    subtitle: texts.playersCount(game.players),
    icon: GameIcon(url: game.game.iconUrl, size: 30),
    selected: _game?.game.titleId == game.game.titleId,
    onTap: () => _pick(game),
  );

  Widget _boardView(Strings texts) {
    final board = _board;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Segments<BoardScope>(
              values: BoardScope.values,
              value: _scope,
              label: texts.scope,
              onChanged: (scope) {
                setState(() => _scope = scope);
                _load();
              },
            ),
            if (_game != null)
              _Segments<BoardKind>(
                values: BoardKind.values,
                value: _kind,
                label: texts.boardKind,
                onChanged: (kind) {
                  setState(() => _kind = kind);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (board == null && _error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  texts.boardFailed,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(onPressed: _load, child: Text(texts.retry)),
            ],
          ),
        if (board != null) ...[
          _MyRank(board: board),
          const SizedBox(height: 10),
          if (board.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                texts.boardEmpty(board.scope),
                style: const TextStyle(color: Colors.white54, fontSize: 13.5),
              ),
            ),
          for (final entry in board.entries) _entry(board, entry),
          if (board.around.isNotEmpty) ...[
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
            for (final entry in board.around) _entry(board, entry),
          ],
        ],
      ],
    );
  }

  Widget _entry(Leaderboard board, LeaderboardEntry entry) {
    final texts = Texts.of(context);
    final me = entry.person.id == widget.hub.me;
    final medal = switch (entry.rank) {
      1 => const Color(0xFFFFC94D),
      2 => const Color(0xFFC9D1DC),
      3 => const Color(0xFFD08A5A),
      _ => null,
    };
    return Material(
      color: me ? const Color(0x1A8AB4FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onProfile == null
            ? null
            : () => widget.onProfile!(entry.person.handle),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${entry.rank}',
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
              Avatar(person: entry.person, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.person.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: me ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                texts.boardValue(board.kind, entry.value),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the reader stands: their rank and value, or why they are not on the board.
class _MyRank extends StatelessWidget {
  const _MyRank({required this.board});

  final Leaderboard board;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final rank = board.myRank;
    final String headline;
    final String? note;
    if (rank == null) {
      headline = texts.notRanked;
      note = texts.nothingToRank;
    } else if (!board.listed) {
      headline = texts.notRanked;
      note = texts.wouldBe(rank, library: board.kind == BoardKind.time);
    } else {
      headline = texts.rankOf(rank, board.total);
      note = null;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texts.yourRank.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (rank != null)
            Text(
              texts.boardValue(board.kind, board.myValue),
              style: const TextStyle(
                color: togetherAccent,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Material(
      color: selected ? const Color(0x1F8AB4FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
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
        ),
      ),
    ),
  );
}

/// A few choices side by side, the picked one lit.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in values)
          Semantics(
            button: true,
            selected: option == value,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: option == value ? null : () => onChanged(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: option == value
                      ? const Color(0x338AB4FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label(option),
                  style: TextStyle(
                    color: option == value ? Colors.white : Colors.white54,
                    fontSize: 13,
                    fontWeight: option == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
