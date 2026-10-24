import 'dart:typed_data';

import 'activity.dart';
import 'people.dart';
import 'together_account.dart';

/// Who may see a part of a profile; the owner always sees all of it.
enum Audience { everyone, friends, nobody }

/// The parts of a profile privacy settings cover: games and play time, trophies, the friends
/// list, online and what is played, and being found by name.
enum PrivacySection { library, trophies, friends, presence, search }

typedef Privacy = Map<PrivacySection, Audience>;

const defaultPrivacy = <PrivacySection, Audience>{
  PrivacySection.library: Audience.friends,
  PrivacySection.trophies: Audience.friends,
  PrivacySection.friends: Audience.friends,
  PrivacySection.presence: Audience.friends,
  PrivacySection.search: Audience.everyone,
};

Privacy privacyFrom(Object? json) => {
  for (final section in PrivacySection.values)
    section:
        Audience.values
            .where((a) => json is Map && a.name == json[section.name])
            .firstOrNull ??
        defaultPrivacy[section]!,
};

/// The server's limits for a profile, as packages/shared/src/profile.ts has them.
abstract final class ProfileLimits {
  static const handleMin = 3;
  static const handleMax = 20;
  static const nameMax = 40;
  static const bioMax = 160;

  /// What PUT /me/avatar takes: PNG or JPEG, at most 5 MB, at least 32 px a side, at most 25
  /// megapixels; it keeps a 256 px square.
  static const avatarMaxBytes = 5 * 1024 * 1024;
  static const avatarMinSide = 32;
  static const avatarMaxPixels = 25000000;
}

/// Why a handle would be turned down before it is sent, or null when it looks right.
enum HandleIssue { length, characters, dots }

HandleIssue? handleIssue(String raw) {
  final handle = raw.trim().replaceFirst(RegExp('^@'), '').toLowerCase();
  if (handle.length < ProfileLimits.handleMin ||
      handle.length > ProfileLimits.handleMax) {
    return HandleIssue.length;
  }
  if (!RegExp(r'^[a-z0-9_.]+$').hasMatch(handle)) return HandleIssue.characters;
  if (handle.startsWith('.') || handle.endsWith('.') || handle.contains('..')) {
    return HandleIssue.dots;
  }
  return null;
}

/// 🇹🇷 from "TR".
String flagOf(String code) => String.fromCharCodes(
  code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65),
);

/// ISO 3166-1 alpha-2, as the API takes them.
const countryCodes =
    'AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ '
    'BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM '
    'DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS '
    'GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN '
    'KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ '
    'MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM '
    'PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV '
    'SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI '
    'VN VU WF WS YE YT ZA ZM ZW';

/// The signed-in person's own profile, with what only they see.
class OwnProfile {
  const OwnProfile({
    required this.handle,
    required this.displayName,
    this.bio,
    this.avatar,
    this.country,
    this.handleChangeAt,
    this.privacy = defaultPrivacy,
  });

  factory OwnProfile.fromJson(Map<String, dynamic> json) => OwnProfile(
    handle: json['handle'] as String,
    displayName: json['displayName'] as String,
    bio: json['bio'] as String?,
    avatar: json['avatar'] as String?,
    country: json['country'] as String?,
    handleChangeAt: DateTime.tryParse(json['handleChangeAt'] as String? ?? ''),
    privacy: privacyFrom(json['privacy']),
  );

  final String handle;
  final String displayName;
  final String? bio;
  final String? avatar;
  final String? country;

  /// When the handle may change again; null when it may now.
  final DateTime? handleChangeAt;
  final Privacy privacy;

  OwnProfile copyWith({
    String? avatar,
    bool clearAvatar = false,
    Privacy? privacy,
  }) => OwnProfile(
    handle: handle,
    displayName: displayName,
    bio: bio,
    avatar: clearAvatar ? null : avatar ?? this.avatar,
    country: country,
    handleChangeAt: handleChangeAt,
    privacy: privacy ?? this.privacy,
  );
}

enum Friendship { me, none, friends, pendingOut, pendingIn }

/// Someone's card as the asker may see it, and which parts they may open.
class UserProfile {
  const UserProfile({
    required this.person,
    this.bio,
    this.country,
    this.friendship = Friendship.none,
    this.visible = const {},
    this.presence,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final visible = json['visible'];
    return UserProfile(
      person: Person.fromJson(json),
      bio: json['bio'] as String?,
      country: json['country'] as String?,
      friendship: switch (json['friendship']) {
        'me' => Friendship.me,
        'friends' => Friendship.friends,
        'pending_out' => Friendship.pendingOut,
        'pending_in' => Friendship.pendingIn,
        _ => Friendship.none,
      },
      visible: {
        for (final section in PrivacySection.values)
          if (visible is Map && visible[section.name] == true) section,
      },
      presence: json['presence'] is Map<String, dynamic>
          ? Presence.fromJson(json['presence'] as Map<String, dynamic>)
          : null,
    );
  }

  final Person person;
  final String? bio;
  final String? country;
  final Friendship friendship;
  final Set<PrivacySection> visible;
  final Presence? presence;
}

/// A game in someone's library: play time, and trophies when those are shown too.
class LibraryGame {
  const LibraryGame({
    required this.game,
    this.firstPlayedAt,
    this.lastPlayedAt,
    this.secondsPlayed = 0,
    this.trophiesEarned,
    this.trophiesTotal,
    this.progress,
    this.points,
  });

  factory LibraryGame.fromJson(Map<String, dynamic> json) => LibraryGame(
    game: GameRef.fromJson(json),
    firstPlayedAt: DateTime.tryParse(json['firstPlayedAt'] as String? ?? ''),
    lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
    secondsPlayed: (json['secondsPlayed'] as num? ?? 0).toInt(),
    trophiesEarned: (json['trophiesEarned'] as num?)?.toInt(),
    trophiesTotal: (json['trophiesTotal'] as num?)?.toInt(),
    progress: (json['progress'] as num?)?.toInt(),
    points: (json['points'] as num?)?.toInt(),
  );

  final GameRef game;
  final DateTime? firstPlayedAt;
  final DateTime? lastPlayedAt;
  final int secondsPlayed;

  /// null when the trophies are private though the games are not.
  final int? trophiesEarned;
  final int? trophiesTotal;
  final int? progress;
  final int? points;
}

/// A trophy someone earned, newest first on their profile.
class EarnedTrophy {
  const EarnedTrophy({
    required this.game,
    required this.trophyId,
    required this.grade,
    required this.hidden,
    required this.texts,
    required this.earnedAt,
    this.rarity,
    this.rarityLabel,
  });

  factory EarnedTrophy.fromJson(Map<String, dynamic> json) => EarnedTrophy(
    game: GameRef.fromJson(json),
    trophyId: (json['trophyId'] as num? ?? 0).toInt(),
    grade: gradeFrom(json['grade']),
    hidden: json['hidden'] == true,
    texts: trophyTextsFrom(json['texts']),
    earnedAt:
        DateTime.tryParse(json['earnedAt'] as String? ?? '') ?? DateTime.now(),
    rarity: (json['rarity'] as num?)?.toDouble(),
    rarityLabel: rarityFrom(json['rarityLabel']),
  );

  final GameRef game;
  final int trophyId;
  final Grade grade;
  final bool hidden;
  final TrophyTexts? texts;
  final DateTime earnedAt;

  /// The share of players who have it, 0..1.
  final double? rarity;
  final Rarity? rarityLabel;
}

/// What a profile adds up to, from the games shown.
class ProfileTotals {
  const ProfileTotals({
    required this.games,
    required this.seconds,
    required this.trophies,
    required this.points,
    required this.platinums,
    required this.countsHidden,
  });

  factory ProfileTotals.of(List<LibraryGame> games, List<EarnedTrophy>? won) =>
      ProfileTotals(
        games: games.length,
        seconds: games.fold(0, (sum, g) => sum + g.secondsPlayed),
        trophies: games.fold(0, (sum, g) => sum + (g.trophiesEarned ?? 0)),
        points: games.fold(0, (sum, g) => sum + (g.points ?? 0)),
        platinums: won?.where((t) => t.grade == Grade.platinum).length,
        countsHidden: games.any((g) => g.trophiesEarned == null),
      );

  final int games;
  final int seconds;
  final int trophies;
  final int points;

  /// Among the trophies shown (the newest 200); null when those are private.
  final int? platinums;

  /// The trophies are private though the games are not: counts show as a dash.
  final bool countsHidden;
}

/// Everything a profile shows: the card, and each part the asker may open; a private part is
/// null.
class ProfilePage {
  const ProfilePage({
    required this.profile,
    required this.games,
    required this.trophies,
    required this.friends,
    required this.activity,
  });

  final UserProfile profile;
  final List<LibraryGame>? games;
  final List<EarnedTrophy>? trophies;
  final List<Person>? friends;
  final FeedPage activity;

  ProfileTotals? get totals =>
      games == null ? null : ProfileTotals.of(games!, trophies);
}

/// Profiles on AnyTogether: anyone's (as far as their privacy lets the asker see), and the
/// signed-in person's own, with editing it, its privacy and its picture.
class Profiles {
  Profiles(this.account);

  final TogetherAccount account;

  static String _path(String handle) =>
      'users/${Uri.encodeComponent(handle.replaceFirst(RegExp('^@'), ''))}';

  /// A private part (403) comes back as null; anything else that fails, fails.
  static Future<T?> _shown<T>(Future<T> load) async {
    try {
      return await load;
    } on TogetherProblem catch (problem) {
      if (problem.status == 403) return null;
      rethrow;
    }
  }

  Future<ProfilePage> load(String handle) async {
    final path = _path(handle);
    final [
      card,
      gamesJson,
      trophiesJson,
      friendsJson,
      activity,
    ] = await Future.wait<Map<String, dynamic>?>([
      account.call('GET', path),
      _shown(account.call('GET', '$path/library')),
      _shown(account.call('GET', '$path/trophies')),
      _shown(account.call('GET', '$path/friends')),
      account
          .call('GET', '$path/activity?limit=10')
          .catchError((_) => const <String, dynamic>{}),
    ]);
    final profile = UserProfile.fromJson(card!);
    return ProfilePage(
      profile: profile,
      games: gamesJson == null
          ? null
          : [
              for (final g in (gamesJson['games'] as List? ?? const []))
                LibraryGame.fromJson(g as Map<String, dynamic>),
            ],
      trophies: trophiesJson == null
          ? null
          : [
              for (final t in (trophiesJson['trophies'] as List? ?? const []))
                EarnedTrophy.fromJson(t as Map<String, dynamic>),
            ],
      friends: friendsJson == null
          ? null
          : [
              for (final f in (friendsJson['friends'] as List? ?? const []))
                Person.fromJson(f as Map<String, dynamic>),
            ],
      activity: FeedPage.fromJson(activity ?? const {}),
    );
  }

  /// Older items of someone's recent activity.
  Future<FeedPage> activity(
    String handle, {
    String? before,
  }) async => FeedPage.fromJson(
    await account.call(
      'GET',
      '${_path(handle)}/activity?limit=10${before == null ? '' : '&before=$before'}',
    ),
  );

  Future<OwnProfile> mine() async {
    final json = await account.call('GET', 'me');
    return OwnProfile.fromJson(json['profile'] as Map<String, dynamic>);
  }

  /// Name, bio and country; an empty bio and a null country clear them.
  Future<OwnProfile> save({
    required String displayName,
    required String bio,
    required String? country,
  }) async {
    final profile = OwnProfile.fromJson(
      await account.call('PATCH', 'me/profile', {
        'displayName': displayName.trim(),
        'bio': bio.trim().isEmpty ? null : bio.trim(),
        'country': country,
      }),
    );
    account.renamed(displayName: profile.displayName);
    return profile;
  }

  Future<OwnProfile> changeHandle(String handle) async {
    final profile = OwnProfile.fromJson(
      await account.call('PATCH', 'me/handle', {
        'handle': handle.trim().replaceFirst(RegExp('^@'), '').toLowerCase(),
      }),
    );
    account.renamed(handle: profile.handle);
    return profile;
  }

  Future<Privacy> setPrivacy(PrivacySection section, Audience audience) async =>
      privacyFrom(
        await account.call('PATCH', 'me/privacy', {
          section.name: audience.name,
        }),
      );

  /// A square picture (PNG or JPEG) as the new avatar; its address comes back.
  Future<String> uploadAvatar(Uint8List bytes) async {
    final png = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final json = await account.upload(
      'me/avatar',
      bytes,
      png ? 'image/png' : 'image/jpeg',
    );
    return json['avatar'] as String;
  }

  Future<void> removeAvatar() => account.call('DELETE', 'me/avatar');
}
