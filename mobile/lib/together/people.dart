import 'private_identity.dart';

export 'private_identity.dart';

/// Someone on AnyTogether as the API's name cards show them.
class Person {
  const Person({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatar,
    this.privateName,
    this.privateAvatar,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['userId'] as String,
    handle: json['handle'] as String,
    displayName: json['displayName'] as String,
    avatar: json['avatar'] as String?,
    privateName: json['privateName'] is String
        ? json['privateName'] as String
        : null,
    privateAvatar: json['privateAvatar'] is String
        ? json['privateAvatar'] as String
        : null,
  );

  final String id;
  final String handle;
  final String displayName;

  /// The picture's full address, or null for none.
  final String? avatar;

  /// The friends-only name and picture (AnyTogether's docs/private-identity.md): on the cards of
  /// friends in the answers that carry them, null when not set or not for this user to see.
  /// The picture is a signed link that runs out.
  final String? privateName;
  final String? privateAvatar;

  /// The name to show: the friends-only one when this user may see it (from this card, or the
  /// friends list kept by user ID), else the public one. The handle goes beside a private name.
  String get shownName => ShownIdentity.of(this).name;

  /// The picture to show, the same way.
  String? get shownAvatar => ShownIdentity.of(this).avatar;

  /// "@handle", with the public name too when a private one is shown.
  String get handleLine => ShownIdentity.of(this).handleLine;

  /// One or two letters for a person with no picture.
  String get initials {
    final words = shownName.trim().split(RegExp(r'\s+'));
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
