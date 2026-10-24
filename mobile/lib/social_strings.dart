import 'strings.dart';
import 'together/activity.dart';
import 'together/leaderboards.dart';
import 'together/profiles.dart';

/// AnyTogether's social texts (profiles, the feed, leaderboards, calls), English and Turkish,
/// beside [Strings] so the two grow apart without touching each other. The wording follows the
/// website's.
extension SocialTexts on Strings {
  String _s(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String _fill(String key, Map<String, Object> values) {
    var text = _s(key);
    values.forEach(
      (name, value) => text = text.replaceAll('{$name}', '$value'),
    );
    return text;
  }

  // Profiles

  String get profile => _s('profile');
  String get myProfile => _s('myProfile');
  String get editProfile => _s('editProfile');
  String get noBio => _s('noBio');
  String get statGames => _s('statGames');
  String get statPlayed => _s('statPlayed');
  String get statTrophies => _s('statTrophies');
  String get statPoints => _s('statPoints');
  String get statPlatinums => _s('statPlatinums');
  String get library => _s('library');
  String get recentTrophies => _s('recentTrophies');
  String get recentActivity => _s('recentActivity');
  String get noGamesYet => _s('noGamesYet');
  String get noTrophiesYet => _s('noTrophiesYet');
  String get noActivity => _s('noActivity');
  String get hiddenTrophy => _s('hiddenTrophy');
  String privateSection(String name) => _fill('privateSection', {'name': name});
  String trophiesOf(int earned, int total) =>
      _fill('trophiesOf', {'e': earned, 't': total});
  String ofPlayers(double rarity) =>
      _fill('ofPlayers', {'p': rarityPercent(rarity)});
  String lastPlayed(DateTime when) =>
      _fill('lastPlayed', {'when': daysAgo(when)});
  String grade(Grade grade) => _s('grade_${grade.name}');
  String rarity(Rarity rarity) => _s('rarity_${rarity.name}');
  String get areFriends => _s('areFriends');
  String get requestPending => _s('requestPending');
  String get addFriend => _s('addFriend');
  String wantsToBeFriends(String name) =>
      _fill('wantsToBeFriends', {'name': name});
  String get thisIsYou => _s('thisIsYou');
  String get profileFailed => _s('profileFailed');
  String get friendsList => _s('friendsList');

  // Editing

  String get displayName => _s('displayName');
  String get handle => _s('handle');
  String get handleHint => _s('handleHint');
  String handleNextChange(DateTime date) =>
      _fill('handleNextChange', {'date': day(date)});
  String handleIssue(HandleIssue issue) => _s('handle_${issue.name}');
  String get bio => _s('bio');
  String get bioPlaceholder => _s('bioPlaceholder');
  String get country => _s('country');
  String get noCountry => _s('noCountry');
  String get searchCountry => _s('searchCountry');
  String get save => _s('save');
  String get saved => _s('saved');
  String get privacy => _s('privacy');
  String get privacyLead => _s('privacyLead');
  String privacySection(PrivacySection section) =>
      _s('privacy_${section.name}');
  String audience(Audience audience, {bool search = false}) =>
      search && audience == Audience.nobody
      ? _s('vis_nobody_search')
      : _s('vis_${audience.name}');
  String get searchHint => _s('searchHint');
  String get avatar => _s('avatar');
  String get changeAvatar => _s('changeAvatar');
  String get removeAvatar => _s('removeAvatar');
  String get avatarHint => _s('avatarHint');
  String get cropHint => _s('cropHint');
  String get zoom => _s('zoom');
  String get useAvatar => _s('useAvatar');
  String get avatarTooBig => _s('avatarTooBig');
  String get avatarWrongType => _s('avatarWrongType');
  String get avatarBad => _s('avatarBad');
  String get photoDenied => _s('photoDenied');

  /// What went wrong saving a profile, in words, for the codes the API uses.
  String? profileProblem(String code, Map<String, dynamic>? extra) =>
      switch (code) {
        'handle_taken' => _s('handleTaken'),
        'handle_reserved' => _s('handleReserved'),
        'handle_cooldown' => switch (DateTime.tryParse(
          '${extra?['handleChangeAt']}',
        )) {
          final at? => handleNextChange(at),
          null => _s('handleCooldown'),
        },
        'links_not_allowed' => _s('noLinks'),
        'payload_too_large' => avatarTooBig,
        'unsupported_media_type' => avatarWrongType,
        'bad_image' => avatarBad,
        'rate_limited' => _s('rateLimited'),
        _ => null,
      };

  // The feed

  String get feed => _s('feed');
  String get feedLead => _s('feedLead');
  String get feedEmpty => _s('feedEmpty');
  String get feedEmptyNoFriends => _s('feedEmptyNoFriends');
  String get loadMore => _s('loadMore');
  String get rare => _s('rare');
  String get platinumTag => _s('platinumTag');
  String get milestoneTag => _s('milestoneTag');
  String andMore(int n) => _fill('andMore', {'n': n});
  String reactionName(Reaction reaction) => _s('react_${reaction.name}');

  /// What an item says, with {name}, {game}, {trophy} and {friend} left for the caller to set
  /// apart (bold names), and the rest filled in.
  String activityLine(Activity item) => switch (item.kind) {
    ActivityKind.trophy when item.trophyCount > 1 => _fill('act_trophy_many', {
      'n': item.trophyCount,
    }),
    ActivityKind.trophy => _s('act_trophy_one'),
    ActivityKind.platinum => _s('act_platinum'),
    ActivityKind.firstPlay => _s('act_first_play'),
    ActivityKind.longSession => _fill('act_long_session', {
      'time': playTime(item.seconds ?? 0),
    }),
    ActivityKind.friendship => _s('act_friendship'),
    ActivityKind.milestone => _fill(
      'act_milestone_${item.milestoneKind ?? 'trophies'}',
      {'value': number(item.milestoneValue ?? 0)},
    ),
  };

  /// "3 min ago", "2 h ago", then [daysAgo].
  String ago(DateTime when, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(when);
    if (elapsed.inMinutes < 1) return _s('justNow');
    if (elapsed.inMinutes < 60) {
      return _fill('minutesAgo', {'n': elapsed.inMinutes});
    }
    if (elapsed.inHours < 24) return _fill('hoursAgo', {'n': elapsed.inHours});
    return daysAgo(when, now: now);
  }

  // Leaderboards

  String get leaderboards => _s('leaderboards');
  String get boardsLead => _s('boardsLead');
  String get overall => _s('overall');
  String get yourGames => _s('yourGames');
  String get mostPlayed => _s('mostPlayed');
  String scope(BoardScope scope) => _s('scope_${scope.name}');
  String boardKind(BoardKind kind) => _s('board_${kind.name}');
  String get yourRank => _s('yourRank');
  String rankOf(int rank, int total) =>
      _fill('rankOf', {'rank': rank, 'total': number(total)});
  String get notRanked => _s('notRanked');
  String wouldBe(int rank, {required bool library}) =>
      _fill(library ? 'wouldBeLibrary' : 'wouldBe', {'rank': rank});
  String get nothingToRank => _s('nothingToRank');
  String boardEmpty(BoardScope scope) =>
      _s(scope == BoardScope.global ? 'boardEmptyGlobal' : 'boardEmpty');
  String playersCount(int n) => _fill('playersCount', {'n': number(n)});
  String get boardFailed => _s('boardFailed');

  /// A board's value as it reads: "1,230 pts", "12 h", "85%".
  String boardValue(BoardKind kind, int value) => switch (kind) {
    BoardKind.points => _fill('pointsValue', {'n': number(value)}),
    BoardKind.time => totalTime(value),
    BoardKind.completion => language == 'tr' ? '%$value' : '$value%',
  };

  // Times and numbers

  /// "42 min", "3 h 5 min".
  String playTime(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return _fill('minutes', {'m': minutes});
    return _fill('hours', {'h': minutes ~/ 60, 'm': minutes % 60});
  }

  /// Hours only, for the totals: "128 h", or minutes under an hour.
  String totalTime(int seconds) {
    final minutes = seconds ~/ 60;
    return minutes < 60
        ? _fill('minutes', {'m': minutes})
        : _fill('hoursOnly', {'h': minutes ~/ 60});
  }

  /// "today", "yesterday", "3 days ago", then the date.
  String daysAgo(DateTime when, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final local = when.toLocal();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(local.year, local.month, local.day)).inDays;
    if (days <= 0) return _s('today');
    if (days == 1) return _s('yesterday');
    if (days < 30) return _fill('daysAgo', {'n': days});
    return day(local);
  }

  /// "24.10.2026".
  String day(DateTime when) {
    final local = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  /// 12 345 as the language groups it.
  String number(int value) {
    final digits = value.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => language == 'tr' ? '.' : ',',
    );
    return value < 0 ? '-$grouped' : grouped;
  }

  /// "1.2 %" of players: one decimal under 10 %.
  String rarityPercent(double rarity) {
    final percent = rarity * 100;
    final text = percent < 10
        ? percent.toStringAsFixed(1)
        : percent.round().toString();
    final local = language == 'tr' ? text.replaceAll('.', ',') : text;
    return language == 'tr' ? '%$local' : '$local%';
  }
}

const _en = {
  'leaderboards': 'Leaderboards',
  'boardsLead':
      'Trophy points, play time and completion, among friends or everyone.',
  'overall': 'All games',
  'yourGames': 'Your games',
  'mostPlayed': 'Most played',
  'scope_friends': 'Friends',
  'scope_global': 'Global',
  'board_points': 'Points',
  'board_time': 'Time',
  'board_completion': 'Completion',
  'yourRank': 'Your rank',
  'rankOf': '#{rank} of {total}',
  'notRanked': 'Not ranked yet',
  'wouldBe': 'You would be #{rank}: your trophies are not public, so the global board leaves you out.',
  'wouldBeLibrary': 'You would be #{rank}: your games are not public, so the global board leaves you out.',
  'nothingToRank': 'Play and earn trophies to get on the board.',
  'boardEmpty': 'No one on this board yet.',
  'boardEmptyGlobal': 'No one on this board yet. Only players whose trophies are public show up here.',
  'pointsValue': '{n} pts',
  'playersCount': '{n} players',
  'boardFailed': "Couldn't load this board",
  'feed': 'Activity',
  'feedLead': 'What your friends played, earned and reached.',
  'feedEmpty': 'Nothing here yet. When your friends earn trophies or start a new game, it shows up here.',
  'feedEmptyNoFriends': 'Add friends to see what they play and earn.',
  'loadMore': 'Show older',
  'rare': 'Rare',
  'platinumTag': 'Platinum',
  'milestoneTag': 'Milestone',
  'andMore': '+{n} more',
  'react_fire': 'Fire',
  'react_clap': 'Applause',
  'react_wow': 'Wow',
  'react_heart': 'Love',
  'act_trophy_one': '{name} earned {trophy} in {game}',
  'act_trophy_many': '{name} earned {n} trophies in {game}',
  'act_platinum': '{name} earned the platinum in {game}',
  'act_first_play': '{name} started playing {game}',
  'act_long_session': '{name} played {game} for {time}',
  'act_friendship': '{name} and {friend} are now friends',
  'act_milestone_trophies': '{name} reached {value} trophies',
  'act_milestone_platinums': '{name} reached {value} platinums',
  'act_milestone_games': '{name} has played {value} games',
  'act_milestone_hours': '{name} has played for {value} hours',
  'justNow': 'just now',
  'minutesAgo': '{n} min ago',
  'hoursAgo': '{n} h ago',
  'profile': 'Profile',
  'myProfile': 'Your profile',
  'editProfile': 'Edit profile',
  'noBio': 'No bio yet.',
  'statGames': 'Games',
  'statPlayed': 'Played',
  'statTrophies': 'Trophies',
  'statPoints': 'Points',
  'statPlatinums': 'Platinums',
  'library': 'Games',
  'recentTrophies': 'Trophies',
  'recentActivity': 'Activity',
  'noGamesYet': 'No games yet. They show up here after playing in an AnyPS5 launcher signed in to AnyTogether.',
  'noTrophiesYet': 'No trophies yet.',
  'noActivity': 'Nothing yet.',
  'hiddenTrophy': 'Hidden trophy',
  'privateSection': '{name} keeps this private.',
  'trophiesOf': '{e} of {t} trophies',
  'ofPlayers': '{p} of players',
  'lastPlayed': 'last played {when}',
  'grade_bronze': 'Bronze',
  'grade_silver': 'Silver',
  'grade_gold': 'Gold',
  'grade_platinum': 'Platinum',
  'rarity_common': 'Common',
  'rarity_uncommon': 'Uncommon',
  'rarity_rare': 'Rare',
  'rarity_veryRare': 'Very rare',
  'rarity_ultraRare': 'Ultra rare',
  'areFriends': 'Friends',
  'requestPending': 'Request sent',
  'addFriend': 'Add friend',
  'wantsToBeFriends': '{name} wants to be your friend.',
  'thisIsYou': 'This is you',
  'profileFailed': "Couldn't load this profile",
  'friendsList': 'Friends',
  'displayName': 'Name',
  'handle': 'Handle',
  'handleHint': '3 to 20 of a-z, 0-9, _ and . Once every 30 days; the old one keeps leading here for 30 days.',
  'handleNextChange': 'You can change it again on {date}.',
  'handleCooldown': 'You changed your handle lately; try again later.',
  'handle_length': 'Use 3 to 20 characters.',
  'handle_characters': 'Use only a-z, 0-9, _ and .',
  'handle_dots': 'No dot at either end, and no two dots in a row.',
  'handleTaken': 'That handle is taken.',
  'handleReserved': 'That handle is reserved.',
  'noLinks': 'Names and bios cannot carry links.',
  'rateLimited': 'Too many changes at once; wait a moment.',
  'bio': 'Bio',
  'bioPlaceholder': 'A line about you and what you play',
  'country': 'Country',
  'noCountry': 'Not shown',
  'searchCountry': 'Country code, like TR',
  'save': 'Save',
  'saved': 'Saved',
  'privacy': 'Privacy',
  'privacyLead': 'Your card (picture, name, handle, bio) is shown to anyone signed in. Choose who sees the rest; you always see all of it.',
  'privacy_library': 'Games and play time',
  'privacy_trophies': 'Trophies',
  'privacy_friends': 'Friends list',
  'privacy_presence': 'Online and what you play',
  'privacy_search': 'Finding you by name',
  'vis_everyone': 'Everyone',
  'vis_friends': 'Friends',
  'vis_nobody': 'Only me',
  'vis_nobody_search': 'No one',
  'searchHint': 'A friend request to your exact handle always works.',
  'avatar': 'Picture',
  'changeAvatar': 'Change picture',
  'removeAvatar': 'Remove',
  'avatarHint': 'From your photo library, cropped square.',
  'cropHint': 'Drag to move it, pinch or slide to zoom.',
  'zoom': 'Zoom',
  'useAvatar': 'Use this picture',
  'avatarTooBig': 'That file is over 5 MB.',
  'avatarWrongType': 'Choose a PNG or JPEG picture.',
  'avatarBad': 'That picture could not be read. Try another one, at least 32 px on each side.',
  'photoDenied': 'Allow AnyPS5 Remote to use your photos in Settings.',
  'minutes': '{m} min',
  'hours': '{h} h {m} min',
  'hoursOnly': '{h} h',
  'today': 'today',
  'yesterday': 'yesterday',
  'daysAgo': '{n} days ago',
};

const _tr = {
  'leaderboards': 'Sıralamalar',
  'boardsLead': 'Kupa puanı, oynama süresi ve tamamlama; arkadaşlar arasında ya da herkesle.',
  'overall': 'Tüm oyunlar',
  'yourGames': 'Senin oyunların',
  'mostPlayed': 'En çok oynananlar',
  'scope_friends': 'Arkadaşlar',
  'scope_global': 'Herkes',
  'board_points': 'Puan',
  'board_time': 'Süre',
  'board_completion': 'Tamamlama',
  'yourRank': 'Sıran',
  'rankOf': '{total} kişide #{rank}',
  'notRanked': 'Henüz sıralamada değilsin',
  'wouldBe': '#{rank} olurdun: kupaların herkese açık değil, bu yüzden genel sıralamada yoksun.',
  'wouldBeLibrary': '#{rank} olurdun: oyunların herkese açık değil, bu yüzden genel sıralamada yoksun.',
  'nothingToRank': 'Sıralamaya girmek için oyna ve kupa kazan.',
  'boardEmpty': 'Bu sıralamada henüz kimse yok.',
  'boardEmptyGlobal': 'Bu sıralamada henüz kimse yok. Yalnızca kupaları herkese açık olanlar burada görünür.',
  'pointsValue': '{n} puan',
  'playersCount': '{n} oyuncu',
  'boardFailed': 'Bu sıralama yüklenemedi',
  'feed': 'Etkinlik',
  'feedLead': 'Arkadaşlarının oynadıkları, kazandıkları ve ulaştıkları.',
  'feedEmpty': 'Henüz bir şey yok. Arkadaşların kupa kazanınca ya da yeni bir oyuna başlayınca burada görünür.',
  'feedEmptyNoFriends':
      'Ne oynadıklarını ve kazandıklarını görmek için arkadaş ekle.',
  'loadMore': 'Daha eskiler',
  'rare': 'Nadir',
  'platinumTag': 'Platin',
  'milestoneTag': 'Dönüm noktası',
  'andMore': '+{n} daha',
  'react_fire': 'Ateş',
  'react_clap': 'Alkış',
  'react_wow': 'Vay',
  'react_heart': 'Sevgi',
  'act_trophy_one': '{name}, {game} oyununda {trophy} kupasını kazandı',
  'act_trophy_many': '{name}, {game} oyununda {n} kupa kazandı',
  'act_platinum': '{name}, {game} oyununda platini aldı',
  'act_first_play': '{name}, {game} oynamaya başladı',
  'act_long_session': '{name}, {game} oyununu {time} oynadı',
  'act_friendship': '{name} ile {friend} artık arkadaş',
  'act_milestone_trophies': '{name} {value} kupaya ulaştı',
  'act_milestone_platinums': '{name} {value} platine ulaştı',
  'act_milestone_games': '{name} {value} oyun oynadı',
  'act_milestone_hours': '{name} toplam {value} saat oynadı',
  'justNow': 'az önce',
  'minutesAgo': '{n} dk önce',
  'hoursAgo': '{n} sa önce',
  'profile': 'Profil',
  'myProfile': 'Profilin',
  'editProfile': 'Profili düzenle',
  'noBio': 'Henüz bio yok.',
  'statGames': 'Oyun',
  'statPlayed': 'Oynandı',
  'statTrophies': 'Kupa',
  'statPoints': 'Puan',
  'statPlatinums': 'Platin',
  'library': 'Oyunlar',
  'recentTrophies': 'Kupalar',
  'recentActivity': 'Etkinlik',
  'noGamesYet': "Henüz oyun yok. AnyTogether'a giriş yapmış bir AnyPS5 launcher'ında oynayınca burada görünür.",
  'noTrophiesYet': 'Henüz kupa yok.',
  'noActivity': 'Henüz bir şey yok.',
  'hiddenTrophy': 'Gizli kupa',
  'privateSection': '{name} bunu gizli tutuyor.',
  'trophiesOf': '{t} kupadan {e}',
  'ofPlayers': '{p} oyuncuda',
  'lastPlayed': 'son oynama {when}',
  'grade_bronze': 'Bronz',
  'grade_silver': 'Gümüş',
  'grade_gold': 'Altın',
  'grade_platinum': 'Platin',
  'rarity_common': 'Yaygın',
  'rarity_uncommon': 'Az yaygın',
  'rarity_rare': 'Nadir',
  'rarity_veryRare': 'Çok nadir',
  'rarity_ultraRare': 'Son derece nadir',
  'areFriends': 'Arkadaşsınız',
  'requestPending': 'İstek gönderildi',
  'addFriend': 'Arkadaş ekle',
  'wantsToBeFriends': '{name} arkadaşın olmak istiyor.',
  'thisIsYou': 'Bu sensin',
  'profileFailed': 'Bu profil yüklenemedi',
  'friendsList': 'Arkadaşlar',
  'displayName': 'İsim',
  'handle': 'Kullanıcı adı',
  'handleHint': '3-20 karakter: a-z, 0-9, _ ve . 30 günde bir değişir; eskisi 30 gün boyunca buraya yönlendirir.',
  'handleNextChange': '{date} tarihinde yeniden değiştirebilirsin.',
  'handleCooldown':
      'Kullanıcı adını yakın zamanda değiştirdin; sonra tekrar dene.',
  'handle_length': '3-20 karakter kullan.',
  'handle_characters': 'Yalnızca a-z, 0-9, _ ve . kullan.',
  'handle_dots': 'Başta ya da sonda nokta, art arda iki nokta olmasın.',
  'handleTaken': 'Bu kullanıcı adı alınmış.',
  'handleReserved': 'Bu kullanıcı adı ayrılmış.',
  'noLinks': "İsim ve bio'da bağlantı olamaz.",
  'rateLimited': 'Bir anda çok fazla değişiklik; biraz bekle.',
  'bio': 'Bio',
  'bioPlaceholder': 'Kendin ve oynadıkların hakkında bir satır',
  'country': 'Ülke',
  'noCountry': 'Gösterme',
  'searchCountry': 'Ülke kodu, ör. TR',
  'save': 'Kaydet',
  'saved': 'Kaydedildi',
  'privacy': 'Gizlilik',
  'privacyLead': 'Kartın (resim, isim, kullanıcı adı, bio) giriş yapmış herkese görünür. Gerisini kimin göreceğini seç; sen hepsini her zaman görürsün.',
  'privacy_library': 'Oyunlar ve oynama süresi',
  'privacy_trophies': 'Kupalar',
  'privacy_friends': 'Arkadaş listesi',
  'privacy_presence': 'Çevrimiçi durumu ve ne oynadığın',
  'privacy_search': 'Seni isimle bulma',
  'vis_everyone': 'Herkes',
  'vis_friends': 'Arkadaşlar',
  'vis_nobody': 'Sadece ben',
  'vis_nobody_search': 'Kimse',
  'searchHint':
      'Tam kullanıcı adına arkadaşlık isteği her zaman gönderilebilir.',
  'avatar': 'Resim',
  'changeAvatar': 'Resmi değiştir',
  'removeAvatar': 'Kaldır',
  'avatarHint': 'Fotoğraf arşivinden, kare kırpılmış.',
  'cropHint':
      'Sürükleyerek kaydır, iki parmakla ya da kaydırıcıyla yakınlaştır.',
  'zoom': 'Yakınlaştır',
  'useAvatar': 'Bu resmi kullan',
  'avatarTooBig': "Bu dosya 5 MB'tan büyük.",
  'avatarWrongType': 'PNG ya da JPEG bir resim seç.',
  'avatarBad':
      'Bu resim okunamadı. Her kenarı en az 32 px olan başka bir resim dene.',
  'photoDenied':
      "Ayarlar'dan AnyPS5 Remote'un fotoğraflarını kullanmasına izin ver.",
  'minutes': '{m} dk',
  'hours': '{h} sa {m} dk',
  'hoursOnly': '{h} sa',
  'today': 'bugün',
  'yesterday': 'dün',
  'daysAgo': '{n} gün önce',
};
