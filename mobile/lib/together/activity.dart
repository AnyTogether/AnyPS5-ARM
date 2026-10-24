import 'people.dart';

/// A game as AnyTogether names it: its names by language and its icon.
class GameRef {
  const GameRef({required this.titleId, required this.names, this.iconUrl});

  factory GameRef.fromJson(Map<String, dynamic> json) => GameRef(
    titleId: json['titleId'] as String,
    names: namesFrom(json['names'] ?? json['gameNames']),
    iconUrl: json['iconUrl'] as String?,
  );

  final String titleId;
  final Map<String, String> names;
  final String? iconUrl;

  String name(String language) => localName(names, language) ?? titleId;
}

Map<String, String> namesFrom(Object? json) => {
  if (json is Map)
    for (final entry in json.entries)
      if (entry.value is String) '${entry.key}': entry.value as String,
};

/// The name in the language asked for, then its base language, then English, then any.
String? localName(Map<String, String> names, String language) {
  if (names.isEmpty) return null;
  return names[language] ??
      names[language.split('-').first] ??
      names['en'] ??
      names['en-US'] ??
      names.values.first;
}

enum Grade { bronze, silver, gold, platinum }

Grade gradeFrom(Object? value) => switch (value) {
  'platinum' => Grade.platinum,
  'gold' => Grade.gold,
  'silver' => Grade.silver,
  _ => Grade.bronze,
};

/// How rare a trophy is, from the share of players who have it.
enum Rarity { common, uncommon, rare, veryRare, ultraRare }

Rarity? rarityFrom(Object? value) => switch (value) {
  'common' => Rarity.common,
  'uncommon' => Rarity.uncommon,
  'rare' => Rarity.rare,
  'very_rare' => Rarity.veryRare,
  'ultra_rare' => Rarity.ultraRare,
  _ => null,
};

/// A trophy's name and detail by language; null for a hidden one the reader may not see.
typedef TrophyTexts = Map<String, ({String name, String? detail})>;

TrophyTexts? trophyTextsFrom(Object? json) {
  if (json is! Map) return null;
  return {
    for (final entry in json.entries)
      if (entry.value is Map && (entry.value as Map)['name'] is String)
        '${entry.key}': (
          name: (entry.value as Map)['name'] as String,
          detail: (entry.value as Map)['detail'] as String?,
        ),
  };
}

({String name, String? detail})? localTexts(TrophyTexts? texts, String lang) {
  if (texts == null || texts.isEmpty) return null;
  return texts[lang] ??
      texts[lang.split('-').first] ??
      texts['en'] ??
      texts.values.first;
}

/// A trophy as the feed shows it.
class ActivityTrophy {
  const ActivityTrophy({
    required this.trophyId,
    required this.grade,
    required this.hidden,
    required this.texts,
    required this.rarity,
    required this.rarityLabel,
  });

  factory ActivityTrophy.fromJson(Map<String, dynamic> json) => ActivityTrophy(
    trophyId: (json['trophyId'] as num? ?? 0).toInt(),
    grade: gradeFrom(json['grade']),
    hidden: json['hidden'] == true,
    texts: trophyTextsFrom(json['texts']),
    rarity: (json['rarity'] as num?)?.toDouble(),
    rarityLabel: rarityFrom(json['rarityLabel']),
  );

  final int trophyId;
  final Grade grade;
  final bool hidden;
  final TrophyTexts? texts;
  final double? rarity;
  final Rarity? rarityLabel;
}

enum ActivityKind {
  trophy,
  platinum,
  firstPlay,
  longSession,
  friendship,
  milestone,
}

/// The fixed reactions, drawn as 🔥 👏 😮 ❤️; one per person per item.
enum Reaction {
  fire('🔥'),
  clap('👏'),
  wow('😮'),
  heart('❤️');

  const Reaction(this.emoji);

  final String emoji;
}

Reaction? reactionFrom(Object? value) =>
    Reaction.values.where((r) => r.name == value).firstOrNull;

class Reactions {
  const Reactions({this.counts = const {}, this.mine});

  factory Reactions.fromJson(Object? json) {
    if (json is! Map) return const Reactions();
    final counts = json['counts'];
    return Reactions(
      counts: {
        if (counts is Map)
          for (final entry in counts.entries)
            ?reactionFrom(entry.key): (entry.value as num? ?? 0).toInt(),
      },
      mine: reactionFrom(json['mine']),
    );
  }

  final Map<Reaction, int> counts;
  final Reaction? mine;

  int get total => counts.values.fold(0, (sum, n) => sum + n);

  /// [reaction] picked (null: taken back), counted at once, before the server answers.
  Reactions picked(Reaction? reaction) {
    final next = {...counts};
    if (mine != null) {
      next[mine!] = (next[mine!] ?? 1) - 1;
      if (next[mine!]! <= 0) next.remove(mine);
    }
    if (reaction != null) next[reaction] = (next[reaction] ?? 0) + 1;
    return Reactions(counts: next, mine: reaction);
  }
}

/// One item of the activity feed as a reader sees it.
class Activity {
  const Activity({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.actor,
    this.game,
    this.highlight,
    this.trophies = const [],
    this.trophyCount = 0,
    this.seconds,
    this.friend,
    this.milestoneKind,
    this.milestoneValue,
    this.reactions = const Reactions(),
  });

  /// null for a kind this app does not know yet.
  static Activity? fromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']) {
      'trophy' => ActivityKind.trophy,
      'platinum' => ActivityKind.platinum,
      'first_play' => ActivityKind.firstPlay,
      'long_session' => ActivityKind.longSession,
      'friendship' => ActivityKind.friendship,
      'milestone' => ActivityKind.milestone,
      _ => null,
    };
    final actor = json['actor'];
    if (kind == null || actor is! Map<String, dynamic>) return null;
    final milestone = json['milestone'];
    return Activity(
      id: json['id'] as String,
      kind: kind,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      actor: Person.fromJson(actor),
      game: json['game'] is Map<String, dynamic>
          ? GameRef.fromJson(json['game'] as Map<String, dynamic>)
          : null,
      highlight: json['highlight'] as String?,
      trophies: [
        for (final trophy in (json['trophies'] as List? ?? const []))
          ActivityTrophy.fromJson(trophy as Map<String, dynamic>),
      ],
      trophyCount: (json['trophyCount'] as num? ?? 0).toInt(),
      seconds: (json['seconds'] as num?)?.toInt(),
      friend: json['friend'] is Map<String, dynamic>
          ? Person.fromJson(json['friend'] as Map<String, dynamic>)
          : null,
      milestoneKind: milestone is Map ? milestone['kind'] as String? : null,
      milestoneValue: milestone is Map
          ? (milestone['value'] as num?)?.toInt()
          : null,
      reactions: Reactions.fromJson(json['reactions']),
    );
  }

  final String id;
  final ActivityKind kind;
  final DateTime createdAt;
  final Person actor;
  final GameRef? game;

  /// platinum, rare, or null.
  final String? highlight;
  final List<ActivityTrophy> trophies;
  final int trophyCount;
  final int? seconds;
  final Person? friend;

  /// trophies, platinums, games or hours.
  final String? milestoneKind;
  final int? milestoneValue;
  final Reactions reactions;

  Activity withReactions(Reactions next) => Activity(
    id: id,
    kind: kind,
    createdAt: createdAt,
    actor: actor,
    game: game,
    highlight: highlight,
    trophies: trophies,
    trophyCount: trophyCount,
    seconds: seconds,
    friend: friend,
    milestoneKind: milestoneKind,
    milestoneValue: milestoneValue,
    reactions: next,
  );
}

/// A page of the feed, newest first, and where the next (older) one starts.
class FeedPage {
  const FeedPage(this.items, this.next);

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage([
    for (final item in (json['items'] as List? ?? const []))
      ?Activity.fromJson(item as Map<String, dynamic>),
  ], json['next'] as String?);

  final List<Activity> items;
  final String? next;
}
