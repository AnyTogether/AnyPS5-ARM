import 'l10n.dart';
import 'strings.dart';
import 'together/discover.dart';

/// AnyTogether's texts for meeting people beyond one's friends (a friend's joinable game, the
/// looking-for-group board, public parties and share plays, discovery), beside [Strings], their
/// texts in assets/l10n the way the social texts are. The wording follows the website's.
extension DiscoverTexts on Strings {
  // A friend's game

  String get joinable => lookup('joinable');
  String joinableCount(int players, int capacity) =>
      fill('joinableCount', [players, capacity]);
  String get joinableHint => lookup('joinableHint');

  // Find players

  String get findPlayers => lookup('discoverFindPlayers');
  String get tabBoard => lookup('discoverBoard');
  String get tabMine => lookup('tabMine');
  String get tabLive => lookup('tabLive');
  String get tabPeople => lookup('discoverPeople');

  // The board

  String get lfgPost => lookup('discoverPost');
  String get lfgNew => lookup('lfgNew');
  String get lfgNewLead => lookup('lfgNewLead');
  String purpose(LfgPurpose purpose) => lookup('purpose_${purpose.name}');
  String purposeHint(LfgPurpose purpose) =>
      lookup('purposeHint_${purpose.name}');
  String get allGames => lookup('allGames');
  String get anything => lookup('anything');
  String get anyLanguage => lookup('discoverAnyLanguage');
  String get nowOnly => lookup('discoverNow');
  String get startsNow => lookup('startsNow');
  String startsAt(DateTime when) {
    final local = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return fill('startsAtTime', ['${two(local.hour)}:${two(local.minute)}']);
  }

  String spotsLeft(int left, int total) => fill('spotsLeft', [left, total]);
  String get spotsFull => lookup('spotsFull');
  String get imIn => lookup('imIn');
  String get takeBack => lookup('takeBack');
  String get askedState => lookup('askedState');
  String get youreIn => lookup('youreIn');
  String get notThisTime => lookup('discoverNotThisTime');
  String get goToParty => lookup('goToParty');
  String get yourPost => lookup('yourPost');
  String get noPosts => lookup('noPosts');
  String get noPostsFiltered => lookup('noPostsFiltered');
  String get yourPosts => lookup('yourPosts');
  String get yourRequests => lookup('yourRequests');
  String get noPostsOfMine => lookup('noPostsOfMine');
  String get wantsIn => lookup('wantsIn');
  String get noRequestsYet => lookup('noRequestsYet');
  String get letIn => lookup('letIn');
  String get requestIn => lookup('requestIn');
  String get requestNo => lookup('requestNo');
  String get closePost => lookup('closePost');
  String lfgStatus(LfgStatus status) => lookup('status_${status.name}');
  String get invitedToParty => lookup('invitedToParty');
  String get invitedToShare => lookup('invitedToShare');

  // A new post

  String get lfgPickGame => lookup('lfgPickGame');
  String get otherGame => lookup('otherGame');
  String get titleIdHint => lookup('titleIdHint');
  String get whatFor => lookup('whatFor');
  String get when => lookup('when');
  String inMinutes(int minutes) => minutes < 60
      ? fill('inMinutes', [minutes])
      : fill('inHours', [minutes ~/ 60]);
  String get languagesUpTo => lookup('languagesUpTo');
  String get playersWanted => lookup('discoverSlots');
  String get note => lookup('discoverNote');
  String get notePlaceholder => lookup('notePlaceholder');
  String get endsAfter => lookup('endsAfter');
  String hoursN(int n) => fill('hoursN', [n]);
  String get postIt => lookup('postIt');
  String get tooManyOpen => lookup('tooManyOpen');
  String get postClosed => lookup('postClosed');
  String draftIssue(LfgDraftIssue issue) => lookup('draft_${issue.name}');

  // Live now

  String get liveNow => lookup('liveNow');
  String get liveLead => lookup('liveLead');
  String get liveFlair => lookup('liveFlair');
  String get publicParties => lookup('discoverPublicParties');
  String get noLive => lookup('noLive');
  String get noPublicParties => lookup('noPublicParties');
  String get askToJoin => lookup('partyCodeAsk');
  String watching(int n, int max) => fill('watching', [n, max]);
  String partyCount(int n, int max) => fill('partyCount', [n, max]);
  String get joinOpenFlair => lookup('joinOpenFlair');
  String get joinRequestFlair => lookup('joinRequestFlair');
  String hostedBy(String name) => fill('hostedBy', [name]);
  String get noGameListed => lookup('noGameListed');
  String get inThisParty => lookup('inThisParty');
  String get full => lookup('full');

  // The party

  String get partyPublic => lookup('partyPublic');
  String get partyPublicHint => lookup('partyPublicHint');
  String get publicOff => lookup('publicOff');
  String get joinModeRequest => lookup('joinModeRequest');
  String get joinModeOpen => lookup('discoverListOpen');
  String get listLanguage => lookup('listLanguage');
  String get noLanguage => lookup('noLanguage');
  String get askingToJoin => lookup('askingToJoin');

  // People

  String get peopleLead => lookup('peopleLead');
  String get suggestions => lookup('suggestions');
  String get noSuggestions => lookup('noSuggestions');
  String reasonFriends(int n) =>
      n == 1 ? lookup('reasonFriend') : fill('reasonFriends', [n]);
  String reasonGame(String game) => fill('reasonGame', [game]);
  String reasonLanguage(String code) =>
      fill('reasonLanguage', [languageName(code)]);
  String get requested => lookup('requested');
  String get sectionDiscovery => lookup('discoveryTitle');
  String get discoveryLead => lookup('discoveryLead');
  String get showInDiscovery => lookup('discoverShowMe');
  String get discoveryFollow => lookup('discoveryFollow');
  String get discoveryOn => lookup('discoveryOn');
  String get discoveryOff => lookup('discoveryOff');
  String get discoveryShown => lookup('discoveryShown');
  String get discoveryHidden => lookup('discoveryHidden');
  String get languagesYouPlay => lookup('languagesYouPlay');
  String get languagesHint => lookup('languagesHint');

  /// A language's name in the app's language; its code for one the app does not name.
  String languageName(String code) =>
      L10n.textOrNull(language, 'spokenLanguage_$code') ?? code.toUpperCase();
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
