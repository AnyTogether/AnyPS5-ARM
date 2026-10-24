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

/// What a friend shows: in a game (which, since when), online, away or offline, and the party
/// they are in.
class Presence {
  const Presence({
    this.state = PresenceState.offline,
    this.titleId,
    this.since,
    this.partyId,
    this.partyOpen = false,
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
    );
  }

  static const offline = Presence();

  final PresenceState state;
  final String? titleId;
  final DateTime? since;

  /// The party they are in, and whether friends may walk in.
  final String? partyId;
  final bool partyOpen;
}

/// A friend and what they are doing.
class Friend {
  const Friend(this.person, this.presence);

  final Person person;
  final Presence presence;
}
