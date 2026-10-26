import 'people.dart';

/// The friends' private names and pictures as the last friends list (over HTTP) said, by user
/// ID: realtime events never carry them, so a card from an event takes them from here. A friend
/// gone from the list, or one who cleared them, is forgotten with the next list. The launchers'
/// identity book, rule for rule.
class IdentityBook {
  /// The book the friends list of the account signed in keeps.
  static IdentityBook shared = IdentityBook();

  final Map<String, (String?, String?)> _entries = {};
  DateTime? learnedAt;

  void learn(List<Friend> friends, {DateTime? at}) {
    _entries.clear();
    for (final friend in friends) {
      final name = clean(friend.person.privateName);
      final avatar = clean(friend.person.privateAvatar);
      if (name != null || avatar != null) {
        _entries[friend.person.id] = (name, avatar);
      }
    }
    learnedAt = at ?? DateTime.now();
  }

  /// Signed picture links last 6 to 12 hours: a list older than this is read again.
  bool stale({DateTime? now}) {
    final learned = learnedAt;
    return learned == null ||
        (now ?? DateTime.now()).difference(learned) > const Duration(hours: 5);
  }

  (String?, String?)? operator [](String userId) => _entries[userId];

  static String? clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// What to show for someone: the private name and picture when there, else the public ones,
/// and the handle always beside a private name.
class ShownIdentity {
  const ShownIdentity({
    required this.name,
    required this.avatar,
    required this.handle,
    required this.publicName,
    required this.isPrivate,
  });

  factory ShownIdentity.of(Person person, [IdentityBook? book]) {
    final kept = (book ?? IdentityBook.shared)[person.id];
    final name = IdentityBook.clean(person.privateName) ?? kept?.$1;
    final picture = IdentityBook.clean(person.privateAvatar) ?? kept?.$2;
    return ShownIdentity(
      name: name ?? person.displayName,
      avatar: picture ?? person.avatar,
      handle: person.handle,
      publicName: person.displayName,
      isPrivate: name != null,
    );
  }

  final String name;
  final String? avatar;
  final String handle;
  final String publicName;

  /// The name shown is the friends-only one.
  final bool isPrivate;

  /// "@handle", with the public name too when a private one is shown.
  String get handleLine =>
      isPrivate && publicName != name ? '@$handle · $publicName' : '@$handle';
}
