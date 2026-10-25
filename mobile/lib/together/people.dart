/// Someone on AnyTogether as the API's name cards show them.
class Person {
  const Person({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatar,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['userId'] as String,
    handle: json['handle'] as String,
    displayName: json['displayName'] as String,
    avatar: json['avatar'] as String?,
  );

  final String id;
  final String handle;
  final String displayName;

  /// The picture's full address, or null for none.
  final String? avatar;

  /// One or two letters for a person with no picture.
  String get initials {
    final words = displayName.trim().split(RegExp(r'\s+'));
    final letters = words
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
        .join();
    return letters.isEmpty ? handle.substring(0, 1).toUpperCase() : letters;
  }
}

enum PresenceState { inGame, online, away, offline }

/// A friend sharing the game they play: friends may watch while it is open and not full.
class SharePresence {
  const SharePresence({
    required this.sharePlayId,
    required this.titleId,
    this.title,
    this.open = false,
    this.viewers = 0,
    this.maxViewers = 0,
  });

  static SharePresence? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['sharePlayId'] is! String) {
      return null;
    }
    return SharePresence(
      sharePlayId: json['sharePlayId'] as String,
      titleId: json['titleId'] as String? ?? '',
      title: json['title'] as String?,
      open: json['open'] == true,
      viewers: (json['viewers'] as num?)?.toInt() ?? 0,
      maxViewers: (json['maxViewers'] as num?)?.toInt() ?? 0,
    );
  }

  final String sharePlayId;
  final String titleId;
  final String? title;
  final bool open;
  final int viewers;
  final int maxViewers;
}

/// A game session a friend hosts: friends may join it from the Mac's launcher while it is
/// [joinable] (open to friends and not full).
class GamePresence {
  const GamePresence({
    required this.sessionId,
    required this.titleId,
    this.joinable = false,
    this.players = 0,
    this.capacity = 0,
  });

  static GamePresence? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['sessionId'] is! String) {
      return null;
    }
    return GamePresence(
      sessionId: json['sessionId'] as String,
      titleId: json['titleId'] as String? ?? '',
      joinable: json['joinable'] == true,
      players: (json['players'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
    );
  }

  final String sessionId;
  final String titleId;
  final bool joinable;
  final int players;
  final int capacity;
}

/// What a friend shows: in a game (which, since when), online, away or offline, the party
/// they are in, the game session they host, and the game they share.
class Presence {
  const Presence({
    this.state = PresenceState.offline,
    this.titleId,
    this.since,
    this.partyId,
    this.partyOpen = false,
    this.game,
    this.share,
  });

  factory Presence.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Presence();
    final party = json['party'];
    return Presence(
      state: switch (json['state']) {
        'in_game' => PresenceState.inGame,
        'online' => PresenceState.online,
        'away' => PresenceState.away,
        _ => PresenceState.offline,
      },
      titleId: json['titleId'] as String?,
      since: DateTime.tryParse(json['since'] as String? ?? ''),
      partyId: party is Map<String, dynamic> ? party['id'] as String? : null,
      partyOpen: party is Map<String, dynamic> && party['open'] == true,
      game: GamePresence.fromJson(json['game']),
      share: SharePresence.fromJson(json['share']),
    );
  }

  static const offline = Presence();

  final PresenceState state;
  final String? titleId;
  final DateTime? since;

  /// The party they are in, and whether friends may walk in.
  final String? partyId;
  final bool partyOpen;

  /// The game session they host, while they do.
  final GamePresence? game;

  /// Their share play, while they share.
  final SharePresence? share;
}

/// A friend and what they are doing.
class Friend {
  const Friend(this.person, this.presence);

  final Person person;
  final Presence presence;
}
