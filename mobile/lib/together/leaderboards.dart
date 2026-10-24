import 'activity.dart';
import 'people.dart';
import 'together_account.dart';

/// Among friends, or everyone whose trophies (or games) are public.
enum BoardScope { friends, global }

/// What a board ranks: trophy points (overall or in one game), play time or completion.
enum BoardKind { points, time, completion }

BoardKind boardKindFrom(Object? value) =>
    BoardKind.values.where((k) => k.name == value).firstOrNull ??
    BoardKind.points;

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.person,
    required this.value,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num? ?? 0).toInt(),
        person: Person.fromJson(json['user'] as Map<String, dynamic>),
        value: (json['value'] as num? ?? 0).toInt(),
      );

  final int rank;
  final Person person;

  /// Points, seconds played, or completion percent.
  final int value;
}

/// A board as the reader sees it: the top, the reader's own place, the people around them
/// when they are further down, and how many are on it.
class Leaderboard {
  const Leaderboard({
    required this.kind,
    required this.scope,
    required this.game,
    required this.entries,
    required this.myRank,
    required this.myValue,
    required this.listed,
    required this.around,
    required this.total,
    required this.updatedAt,
  });

  factory Leaderboard.fromJson(Map<String, dynamic> json) {
    final me = json['me'] is Map<String, dynamic>
        ? json['me'] as Map<String, dynamic>
        : const <String, dynamic>{};
    List<LeaderboardEntry> list(Object? value) => [
      for (final entry in (value as List? ?? const []))
        LeaderboardEntry.fromJson(entry as Map<String, dynamic>),
    ];
    return Leaderboard(
      kind: boardKindFrom(json['board']),
      scope: json['scope'] == 'global' ? BoardScope.global : BoardScope.friends,
      game: json['game'] is Map<String, dynamic>
          ? GameRef.fromJson(json['game'] as Map<String, dynamic>)
          : null,
      entries: list(json['entries']),
      myRank: (me['rank'] as num?)?.toInt(),
      myValue: (me['value'] as num? ?? 0).toInt(),
      listed: me['listed'] == true,
      around: list(json['around']),
      total: (json['total'] as num? ?? 0).toInt(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  final BoardKind kind;
  final BoardScope scope;
  final GameRef? game;
  final List<LeaderboardEntry> entries;

  /// The reader's rank (null with nothing to rank); when not [listed] (their part is not
  /// public), where they would be.
  final int? myRank;
  final int myValue;
  final bool listed;
  final List<LeaderboardEntry> around;
  final int total;
  final DateTime? updatedAt;
}

/// A game to pick a board from, the reader's own first, then the most played.
class BoardGame {
  const BoardGame({
    required this.game,
    required this.players,
    required this.mine,
  });

  factory BoardGame.fromJson(Map<String, dynamic> json) => BoardGame(
    game: GameRef.fromJson(json),
    players: (json['players'] as num? ?? 0).toInt(),
    mine: json['mine'] == true,
  );

  final GameRef game;
  final int players;
  final bool mine;
}

/// Leaderboards on AnyTogether: overall by trophy points, and per game by points, time or
/// completion, among friends or everyone.
class Leaderboards {
  Leaderboards(this.account);

  final TogetherAccount account;

  Future<Leaderboard> overall(BoardScope scope) async => Leaderboard.fromJson(
    await account.call('GET', 'leaderboards/points?scope=${scope.name}'),
  );

  Future<Leaderboard> game(
    String titleId,
    BoardKind kind,
    BoardScope scope,
  ) async => Leaderboard.fromJson(
    await account.call(
      'GET',
      'games/$titleId/leaderboard?by=${kind.name}&scope=${scope.name}',
    ),
  );

  Future<List<BoardGame>> games() async {
    final json = await account.call('GET', 'leaderboards/games');
    return [
      for (final game in (json['games'] as List? ?? const []))
        BoardGame.fromJson(game as Map<String, dynamic>),
    ];
  }
}
