import 'activity.dart';
import 'notifications.dart';
import 'people.dart';
import 'together_account.dart';

/// What a challenge counts: trophy points or trophies earned in its window, or time played in it.
enum ChallengeMetric { points, trophies, time }

/// Who may see and join one: the maker's friends, a community's members, or everyone.
enum ChallengeAudience { friends, community, public }

/// upcoming: not started; active: running; ended: over (final once [ChallengeView.isFinal]);
/// cancelled: called off.
enum ChallengeState { upcoming, active, ended, cancelled }

T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// A name card, or null when there is none or it is not one (someone the reader may not see).
Person? _person(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  if (json['userId'] is! String ||
      json['handle'] is! String ||
      json['displayName'] is! String) {
    return null;
  }
  return Person.fromJson(json);
}

/// One row of a challenge's standings. Ranks are shared on ties (1, 2, 2, 4).
class ChallengeStanding {
  const ChallengeStanding({
    required this.rank,
    required this.person,
    required this.value,
    required this.me,
  });

  static ChallengeStanding? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ChallengeStanding(
      rank: _int(json['rank']),
      person: _person(json['user']),
      value: _int(json['value']),
      me: json['me'] == true,
    );
  }

  final int rank;

  /// Null for a hidden player (a block either way); their place still counts.
  final Person? person;

  /// Trophy points, trophies, or seconds played, by the challenge's metric.
  final int value;

  /// The reader's own row.
  final bool me;
}

/// A time-boxed race on one game's leaderboard, as the reader sees it.
class ChallengeView {
  const ChallengeView({
    required this.id,
    required this.title,
    required this.description,
    required this.game,
    required this.metric,
    required this.audience,
    required this.communityName,
    required this.creator,
    required this.startsAt,
    required this.endsAt,
    required this.state,
    required this.isFinal,
    required this.entrants,
    required this.joined,
    required this.mine,
    required this.leader,
    required this.myRank,
    required this.myValue,
  });

  /// Null when it is not one this app can show: no ID, title, game or window, or a metric
  /// from a newer server it would count wrong. Unknown fields are left out.
  static ChallengeView? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final title = json['title'];
    final game = json['game'];
    final metric = _named(ChallengeMetric.values, json['metric']);
    final startsAt = DateTime.tryParse('${json['startsAt']}');
    final endsAt = DateTime.tryParse('${json['endsAt']}');
    if (id is! String ||
        title is! String ||
        game is! Map<String, dynamic> ||
        game['titleId'] is! String ||
        metric == null ||
        startsAt == null ||
        endsAt == null) {
      return null;
    }
    final community = json['community'];
    final mine = json['myStanding'];
    final description = json['description'];
    return ChallengeView(
      id: id,
      title: title,
      description: description is String && description.trim().isNotEmpty
          ? description
          : null,
      game: GameRef.fromJson(game),
      metric: metric,
      audience: _named(ChallengeAudience.values, json['audience']),
      communityName: community is Map && community['name'] is String
          ? community['name'] as String
          : null,
      creator: _person(json['creator']),
      startsAt: startsAt,
      endsAt: endsAt,
      state:
          _named(ChallengeState.values, json['state']) ??
          _stateOf(startsAt, endsAt, DateTime.now()),
      isFinal: json['final'] == true,
      entrants: _int(json['entrants']),
      joined: json['joined'] == true,
      mine: json['mine'] == true,
      leader: ChallengeStanding.fromJson(json['leader']),
      myRank: mine is Map && mine['rank'] is num
          ? (mine['rank'] as num).toInt()
          : null,
      myValue: mine is Map ? _int(mine['value']) : 0,
    );
  }

  static ChallengeState _stateOf(DateTime start, DateTime end, DateTime now) =>
      now.isBefore(start)
      ? ChallengeState.upcoming
      : now.isBefore(end)
      ? ChallengeState.active
      : ChallengeState.ended;

  final String id;
  final String title;
  final String? description;
  final GameRef game;
  final ChallengeMetric metric;

  /// Null for a kind of audience from a newer server.
  final ChallengeAudience? audience;

  /// The community's name, for a community challenge.
  final String? communityName;

  /// Null once the maker's account is gone, or for one the reader may not see.
  final Person? creator;
  final DateTime startsAt;
  final DateTime endsAt;
  final ChallengeState state;

  /// Ended and past the grace hour: the standings will not change.
  final bool isFinal;
  final int entrants;
  final bool joined;

  /// The reader made it (and so cannot leave it).
  final bool mine;

  /// First place while it runs, the winner once it ended; null before it starts or with no one
  /// above zero.
  final ChallengeStanding? leader;

  /// The reader's place, when they joined and it started.
  final int? myRank;
  final int myValue;

  /// Can still be joined or left (by someone who did not make it).
  bool get open =>
      state == ChallengeState.upcoming || state == ChallengeState.active;

  /// How much of the window has gone, 0 to 1.
  double progress(DateTime now) {
    final total = endsAt.difference(startsAt).inSeconds;
    if (total <= 0) return now.isBefore(endsAt) ? 0 : 1;
    final gone = now.difference(startsAt).inSeconds / total;
    return gone.clamp(0, 1).toDouble();
  }
}

/// A challenge with its first standings and the reader's neighbours past them.
class ChallengeDetail {
  const ChallengeDetail({
    required this.view,
    required this.standings,
    required this.around,
    required this.updatedAt,
  });

  factory ChallengeDetail.fromJson(Map<String, dynamic> json) {
    final view = ChallengeView.fromJson(json);
    if (view == null) throw const FormatException('not a challenge');
    List<ChallengeStanding> rows(Object? list) => [
      if (list is List)
        for (final row in list) ?ChallengeStanding.fromJson(row),
    ];
    return ChallengeDetail(
      view: view,
      standings: rows(json['standings']),
      around: rows(json['around']),
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
    );
  }

  final ChallengeView view;
  final List<ChallengeStanding> standings;
  final List<ChallengeStanding> around;
  final DateTime? updatedAt;
}

/// The challenge a notification is about, if it is about one.
String? challengeOf(Notice notice) => switch (notice.kind) {
  NoticeKind.challengeInvite ||
  NoticeKind.challengeStarted ||
  NoticeKind.challengeEnded => switch (notice.data['challengeId']) {
    final String id => id,
    _ => notice.subjectId,
  },
  _ => null,
};

/// Challenges on AnyTogether: made on the website, shown where the leaderboards are, joined and
/// left here. A server from before them answers 404, which reads as none.
class Challenges {
  Challenges(this.account);

  final TogetherAccount account;

  /// Running and coming ones on a game the reader may see, soonest first.
  Future<List<ChallengeView>> forGame(String titleId) =>
      _list('challenges?titleId=${Uri.encodeQueryComponent(titleId)}');

  /// The reader's own (joined or made): running and coming, then the last 30 days' ended ones.
  Future<List<ChallengeView>> mine() => _list('me/challenges');

  Future<ChallengeDetail> detail(String id) async =>
      ChallengeDetail.fromJson(await account.call('GET', 'challenges/$id'));

  Future<ChallengeView> join(String id) => _act(id, 'join');

  Future<ChallengeView> leave(String id) => _act(id, 'leave');

  Future<List<ChallengeView>> _list(String path) async {
    final Map<String, dynamic> json;
    try {
      json = await account.call('GET', path);
    } on TogetherProblem catch (problem) {
      if (problem.status == 404) return const [];
      rethrow;
    }
    final list = json['challenges'];
    return [
      if (list is List)
        for (final item in list) ?ChallengeView.fromJson(item),
    ];
  }

  Future<ChallengeView> _act(String id, String action) async {
    final view = ChallengeView.fromJson(
      await account.call('POST', 'challenges/$id/$action', const {}),
    );
    if (view == null) throw const FormatException('not a challenge');
    return view;
  }
}
