import 'package:flutter/foundation.dart';

import 'strings.dart';
import 'together/discover.dart';

/// AnyTogether's texts for meeting people beyond one's friends (a friend's joinable game, the
/// looking-for-group board, public parties and share plays, discovery), English and Turkish,
/// beside [Strings] the way the social texts are. The wording follows the website's.
extension DiscoverTexts on Strings {
  String _d(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String _fill(String key, Map<String, Object> values) {
    var text = _d(key);
    values.forEach(
      (name, value) => text = text.replaceAll('{$name}', '$value'),
    );
    return text;
  }

  // A friend's game

  String get joinable => _d('joinable');
  String joinableCount(int players, int capacity) =>
      _fill('joinableCount', {'n': players, 'max': capacity});
  String get joinableHint => _d('joinableHint');

  // Find players

  String get findPlayers => _d('findPlayers');
  String get tabBoard => _d('tabBoard');
  String get tabMine => _d('tabMine');
  String get tabLive => _d('tabLive');
  String get tabPeople => _d('tabPeople');

  // The board

  String get lfgPost => _d('lfgPost');
  String get lfgNew => _d('lfgNew');
  String get lfgNewLead => _d('lfgNewLead');
  String purpose(LfgPurpose purpose) => _d('purpose_${purpose.name}');
  String purposeHint(LfgPurpose purpose) => _d('purposeHint_${purpose.name}');
  String get allGames => _d('allGames');
  String get anything => _d('anything');
  String get anyLanguage => _d('anyLanguage');
  String get nowOnly => _d('nowOnly');
  String get startsNow => _d('startsNow');
  String startsAt(DateTime when) {
    final local = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return _fill('startsAtTime', {
      'time': '${two(local.hour)}:${two(local.minute)}',
    });
  }

  String spotsLeft(int left, int total) =>
      _fill('spotsLeft', {'n': left, 'total': total});
  String get spotsFull => _d('spotsFull');
  String get imIn => _d('imIn');
  String get takeBack => _d('takeBack');
  String get askedState => _d('askedState');
  String get youreIn => _d('youreIn');
  String get notThisTime => _d('notThisTime');
  String get goToParty => _d('goToParty');
  String get yourPost => _d('yourPost');
  String get noPosts => _d('noPosts');
  String get noPostsFiltered => _d('noPostsFiltered');
  String get yourPosts => _d('yourPosts');
  String get yourRequests => _d('yourRequests');
  String get noPostsOfMine => _d('noPostsOfMine');
  String get wantsIn => _d('wantsIn');
  String get noRequestsYet => _d('noRequestsYet');
  String get letIn => _d('letIn');
  String get requestIn => _d('requestIn');
  String get requestNo => _d('requestNo');
  String get closePost => _d('closePost');
  String lfgStatus(LfgStatus status) => _d('status_${status.name}');
  String get invitedToParty => _d('invitedToParty');
  String get invitedToShare => _d('invitedToShare');

  // A new post

  String get lfgPickGame => _d('lfgPickGame');
  String get otherGame => _d('otherGame');
  String get titleIdHint => _d('titleIdHint');
  String get whatFor => _d('whatFor');
  String get when => _d('when');
  String inMinutes(int minutes) => minutes < 60
      ? _fill('inMinutes', {'n': minutes})
      : _fill('inHours', {'n': minutes ~/ 60});
  String get languagesUpTo => _d('languagesUpTo');
  String get playersWanted => _d('playersWanted');
  String get note => _d('note');
  String get notePlaceholder => _d('notePlaceholder');
  String get endsAfter => _d('endsAfter');
  String hoursN(int n) => _fill('hoursN', {'n': n});
  String get postIt => _d('postIt');
  String get tooManyOpen => _d('tooManyOpen');
  String get postClosed => _d('postClosed');
  String draftIssue(LfgDraftIssue issue) => _d('draft_${issue.name}');

  // Live now

  String get liveNow => _d('liveNow');
  String get liveLead => _d('liveLead');
  String get liveFlair => _d('liveFlair');
  String get publicParties => _d('publicParties');
  String get noLive => _d('noLive');
  String get noPublicParties => _d('noPublicParties');
  String get askToJoin => _d('askToJoin');
  String watching(int n, int max) => _fill('watching', {'n': n, 'max': max});
  String partyCount(int n, int max) =>
      _fill('partyCount', {'n': n, 'max': max});
  String get joinOpenFlair => _d('joinOpenFlair');
  String get joinRequestFlair => _d('joinRequestFlair');
  String hostedBy(String name) => _fill('hostedBy', {'name': name});
  String get noGameListed => _d('noGameListed');
  String get inThisParty => _d('inThisParty');
  String get full => _d('full');

  // The party

  String get partyPublic => _d('partyPublic');
  String get partyPublicHint => _d('partyPublicHint');
  String get publicOff => _d('publicOff');
  String get joinModeRequest => _d('joinModeRequest');
  String get joinModeOpen => _d('joinModeOpen');
  String get listLanguage => _d('listLanguage');
  String get noLanguage => _d('noLanguage');
  String get askingToJoin => _d('askingToJoin');

  // People

  String get peopleLead => _d('peopleLead');
  String get suggestions => _d('suggestions');
  String get noSuggestions => _d('noSuggestions');
  String reasonFriends(int n) =>
      n == 1 ? _d('reasonFriend') : _fill('reasonFriends', {'n': n});
  String reasonGame(String game) => _fill('reasonGame', {'game': game});
  String reasonLanguage(String code) =>
      _fill('reasonLanguage', {'language': languageName(code)});
  String get requested => _d('requested');
  String get sectionDiscovery => _d('sectionDiscovery');
  String get discoveryLead => _d('discoveryLead');
  String get showInDiscovery => _d('showInDiscovery');
  String get discoveryFollow => _d('discoveryFollow');
  String get discoveryOn => _d('discoveryOn');
  String get discoveryOff => _d('discoveryOff');
  String get discoveryShown => _d('discoveryShown');
  String get discoveryHidden => _d('discoveryHidden');
  String get languagesYouPlay => _d('languagesYouPlay');
  String get languagesHint => _d('languagesHint');

  /// A language's name in the app's language; its code for one the app does not name.
  String languageName(String code) =>
      (language == 'tr' ? _trLanguages : _enLanguages)[code] ??
      code.toUpperCase();
}

/// The languages offered for posts, lists and discovery, the most played first.
const offeredLanguages = [
  'en',
  'tr',
  'de',
  'fr',
  'es',
  'it',
  'pt',
  'ru',
  'pl',
  'nl',
  'ar',
  'ja',
  'ko',
  'zh',
];

const _enLanguages = {
  'en': 'English',
  'tr': 'Turkish',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'pl': 'Polish',
  'nl': 'Dutch',
  'ar': 'Arabic',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
};

const _trLanguages = {
  'en': 'İngilizce',
  'tr': 'Türkçe',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'es': 'İspanyolca',
  'it': 'İtalyanca',
  'pt': 'Portekizce',
  'ru': 'Rusça',
  'pl': 'Lehçe',
  'nl': 'Felemenkçe',
  'ar': 'Arapça',
  'ja': 'Japonca',
  'ko': 'Korece',
  'zh': 'Çince',
};

const _en = {
  'joinable': 'Joinable',
  'joinableCount': 'Joinable · {n}/{max}',
  'joinableHint': 'Join from AnyTogether in the launcher on your Mac.',
  'findPlayers': 'Find players',
  'tabBoard': 'Looking for group',
  'tabMine': 'Your posts',
  'tabLive': 'Live now',
  'tabPeople': 'People',
  'lfgPost': 'Post',
  'lfgNew': 'Looking for players',
  'lfgNewLead': 'Say what you want to play. People who are in tap “I\'m in”, and you choose who joins.',
  'purpose_coop': 'Co-op',
  'purpose_online': 'Online',
  'purpose_party': 'Party & voice',
  'purpose_trophies': 'Trophy help',
  'purposeHint_coop': 'You host share play, they play along with a pad.',
  'purposeHint_online': 'Play the game\'s own online together.',
  'purposeHint_party': 'Hang out in a party and talk while you play.',
  'purposeHint_trophies': 'Get a hard trophy done together.',
  'allGames': 'All games',
  'anything': 'Anything',
  'anyLanguage': 'Any language',
  'nowOnly': 'Now',
  'startsNow': 'Now',
  'startsAtTime': 'at {time}',
  'spotsLeft': '{n} of {total} spots left',
  'spotsFull': 'Full',
  'imIn': 'I\'m in',
  'takeBack': 'Take back',
  'askedState': 'Asked',
  'youreIn': 'You\'re in',
  'notThisTime': 'Not this time',
  'goToParty': 'Party',
  'yourPost': 'Your post',
  'noPosts': 'Nobody is looking right now. Post what you want to play and people will find you.',
  'noPostsFiltered':
      'Nothing matches. Try another game or language, or post your own.',
  'yourPosts': 'Your posts',
  'yourRequests': 'You asked to join',
  'noPostsOfMine':
      'You have no posts. Post one and people who are in show up here.',
  'wantsIn': 'Wants in',
  'noRequestsYet': 'Nobody yet. You will hear it here and under the bell.',
  'letIn': 'Let in',
  'requestIn': 'In',
  'requestNo': 'Declined',
  'closePost': 'Close post',
  'status_open': 'Open',
  'status_full': 'Full',
  'status_closed': 'Closed',
  'status_expired': 'Ended',
  'status_removed': 'Removed',
  'invitedToParty': 'Invited to your party',
  'invitedToShare': 'Invited to your share play',
  'lfgPickGame': 'Pick a game',
  'otherGame': 'Another game…',
  'titleIdHint': 'Title ID, like PPSA01234',
  'whatFor': 'What for',
  'when': 'When',
  'inMinutes': 'In {n} min',
  'inHours': 'In {n} h',
  'languagesUpTo': 'Languages (up to 3)',
  'playersWanted': 'Players wanted',
  'note': 'Note',
  'notePlaceholder': 'Mics on, chill, English or Turkish… (no links)',
  'endsAfter': 'Ends after',
  'hoursN': '{n} h',
  'postIt': 'Post it',
  'tooManyOpen': 'You have 3 open posts. Close one first.',
  'postClosed': 'That post just closed.',
  'draft_game': 'A title ID is four capitals and five digits: PPSA01234.',
  'draft_languages': 'Pick one to three languages.',
  'draft_slots': 'Co-op has room for 3 more players, the rest for 7.',
  'draft_note': 'The note is at most 140 characters.',
  'liveNow': 'Live now',
  'liveLead': 'Share plays their hosts opened to everyone. Pull up a seat.',
  'liveFlair': 'LIVE',
  'publicParties': 'Public parties',
  'noLive': 'Nobody is live right now.',
  'noPublicParties':
      'No public parties right now. Make yours public on the party page.',
  'askToJoin': 'Ask to join',
  'watching': '{n}/{max} watching',
  'partyCount': '{n}/{max} in the party',
  'joinOpenFlair': 'Open',
  'joinRequestFlair': 'Ask first',
  'hostedBy': 'with {name}',
  'noGameListed': 'Any game',
  'inThisParty': 'You\'re in it',
  'full': 'Full',
  'partyPublic': 'List in public',
  'partyPublicHint': 'People find it under Find players. Anyone you blocked, or who blocked you, never sees it.',
  'publicOff': 'Off',
  'joinModeRequest': 'Anyone can ask',
  'joinModeOpen': 'Anyone can join',
  'listLanguage': 'Language',
  'noLanguage': 'Any',
  'askingToJoin': 'Asking to join',
  'peopleLead': 'People you may know, and who plays your games. Only those who show themselves here appear.',
  'suggestions': 'People you may know',
  'noSuggestions': 'No suggestions yet. Add friends, set the languages you play in, or make your games public to meet people who play them.',
  'reasonFriends': '{n} friends in common',
  'reasonFriend': '1 friend in common',
  'reasonGame': 'You both play {game}',
  'reasonLanguage': 'Speaks {language}',
  'requested': 'Requested',
  'sectionDiscovery': 'Discovery',
  'discoveryLead': 'Whether people who are not your friends find you in suggestions and game hubs. People you blocked never do.',
  'showInDiscovery': 'Show me in discovery',
  'discoveryFollow': 'Like my games',
  'discoveryOn': 'On',
  'discoveryOff': 'Off',
  'discoveryShown': 'Others can find you now.',
  'discoveryHidden': 'You are hidden from discovery now.',
  'languagesYouPlay': 'Languages you play in',
  'languagesHint':
      'For “speaks your language” and as your default on the board. Up to 5.',
};

const _tr = {
  'joinable': 'Katılınabilir',
  'joinableCount': 'Katılınabilir · {n}/{max}',
  'joinableHint': "Mac'teki launcher'da AnyTogether'dan katıl.",
  'findPlayers': 'Oyuncu bul',
  'tabBoard': 'Grup arayanlar',
  'tabMine': 'İlanların',
  'tabLive': 'Şu an canlı',
  'tabPeople': 'Kişiler',
  'lfgPost': 'İlan ver',
  'lfgNew': 'Oyuncu arıyorum',
  'lfgNewLead': 'Ne oynamak istediğini yaz. İsteyenler “Ben varım” der, kimin katılacağını sen seçersin.',
  'purpose_coop': 'Co-op',
  'purpose_online': 'Online',
  'purpose_party': 'Parti ve ses',
  'purpose_trophies': 'Kupa yardımı',
  'purposeHint_coop': 'Sen share play açarsın, onlar kendi kollarıyla katılır.',
  'purposeHint_online': 'Oyunun kendi online modunda birlikte oynayın.',
  'purposeHint_party': 'Oynarken partide takılıp konuşun.',
  'purposeHint_trophies': 'Zor bir kupayı birlikte alın.',
  'allGames': 'Tüm oyunlar',
  'anything': 'Hepsi',
  'anyLanguage': 'Her dil',
  'nowOnly': 'Şimdi',
  'startsNow': 'Şimdi',
  'startsAtTime': '{time}',
  'spotsLeft': '{total} kişilik yerden {n} boş',
  'spotsFull': 'Dolu',
  'imIn': 'Ben varım',
  'takeBack': 'Geri al',
  'askedState': 'İstendi',
  'youreIn': 'Kabul edildin',
  'notThisTime': 'Bu sefer olmadı',
  'goToParty': 'Parti',
  'yourPost': 'Senin ilanın',
  'noPosts': 'Şu an kimse aramıyor. Ne oynamak istediğini ilan et, insanlar seni bulsun.',
  'noPostsFiltered':
      'Eşleşen yok. Başka bir oyun ya da dil dene, ya da kendi ilanını ver.',
  'yourPosts': 'İlanların',
  'yourRequests': 'Katılmak istediklerin',
  'noPostsOfMine':
      'İlanın yok. Bir ilan ver, katılmak isteyenler burada görünür.',
  'wantsIn': 'Katılmak istiyor',
  'noRequestsYet': 'Henüz kimse yok. Geldiğinde burada ve zilde görürsün.',
  'letIn': 'Kabul et',
  'requestIn': 'Katıldı',
  'requestNo': 'Reddedildi',
  'closePost': 'İlanı kapat',
  'status_open': 'Açık',
  'status_full': 'Dolu',
  'status_closed': 'Kapandı',
  'status_expired': 'Bitti',
  'status_removed': 'Kaldırıldı',
  'invitedToParty': 'Partine çağrıldı',
  'invitedToShare': "Share play'ine çağrıldı",
  'lfgPickGame': 'Bir oyun seç',
  'otherGame': 'Başka bir oyun…',
  'titleIdHint': 'Title ID, örneğin PPSA01234',
  'whatFor': 'Ne için',
  'when': 'Ne zaman',
  'inMinutes': '{n} dk sonra',
  'inHours': '{n} sa sonra',
  'languagesUpTo': 'Diller (en fazla 3)',
  'playersWanted': 'Aranan oyuncu',
  'note': 'Not',
  'notePlaceholder':
      'Mikrofon açık, sakin, Türkçe ya da İngilizce… (bağlantı yok)',
  'endsAfter': 'Bitiş',
  'hoursN': '{n} sa',
  'postIt': 'İlanı ver',
  'tooManyOpen': '3 açık ilanın var. Önce birini kapat.',
  'postClosed': 'Bu ilan az önce kapandı.',
  'draft_game': 'Title ID dört büyük harf ve beş rakamdır: PPSA01234.',
  'draft_languages': 'Bir ile üç arası dil seç.',
  'draft_slots': 'Co-op en fazla 3, diğerleri 7 oyuncu arar.',
  'draft_note': 'Not en fazla 140 karakter.',
  'liveNow': 'Şu an canlı',
  'liveLead': "Sahiplerinin herkese açtığı share play'ler. Bir yer kap.",
  'liveFlair': 'CANLI',
  'publicParties': 'Herkese açık partiler',
  'noLive': 'Şu an kimse canlı değil.',
  'noPublicParties':
      'Şu an herkese açık parti yok. Seninkini parti sayfasından herkese aç.',
  'askToJoin': 'Katılmak iste',
  'watching': '{n}/{max} izliyor',
  'partyCount': 'partide {n}/{max}',
  'joinOpenFlair': 'Açık',
  'joinRequestFlair': 'Önce sor',
  'hostedBy': '{name} ile',
  'noGameListed': 'Herhangi bir oyun',
  'inThisParty': 'Bu partidesin',
  'full': 'Dolu',
  'partyPublic': 'Herkese aç',
  'partyPublicHint': "İnsanlar Oyuncu bul'da görür. Engellediğin ya da seni engelleyen kimse görmez.",
  'publicOff': 'Kapalı',
  'joinModeRequest': 'Herkes sorabilir',
  'joinModeOpen': 'Herkes katılabilir',
  'listLanguage': 'Dil',
  'noLanguage': 'Fark etmez',
  'askingToJoin': 'Katılmak isteyenler',
  'peopleLead': 'Tanıyor olabileceğin kişiler ve oyunlarını oynayanlar. Sadece kendini burada gösterenler çıkar.',
  'suggestions': 'Tanıyor olabileceğin kişiler',
  'noSuggestions': 'Henüz öneri yok. Arkadaş ekle, oynadığın dilleri seç ya da oyunlarını herkese aç ki onları oynayanlarla tanış.',
  'reasonFriends': '{n} ortak arkadaş',
  'reasonFriend': '1 ortak arkadaş',
  'reasonGame': 'İkiniz de {game} oynuyorsunuz',
  'reasonLanguage': '{language} konuşuyor',
  'requested': 'İstek gitti',
  'sectionDiscovery': 'Keşif',
  'discoveryLead': 'Arkadaşın olmayanların seni önerilerde ve oyun sayfalarında bulup bulamayacağı. Engellediklerin asla bulamaz.',
  'showInDiscovery': 'Beni keşifte göster',
  'discoveryFollow': 'Oyunlarım gibi',
  'discoveryOn': 'Açık',
  'discoveryOff': 'Kapalı',
  'discoveryShown': 'Şu an başkaları seni bulabilir.',
  'discoveryHidden': 'Şu an keşifte gizlisin.',
  'languagesYouPlay': 'Oynadığın diller',
  'languagesHint': '“Senin dilini konuşuyor” önerileri ve ilanlarda varsayılan için. En fazla 5.',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesDiscover() => {'en': _en, 'tr': _tr};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldLanguages() => {
  'en': _enLanguages,
  'tr': _trLanguages,
};
