import 'strings.dart';
import 'together/activity.dart';
import 'together/calls.dart';
import 'together/leaderboards.dart';
import 'together/notifications.dart';
import 'together/profiles.dart';

/// AnyTogether's social texts (profiles, the feed, leaderboards, calls), beside [Strings], their
/// texts in assets/l10n. The wording follows the website's.
extension SocialTexts on Strings {
  // Profiles

  String get profile => lookup('profile');
  String get myProfile => lookup('myProfile');
  String get editProfile => lookup('editProfile');
  String get noBio => lookup('noBio');
  String get statGames => lookup('profileGames');
  String get statPlayed => lookup('statPlayed');
  String get statTrophies => lookup('profileTrophies');
  String get statPoints => lookup('statPoints');
  String get statPlatinums => lookup('statPlatinums');
  String get library => lookup('library');
  String get recentTrophies => lookup('recentTrophies');
  String get recentActivity => lookup('recentActivity');
  String get noGamesYet => lookup('noGamesYet');
  String get noTrophiesYet => lookup('noTrophiesYet');
  String get noActivity => lookup('noActivity');
  String get hiddenTrophy => lookup('hiddenTrophy');
  String privateSection(String name) => fill('privateSection', [name]);
  String trophiesOf(int earned, int total) =>
      fill('trophiesOf', [earned, total]);
  String ofPlayers(double rarity) => fill('ofPlayers', [rarityPercent(rarity)]);
  String lastPlayed(DateTime when) => fill('lastPlayed', [daysAgo(when)]);
  String grade(Grade grade) => lookup('grade_${grade.name}');
  String rarity(Rarity rarity) => lookup('rarity_${rarity.name}');
  String get areFriends => lookup('areFriends');
  String get requestPending => lookup('requestPending');
  String get addFriend => lookup('addFriend');
  String wantsToBeFriends(String name) => fill('wantsToBeFriends', [name]);
  String get thisIsYou => lookup('thisIsYou');
  String get profileFailed => lookup('profileFailed');
  String get friendsList => lookup('friendsList');

  // Editing

  String get displayName => lookup('displayName');
  String get handle => lookup('togetherHandle');
  String get handleHint => lookup('handleHint');
  String handleNextChange(DateTime date) =>
      fill('handleNextChange', [day(date)]);
  String handleIssue(HandleIssue issue) => lookup('handle_${issue.name}');
  String get bio => lookup('bio');
  String get bioPlaceholder => lookup('bioPlaceholder');
  String get country => lookup('togetherCountry');
  String get noCountry => lookup('noCountry');
  String get searchCountry => lookup('searchCountry');
  String get save => lookup('save');
  String get saved => lookup('saved');
  String get privacy => lookup('privacy');
  String get privacyLead => lookup('privacyLead');
  String privacySection(PrivacySection section) =>
      lookup('privacy_${section.name}');
  String audience(Audience audience, {bool search = false}) =>
      search && audience == Audience.nobody
      ? lookup('vis_nobody_search')
      : lookup('vis_${audience.name}');
  String get searchHint => lookup('searchHint');
  String get presenceMode => lookup('presenceMode');
  String get presenceOnline => lookup('presenceOnline');
  String get presenceAppearOffline => lookup('presenceAppearOffline');
  String get presenceModeHint => lookup('presenceHint');
  String get appearingOffline => lookup('presenceAppearing');
  String get presenceUnavailable => lookup('presenceUnavailable');
  String trophyLevel(int level) => fill('trophyLevel', [level]);
  String levelProgress(int progress, int next) =>
      fill('levelProgress', [progress, next]);
  String get levelTop => lookup('levelTop');
  String get avatar => lookup('avatar');
  String get changeAvatar => lookup('changeAvatar');
  String get removeAvatar => lookup('removeAvatar');
  String get avatarHint => lookup('avatarHint');
  String get cropHint => lookup('cropHint');
  String get zoom => lookup('cropZoom');
  String get useAvatar => lookup('useAvatar');
  String get avatarTooBig => lookup('avatarTooBig');
  String get avatarWrongType => lookup('avatarWrongType');
  String get avatarBad => lookup('avatarBad');
  String get photoDenied => lookup('photoDenied');

  /// What went wrong saving a profile, in words, for the codes the API uses.
  String? profileProblem(String code, Map<String, dynamic>? extra) =>
      switch (code) {
        'handle_taken' => lookup('handleTaken'),
        'handle_reserved' => lookup('handleReserved'),
        'handle_cooldown' => switch (DateTime.tryParse(
          '${extra?['handleChangeAt']}',
        )) {
          final at? => handleNextChange(at),
          null => lookup('handleCooldown'),
        },
        'links_not_allowed' => lookup('noLinks'),
        'payload_too_large' => avatarTooBig,
        'unsupported_media_type' => avatarWrongType,
        'bad_image' => avatarBad,
        'rate_limited' => lookup('rateLimited'),
        _ => null,
      };

  // The feed

  String get feed => lookup('feed');
  String get feedLead => lookup('feedLead');
  String get feedEmpty => lookup('feedEmpty');
  String get feedEmptyNoFriends => lookup('feedEmptyNoFriends');
  String get loadMore => lookup('loadMore');
  String get rare => lookup('rare');
  String get platinumTag => lookup('gradePlatinum');
  String get milestoneTag => lookup('milestoneTag');
  String andMore(int n) => fill('andMore', [n]);
  String reactionName(Reaction reaction) => lookup('react_${reaction.name}');

  /// What an item says, with {name}, {game}, {trophy} and {friend} left for the caller to set
  /// apart (bold names), and the rest filled in.
  String activityLine(Activity item) => switch (item.kind) {
    ActivityKind.trophy when item.trophyCount > 1 => fill('act_trophy_many', [
      '{name}',
      item.trophyCount,
      '{game}',
    ]),
    ActivityKind.trophy => fill('act_trophy_one', [
      '{name}',
      '{trophy}',
      '{game}',
    ]),
    ActivityKind.platinum => fill('act_platinum', ['{name}', '{game}']),
    ActivityKind.firstPlay => fill('act_first_play', ['{name}', '{game}']),
    ActivityKind.longSession => fill('act_long_session', [
      '{name}',
      '{game}',
      playTime(item.seconds ?? 0),
    ]),
    ActivityKind.friendship => fill('act_friendship', ['{name}', '{friend}']),
    ActivityKind.milestone => fill(
      'act_milestone_${item.milestoneKind ?? 'trophies'}',
      ['{name}', number(item.milestoneValue ?? 0)],
    ),
  };

  /// "3 min ago", "2 h ago", then [daysAgo].
  String ago(DateTime when, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(when);
    if (elapsed.inMinutes < 1) return lookup('justNow');
    if (elapsed.inMinutes < 60) {
      return fill('minutesAgo', [elapsed.inMinutes]);
    }
    if (elapsed.inHours < 24) return fill('hoursAgo', [elapsed.inHours]);
    return daysAgo(when, now: now);
  }

  // Leaderboards

  String get leaderboards => lookup('leaderboards');
  String get boardsLead => lookup('boardsLead');
  String get overall => lookup('discoverAllGames');
  String get yourGames => lookup('yourGames');
  String get mostPlayed => lookup('mostPlayed');
  String scope(BoardScope scope) => lookup('scope_${scope.name}');
  String boardKind(BoardKind kind) => lookup('board_${kind.name}');
  String get yourRank => lookup('socialBoardYourRank');
  String rankOf(int rank, int total) => fill('rankOf', [rank, number(total)]);
  String get notRanked => lookup('notRanked');
  String wouldBe(int rank, {required bool library}) =>
      fill(library ? 'wouldBeLibrary' : 'wouldBe', [rank]);
  String get nothingToRank => lookup('nothingToRank');
  String boardEmpty(BoardScope scope) =>
      lookup(scope == BoardScope.global ? 'boardEmptyGlobal' : 'boardEmpty');
  String playersCount(int n) => fill('playersCount', [number(n)]);
  String get boardFailed => lookup('boardFailed');

  /// A board's value as it reads: "1,230 pts", "12 h", "85%".
  String boardValue(BoardKind kind, int value) => switch (kind) {
    BoardKind.points => fill('pointsValue', [number(value)]),
    BoardKind.time => totalTime(value),
    BoardKind.completion => percent(value),
  };

  // Calls

  String callFriend(String name) => fill('callFriend', [name]);
  String get voiceCall => lookup('voiceCall');
  String callingYou(String name) => fill('callingYou', [name]);
  String get acceptCall => lookup('acceptCall');
  String get declineCall => lookup('declineCall');
  String get calling => lookup('calling');
  String get callConnecting => lookup('callConnecting');
  String get endCall => lookup('endCall');
  String peerMuted(String name) => fill('peerMuted', [name]);
  String callEnded(CallEnd reason, String name) => switch (reason) {
    CallEnd.declined => fill('callDeclined', [name]),
    CallEnd.noAnswer => lookup('callNoAnswer'),
    CallEnd.elsewhere => lookup('callElsewhere'),
    CallEnd.failed => lookup('callFailed'),
    CallEnd.microphone => lookup('callMicDenied'),
    CallEnd.ended => lookup('callEnded'),
  };

  /// "0:42", "12:05", "1:02:09".
  String clock(Duration elapsed) {
    final total = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  // Messages

  String typing(List<String> names) => switch (names.length) {
    0 => '',
    1 => fill('typingOne', [names[0]]),
    2 => fill('typingTwo', [names[0], names[1]]),
    _ => lookup('typingMany'),
  };
  String get newGroup => lookup('messagesNewGroup');
  String get groupName => lookup('groupName');
  String get groupPick => lookup('groupPick');
  String groupPicked(int n, int max) => fill('groupPicked', [n, max]);
  String groupFull(int max) => fill('groupFull', [max]);
  String get startGroup => lookup('startGroup');
  String get noFriendsToMessage => lookup('noFriendsToMessage');
  String linkBlocked(String? domain) => domain == null
      ? lookup('linkBlocked')
      : fill('linkBlockedDomain', [domain]);
  String get cannotMessage => lookup('cannotMessage');

  // Notifications

  String get notifications => lookup('socialNotifTitle');
  String get notificationsLead => lookup('notificationsLead');
  String get markAllRead => lookup('markAllRead');
  String get noNotifications => lookup('noNotifications');
  String get notifySettings => lookup('notifySettings');
  String get notifySettingsLead => lookup('notifySettingsLead');
  String noticeKind(NoticeKind kind) => lookup('nk_${kind.wire}');
  String get digest => lookup('digest');
  String get digestHint => lookup('digestHint');
  String get digestNoEmail => lookup('digestNoEmail');
  String get gameInviteHint => lookup('n_game_invite_hint');
  String get noPushYet => lookup('noPushYet');

  /// What a notification says, with {name} left for the caller to set in bold.
  String notice(Notice n, {String? Function(String titleId)? gameName}) {
    final group = n.data['group'] == true;
    final count = n.count;
    final title = '${n.data['title'] ?? ''}';
    final key = switch (n.kind) {
      NoticeKind.message when group =>
        count > 1 ? 'n_messages_group' : 'n_message_group',
      NoticeKind.message => count > 1 ? 'n_messages' : 'n_message',
      _ => 'n_${n.kind.wire}',
    };
    final lfgKey = switch (n.kind) {
      NoticeKind.lfgRequest when count > 1 => 'n_lfg_requests',
      _ => key,
    };
    final titleId = '${n.data['titleId'] ?? ''}';
    return fill(lfgKey, [
      '{name}',
      count,
      count - 1,
      title,
      gameName?.call(titleId) ??
          localName(namesFrom(n.data['gameNames']), language) ??
          titleId,
    ]);
  }

  /// Under a poster's yes: where the invite is.
  String lfgAcceptedHint(Notice n) {
    final invite = n.data['invite'];
    return lookup(
      invite is Map && invite['kind'] == 'share_play'
          ? 'n_lfg_accepted_share'
          : 'n_lfg_accepted_party',
    );
  }

  String get someone => lookup('n_someone');
  String warningReason(String reason) => fill('n_warning_reason', [reason]);

  // Times and numbers

  /// "42 min", "3 h 5 min".
  String playTime(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return fill('minutes', [minutes]);
    return fill('hours', [minutes ~/ 60, minutes % 60]);
  }

  /// Hours only, for the totals: "128 h", or minutes under an hour.
  String totalTime(int seconds) {
    final minutes = seconds ~/ 60;
    return minutes < 60
        ? fill('minutes', [minutes])
        : fill('hoursOnly', [minutes ~/ 60]);
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
    if (days <= 0) return lookup('today');
    if (days == 1) return lookup('yesterday');
    if (days < 30) return fill('daysAgo', [days]);
    return day(local);
  }

  /// "24.10.2026".
  String day(DateTime when) {
    final local = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  /// "1.2 %" of players: one decimal under 10 %.
  String rarityPercent(double rarity) {
    final percent = rarity * 100;
    return fill('percent', [
      percent < 10 ? decimal(percent, 1) : percent.round(),
    ]);
  }
}
