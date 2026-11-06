import 'dart:typed_data';

import 'activity.dart';
import 'people.dart';
import 'together_account.dart';

/// Who may see a part of a profile; the owner always sees all of it.
enum Audience { everyone, friends, nobody }

/// The parts of a profile privacy settings cover: games and play time, trophies, the friends
/// list, online and what is played, being found by name, and the pinned photos and clips (the
/// gallery, shown only where the server keeps files).
enum PrivacySection { library, trophies, friends, presence, search, gallery }

typedef Privacy = Map<PrivacySection, Audience>;

const defaultPrivacy = <PrivacySection, Audience>{
  PrivacySection.library: Audience.friends,
  PrivacySection.trophies: Audience.friends,
  PrivacySection.friends: Audience.friends,
  PrivacySection.presence: Audience.friends,
  PrivacySection.search: Audience.everyone,
  PrivacySection.gallery: Audience.friends,
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

/// The tier a trophy level is drawn in: bronze 1-99, silver 100-299, gold 300-599, platinum
/// 600-999.
enum LevelTier { bronze, silver, gold, platinum }

/// The trophy level: one number from all trophy points (the PlayStation curve), with the way to
/// the next one.
class TrophyLevel {
  const TrophyLevel({
    required this.level,
    required this.tier,
    required this.frame,
    this.points = 0,
    this.levelPoints = 0,
    this.nextLevelPoints,
    this.progress = 0,
  });

  /// Null for anything that is not a level (a private one, an answer this phone does not know).
  static TrophyLevel? fromJson(Object? json) {
    if (json is! Map || json['level'] is! int) return null;
    final level = json['level'] as int;
    return TrophyLevel(
      level: level,
      tier: LevelTier.values.asNameMap()[json['tier']] ?? LevelTier.bronze,
      frame: json['frame'] is int ? json['frame'] as int : level ~/ 100 + 1,
      points: json['points'] is int ? json['points'] as int : 0,
      levelPoints: json['levelPoints'] is int ? json['levelPoints'] as int : 0,
      nextLevelPoints: json['nextLevelPoints'] as int?,
      progress: json['progress'] is int ? json['progress'] as int : 0,
    );
  }

  final int level;
  final LevelTier tier;

  /// 1 for levels 1-99, 2 for 100-199 … 10 for 900-999.
  final int frame;
  final int points;
  final int levelPoints;

  /// Null at the top.
  final int? nextLevelPoints;

  /// 0-99 towards the next level (100 at the top).
  final int progress;
}

/// The accents a profile can pick, as the launcher offers them (packages/shared accents).
const profileAccents = <String, int>{
  'blue': 0xFF4F94FF,
  'mint': 0xFF5CEBBD,
  'coral': 0xFFFF8066,
  'violet': 0xFFA885FF,
  'gold': 0xFFFFCC5C,
  'white': 0xFFF0F0F0,
};

/// 0xFFRRGGBB from "#rrggbb", null for anything else.
int? hexColor(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
  return match == null ? null : 0xFF000000 | int.parse(match[1]!, radix: 16);
}

/// The picture a profile picked for behind its header: a preset or a game's artwork.
class ProfileCover {
  const ProfileCover({required this.kind, required this.id, required this.url});

  static ProfileCover? fromJson(Object? json) {
    if (json is! Map || json['url'] is! String) return null;
    return ProfileCover(
      kind: json['kind'] as String? ?? 'preset',
      id: json['id'] as String? ?? '',
      url: json['url'] as String,
    );
  }

  final String kind;
  final String id;
  final String url;
}

class ThemeColors {
  const ThemeColors({
    required this.deep,
    required this.middle,
    required this.bright,
    required this.accent,
  });

  static ThemeColors? fromJson(Object? json) {
    if (json is! Map) return null;
    final [deep, middle, bright, accent] = [
      for (final key in ['deep', 'middle', 'bright', 'accent'])
        hexColor(json[key]),
    ];
    if (deep == null || middle == null || bright == null || accent == null) {
      return null;
    }
    return ThemeColors(
      deep: deep,
      middle: middle,
      bright: bright,
      accent: accent,
    );
  }

  final int deep;
  final int middle;
  final int bright;
  final int accent;
}

/// A Theme Hub theme: the one a profile wears, or one of the Hub's to pick from.
class ProfileTheme {
  const ProfileTheme({
    required this.id,
    required this.name,
    required this.colors,
    required this.preview,
    required this.thumb,
    this.makerHandle,
    this.makerName,
  });

  /// Null for anything that is not a whole theme.
  static ProfileTheme? fromJson(Object? json) {
    if (json is! Map) return null;
    final colors = ThemeColors.fromJson(json['colors']);
    final [id, name, preview, thumb] = [
      for (final key in ['id', 'name', 'preview', 'thumb'])
        json[key] is String ? json[key] as String : null,
    ];
    if (id == null || name == null || colors == null) return null;
    final maker = json['maker'];
    return ProfileTheme(
      id: id,
      name: name,
      colors: colors,
      preview: preview ?? thumb ?? '',
      thumb: thumb ?? preview ?? '',
      makerHandle: maker is Map ? maker['handle'] as String? : null,
      makerName: maker is Map ? maker['displayName'] as String? : null,
    );
  }

  final String id;
  final String name;
  final ThemeColors colors;

  /// 1280x720 and 640x360 stills.
  final String preview;
  final String thumb;
  final String? makerHandle;
  final String? makerName;
}

/// How a profile looks: a cover, an accent and a theme, each null on an older server. A cover
/// and an accent picked win over the theme's.
class ProfileLook {
  const ProfileLook({this.cover, this.accent, this.theme});

  factory ProfileLook.fromJson(Map<String, dynamic> json) => ProfileLook(
    cover: ProfileCover.fromJson(json['cover']),
    accent: profileAccents.containsKey(json['accent'])
        ? json['accent'] as String
        : null,
    theme: ProfileTheme.fromJson(json['theme']),
  );

  final ProfileCover? cover;
  final String? accent;
  final ProfileTheme? theme;

  /// What goes behind the header; null for the app's own.
  String? get picture {
    final url = cover?.url ?? theme?.preview;
    return url == null || url.isEmpty ? null : url;
  }

  /// The highlights' colour as 0xFFRRGGBB; null for the app's own.
  int? get accentColor => profileAccents[accent] ?? theme?.colors.accent;

  bool get isDefault => cover == null && accent == null && theme == null;
}

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
    this.appearOffline = false,
    this.trophyLevel,
    this.readReceipts = true,
    this.privateName,
    this.privateAvatar,
    this.look = const ProfileLook(),
  });

  factory OwnProfile.fromJson(Map<String, dynamic> json) => OwnProfile(
    handle: json['handle'] as String,
    displayName: json['displayName'] as String,
    bio: json['bio'] as String?,
    avatar: json['avatar'] as String?,
    country: json['country'] as String?,
    handleChangeAt: DateTime.tryParse(json['handleChangeAt'] as String? ?? ''),
    privacy: privacyFrom(json['privacy']),
    appearOffline: json['appearOffline'] == true,
    trophyLevel: TrophyLevel.fromJson(json['trophyLevel']),
    // On unless the profile says off (older answers lack it).
    readReceipts: json['readReceipts'] != false,
    privateName: IdentityBook.clean(json['privateName'] as String?),
    privateAvatar: IdentityBook.clean(json['privateAvatar'] as String?),
    look: ProfileLook.fromJson(json),
  );

  final String handle;
  final String displayName;
  final String? bio;
  final String? avatar;
  final String? country;

  /// When the handle may change again; null when it may now.
  final DateTime? handleChangeAt;
  final Privacy privacy;

  /// Signed in and working, but shown to everyone as offline.
  final bool appearOffline;
  final TrophyLevel? trophyLevel;

  /// Others see when this person read their messages (and they see others').
  final bool readReceipts;

  /// The name and picture only accepted friends see; null when not set (or an older server).
  final String? privateName;
  final String? privateAvatar;
  final ProfileLook look;

  OwnProfile copyWith({
    String? avatar,
    bool clearAvatar = false,
    Privacy? privacy,
    bool? appearOffline,
    String? privateName,
    bool clearPrivateName = false,
    String? privateAvatar,
    bool clearPrivateAvatar = false,
    ProfileLook? look,
  }) => OwnProfile(
    handle: handle,
    displayName: displayName,
    bio: bio,
    avatar: clearAvatar ? null : avatar ?? this.avatar,
    country: country,
    handleChangeAt: handleChangeAt,
    privacy: privacy ?? this.privacy,
    appearOffline: appearOffline ?? this.appearOffline,
    trophyLevel: trophyLevel,
    readReceipts: readReceipts,
    privateName: clearPrivateName ? null : privateName ?? this.privateName,
    privateAvatar: clearPrivateAvatar
        ? null
        : privateAvatar ?? this.privateAvatar,
    look: look ?? this.look,
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
    this.trophyLevel,
    this.look = const ProfileLook(),
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
      trophyLevel: TrophyLevel.fromJson(json['trophyLevel']),
      look: ProfileLook.fromJson(json),
    );
  }

  final Person person;
  final String? bio;
  final String? country;
  final Friendship friendship;
  final Set<PrivacySection> visible;
  final Presence? presence;

  /// Null when their trophies are private to the asker (or on an older server).
  final TrophyLevel? trophyLevel;
  final ProfileLook look;
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

/// One pin on a profile's showcase: an earned trophy, or a game from the library.
class ShowcasePin {
  const ShowcasePin.trophy(this.titleId, int this.trophyId);
  const ShowcasePin.game(this.titleId) : trophyId = null;

  final String titleId;

  /// Null for a game.
  final int? trophyId;

  bool get isGame => trophyId == null;

  @override
  bool operator ==(Object other) =>
      other is ShowcasePin &&
      other.titleId == titleId &&
      other.trophyId == trophyId;

  @override
  int get hashCode => Object.hash(titleId, trophyId);
}

/// The pins being picked: six at most, trophies and games together, in the order picked.
class ShowcasePicks {
  ShowcasePicks([Iterable<ShowcasePin> pins = const []])
    : _pins = pins.toSet().take(max).toList();

  static const max = 6;

  final List<ShowcasePin> _pins;

  int get count => _pins.length;
  bool get full => _pins.length >= max;
  bool has(ShowcasePin pin) => _pins.contains(pin);

  /// Unpins a pinned one, or pins another while there is room; false when there is none.
  bool toggle(ShowcasePin pin) {
    if (_pins.remove(pin)) return true;
    if (full) return false;
    _pins.add(pin);
    return true;
  }

  /// What PUT /me/showcase takes: always both lists, since a list left out keeps what is stored
  /// and that counts towards the six too.
  Map<String, dynamic> toJson() => {
    'trophies': [
      for (final pin in _pins)
        if (!pin.isGame) {'titleId': pin.titleId, 'trophyId': pin.trophyId},
    ],
    'games': [
      for (final pin in _pins)
        if (pin.isGame) pin.titleId,
    ],
  };
}

/// What a profile pinned to its top, as far as the asker may see it: a part kept private is null.
/// At most six show, trophies first.
class Showcase {
  const Showcase({this.trophies, this.games});

  factory Showcase.fromJson(Map<String, dynamic> json) {
    final trophies = json['trophies'] is List
        ? [
            for (final t in json['trophies'] as List)
              if (t is Map<String, dynamic> && t['titleId'] is String)
                EarnedTrophy.fromJson(t),
          ].take(ShowcasePicks.max).toList()
        : null;
    final games = json['games'] is List
        ? [
            for (final g in json['games'] as List)
              if (g is Map<String, dynamic> && g['titleId'] is String)
                LibraryGame.fromJson(g),
          ].take(ShowcasePicks.max - (trophies?.length ?? 0)).toList()
        : null;
    return Showcase(trophies: trophies, games: games);
  }

  final List<EarnedTrophy>? trophies;
  final List<LibraryGame>? games;

  int get count => (trophies?.length ?? 0) + (games?.length ?? 0);
  bool get isEmpty => count == 0;

  ShowcasePicks get picks => ShowcasePicks([
    for (final t in trophies ?? const <EarnedTrophy>[])
      ShowcasePin.trophy(t.game.titleId, t.trophyId),
    for (final g in games ?? const <LibraryGame>[])
      ShowcasePin.game(g.game.titleId),
  ]);
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
    this.showcase,
  });

  final UserProfile profile;
  final List<LibraryGame>? games;
  final List<EarnedTrophy>? trophies;
  final List<Person>? friends;
  final FeedPage activity;

  /// Null when the server has none (an older one) or it could not be read: nothing is shown.
  final Showcase? showcase;

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
      showcaseJson,
    ] = await Future.wait<Map<String, dynamic>?>([
      account.call('GET', path),
      _shown(account.call('GET', '$path/library')),
      _shown(account.call('GET', '$path/trophies')),
      _shown(account.call('GET', '$path/friends')),
      account
          .call('GET', '$path/activity?limit=10')
          .catchError((_) => const <String, dynamic>{}),
      _quiet(account.call('GET', '$path/showcase')),
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
      showcase: showcaseJson == null ? null : Showcase.fromJson(showcaseJson),
    );
  }

  static Future<Map<String, dynamic>?> _quiet(
    Future<Map<String, dynamic>> load,
  ) async {
    try {
      return await load;
    } on Object {
      return null;
    }
  }

  /// Pins exactly these, trophies and games together; what the server kept comes back.
  Future<Showcase> saveShowcase(ShowcasePicks picks) async => Showcase.fromJson(
    await account.call('PUT', 'me/showcase', picks.toJson()),
  );

  /// Wears a Theme Hub theme on the profile, or with null takes it off; the look kept comes
  /// back. Putting one on clears the cover and accent.
  Future<ProfileLook> wearTheme(String? themeId) async => ProfileLook.fromJson(
    await account.call('PATCH', 'me/look', {'theme': themeId}),
  );

  /// The Hub's most popular themes, to wear.
  Future<List<ProfileTheme>> themes() async {
    final json = await account.call('GET', 'themes?sort=popular&limit=24');
    return [
      for (final card in json['themes'] as List? ?? const [])
        ?ProfileTheme.fromJson(card),
    ];
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

  /// Appear offline (signed in, shown to everyone as offline) or online again; what the server
  /// kept comes back.
  Future<bool> setAppearOffline(bool appearOffline) async =>
      (await account.call('PATCH', 'me/presence', {
        'appearOffline': appearOffline,
      }))['appearOffline'] ==
      true;

  /// Read receipts sent (and seen) or not; what the server kept comes back.
  Future<bool> setReadReceipts(bool readReceipts) async =>
      (await account.call('PATCH', 'me/read-receipts', {
        'readReceipts': readReceipts,
      }))['readReceipts'] !=
      false;

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

  /// The friends-only name; blank clears it. What the server kept comes back.
  Future<String?> setPrivateName(String name) async {
    final trimmed = name.trim();
    final json = await account.call('PATCH', 'me/profile', {
      'privateName': trimmed.isEmpty ? null : trimmed,
    });
    return json.containsKey('privateName')
        ? IdentityBook.clean(json['privateName'] as String?)
        : IdentityBook.clean(trimmed);
  }

  /// A square picture (PNG or JPEG) as the friends-only one (the public picture stays); its
  /// signed link comes back.
  Future<String> uploadPrivateAvatar(Uint8List bytes) async {
    final png = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final json = await account.upload(
      'me/avatar/private',
      bytes,
      png ? 'image/png' : 'image/jpeg',
    );
    return json['privateAvatar'] as String;
  }

  Future<void> removePrivateAvatar() =>
      account.call('DELETE', 'me/avatar/private');
}
