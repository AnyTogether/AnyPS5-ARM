import 'package:flutter/widgets.dart';

import 'l10n.dart';
import 'ui/pad_layout.dart';

/// Every text the app shows, read from the language files in assets/l10n ([L10n]): the
/// launcher's language picks one once connected; before that the last one it picked is used. A
/// language without a file is English, and a text a file does not have yet is the English one.
@immutable
class Strings {
  const Strings._(this.language);

  static const english = Strings._(L10n.english);
  static const turkish = Strings._('tr');

  /// The texts of [language], English when there is no file for it.
  static Strings of(String? language) => switch (language) {
    'tr' => turkish,
    final code? when code != L10n.english && L10n.has(code) => Strings._(code),
    _ => english,
  };

  final String language;

  /// The text of the JSON key [key] in this language.
  String lookup(String key) => L10n.text(language, key);

  /// The text of [key] with its %@ and %d filled from [arguments].
  String fill(String key, List<Object?> arguments) =>
      L10n.format(language, key, arguments);

  /// 12,345 or 12.345: the digits of [value] grouped as the language groups them.
  String number(int value) {
    final digits = value.abs().toString();
    final separator = lookup('numberGroupSeparator');
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => separator,
    );
    return value < 0 ? '-$grouped' : grouped;
  }

  /// [value] with [digits] decimals and the language's decimal mark: 1.5 or 1,5.
  String decimal(double value, int digits) => value
      .toStringAsFixed(digits)
      .replaceAll('.', lookup('numberDecimalSeparator'));

  @override
  bool operator ==(Object other) =>
      other is Strings && other.language == language;

  @override
  int get hashCode => language.hashCode;

  String get welcomeTitle => lookup('welcomeTitle');
  String get welcomeText => lookup('welcomeText');
  String get stepOpen => lookup('stepOpen');
  String get stepWifi => lookup('stepWifi');
  String get stepAllow => lookup('stepAllow');
  String get start => lookup('start');
  String found(String mac) => fill('found', [mac]);
  String get searching => lookup('searching');
  String get searchingDetail => lookup('searchingDetail');
  String get busy => lookup('busy');
  String get refused => lookup('refused');
  String get allowOnMac => lookup('allowOnMac');
  String get sameCode => lookup('sameCode');
  String get ready => lookup('ready');
  String get opening => lookup('opening');
  String get retry => lookup('retry');
  String get notFound => lookup('notFound');
  String get startFailed => lookup('startFailed');
  String get play => lookup('play');
  String get resume => lookup('resume');
  String get update => lookup('update');
  String get unlock => lookup('unlock');
  String get cancel => lookup('cancel');
  String get closeGame => lookup('closeGame');
  String get goLive => lookup('goLive');
  String get endBroadcast => lookup('endBroadcast');
  String get starting => lookup('starting');
  String get unavailable => lookup('unavailable');
  String get noGames => lookup('noGames');
  String get playing => lookup('playing');
  String get trophies => lookup('trophies');
  String get about => lookup('about');
  String get aboutText => lookup('aboutText');
  String get madeBy => lookup('madeBy');
  String get sourceCode => lookup('sourceCode');
  String get builtOn => lookup('builtOn');
  String get vibration => lookup('vibration');
  String get vibrationDetail => lookup('vibrationDetail');
  String get motion => lookup('motion');
  String get trophyEarned => lookup('trophyEarned');
  String get activityUnlocking => lookup('activity.unlocking');
  String get activityUpdating => lookup('activity.updating');
  String get activityQueued => lookup('activity.queued');
  String get activityStarting => lookup('activity.starting');
  String activityStep(String phase) => lookup('activity.$phase');
  String get activityReady => lookup('activity.ready');

  /// [text] in capitals the way the language writes them: Turkish and Azerbaijani keep the dot
  /// on İ.
  String upper(String text) => _dottedCapitalI.contains(language)
      ? text.replaceAll('i', _dottedI).toUpperCase()
      : text.toUpperCase();

  static const _dottedCapitalI = {'tr', 'az'};
  static const _dottedI = 'İ'; // not a text
  String percent(int value) => fill('percent', [value]);
  String get motionDetail => lookup('motionDetail');
  String get remotePlay => lookup('remotePlay');
  String get remotePlayDetail => lookup('remotePlayDetail');
  String get remotePlayNoPermission => lookup('remotePlayNoPermission');
  String get together => 'AnyTogether';
  String get togetherIntro => lookup('togetherIntro');
  String get togetherSignIn => lookup('togetherSignIn');
  String togetherUseMac(String mac) => fill('togetherUseMac', [mac]);
  String get togetherUseMacDetail => lookup('togetherUseMacDetail');
  String togetherWaitingMac(String mac) => fill('togetherWaitingMac', [mac]);
  String get togetherMacDeclined => lookup('togetherMacDeclined');
  String get togetherOrEmail => lookup('togetherOrEmail');
  String get togetherEmail => lookup('togetherEmail');
  String get togetherSendCode => lookup('togetherSendCode');
  String togetherCodeSent(String email) => fill('togetherCodeSent', [email]);
  String get togetherCode => lookup('togetherCode');
  String get togetherOtherEmail => lookup('togetherOtherEmail');
  String get togetherSignedIn => lookup('togetherSignedIn');
  String get togetherSignOut => lookup('togetherSignOut');
  String get togetherUnreachable => lookup('togetherUnreachable');
  String togetherMacAsks(String mac, String handle) =>
      fill('togetherMacAsks', [mac, handle]);
  String get friends => lookup('friends');
  String get friendsHandle => lookup('friendsHandle');
  String get friendsAdd => lookup('friendsAdd');
  String friendsRequested(String handle) => fill('friendsRequested', [handle]);
  String friendsAdded(String handle) => fill('friendsAdded', [handle]);
  String get friendsRequests => lookup('friendsRequests');
  String get friendsSent => lookup('friendsSent');
  String get friendsWaiting => lookup('friendsWaiting');
  String get friendsNone => lookup('friendsNone');
  String get friendsRemove => lookup('friendsRemove');
  String get accept => lookup('accept');
  String get decline => lookup('callDecline');
  String presencePlaying(String game) => fill('friendsPlaying', [game]);
  String get presenceOnline => lookup('presenceOnline');
  String get presenceAway => lookup('friendsAway');
  String get presenceOffline => lookup('presenceOffline');
  String get togetherLive => lookup('togetherLive');
  String get togetherConnecting => lookup('togetherConnecting');
  String get togetherNotFound => lookup('togetherNotFound');
  String get back => lookup('back');
  String get voice => lookup('voice');
  String get voiceJoin => lookup('voiceJoin');
  String get voiceLeave => lookup('voiceLeave');
  String get voiceMute => lookup('voiceMute');
  String get voiceUnmute => lookup('conversationUnmute');
  String get voiceMicDenied => lookup('voiceMicDenied');
  String get voiceFailed => lookup('voiceFailed');
  String get voiceAlone => lookup('voiceAlone');
  String get voicePad => lookup('voicePad');
  String voiceConnected(int n) => fill('voiceConnected', [n]);
  String voiceConnecting(int n) => fill('voiceConnecting', [n]);
  String voiceInCall(int n) => fill('voiceInCall', [n]);
  String get party => lookup('partyTitle');
  String get partyIntro => lookup('partyIntro');
  String get partyStart => lookup('partyStart');
  String get partyInvites => lookup('partyInvites');
  String get partyJoin => lookup('partyJoin');
  String get shareTitle => lookup('shareTitle');
  String get shareWatch => lookup('shareWatch');
  String get shareLeave => lookup('shareLeave');
  String get shareWatching => lookup('shareWatching');
  String get shareFull => lookup('shareFull');
  String get shareFailed => lookup('shareFailed');
  String get shareTaken => lookup('shareTaken');
  String shareInvited(String name, String game) =>
      fill('shareInvited', [name, game]);
  String shareSharing(String game) => fill('shareSharing', [game]);
  String shareViewers(int count, int most) =>
      fill('shareViewers', ['$count', '$most']);
  String sharePlayer(int number) => fill('sharePlayer', ['$number']);
  String shareConnecting(String name) => fill('shareConnecting', [name]);
  String shareEnded(String name) => fill('shareEnded', [name]);
  String shareRemoved(String name) => fill('shareRemoved', [name]);
  String get partyLeave => lookup('partyLeave');
  String get partyInvite => lookup('partyInvite');
  String get partyInvited => lookup('partyInvited');
  String get partyInviteFriends => lookup('partyInviteFriends');
  String get partyNoFriends => lookup('partyNoFriends');
  String get partyOpen => lookup('partyOpen');
  String get partyOpenDetail => lookup('partyOpenDetail');
  String get partyLeader => lookup('partyLeader');
  String get partyFriendsParties => lookup('partyFriendsParties');
  String get partyKicked => lookup('partyKicked');
  String get partyFull => lookup('partyFull');
  String get partyKick => lookup('partyKick');
  String get partyMembers => lookup('partyMembers');
  String partyInviteFrom(String name, int size) =>
      fill('partyInviteFrom', [name, size]);
  String get messages => lookup('messagesTitle');
  String get messagesNone => lookup('messagesNone');
  String get messagesPick => lookup('messagesPick');
  String get messagesWrite => lookup('messagesWrite');
  String get messagesSend => lookup('messagesSend');
  String get messagesDeleted => lookup('messagesDeleted');
  String get messagesFailed => lookup('messagesFailed');
  String get messagesEarlier => lookup('messagesEarlier');
  String get messagesYou => lookup('messagesYou');
  String get messagesEdited => lookup('messagesEdited');
  String get togetherServer => lookup('togetherServer');
  String get togetherServerChange => lookup('togetherServerChange');
  String get togetherServerUse => lookup('togetherServerUse');
  String togetherServerMac(String mac, String server) =>
      fill('togetherServerMac', [mac, server]);
  String get togetherServerDetail => lookup('togetherServerDetail');
  String get togetherServerInvalid => lookup('togetherServerInvalid');
  String get allow => lookup('allow');
  String get notNow => lookup('notNow');
  String get editLayout => lookup('editLayout');
  String get done => lookup('done');
  String get editHint => lookup('editHint');
  String get resetAll => lookup('resetAll');
  String get smaller => lookup('smaller');
  String get larger => lookup('larger');
  String get opacity => lookup('opacity');
  String get reset => lookup('reset');
  String get hide => lookup('hide');
  String behavior(ButtonBehavior behavior) =>
      lookup('behavior.${behavior.name}');
}

/// The texts in the language the launcher uses, for every screen under it.
class Texts extends InheritedWidget {
  const Texts({super.key, required this.strings, required super.child});

  final Strings strings;

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Texts>()?.strings ??
      Strings.english;

  @override
  bool updateShouldNotify(Texts old) => old.strings != strings;
}
