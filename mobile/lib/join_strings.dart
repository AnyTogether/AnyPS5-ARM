import 'strings.dart';
import 'together/join_codes.dart';
import 'together/together_account.dart';

/// Join codes, a party's Discord link, deafening and testing the vibration, beside [Strings], their
/// texts in assets/l10n. The wording follows the Mac launcher's.
extension JoinTexts on Strings {
  String get codeTitle => lookup('joinCodeTitle');
  String codeDetail(DateTime until, {DateTime? now}) =>
      fill('joinCodeDetail', [endsAt(until, now: now)]);
  String get copyCode => lookup('partyCodeCopy');
  String get copyLink => lookup('partyCodeCopyLink');
  String get codeCopied => lookup('partyCodeCopied');
  String get linkCopied => lookup('partyLinkCopied');
  String get newCode => lookup('partyCodeNew');
  String get stopCode => lookup('joinStopCode');
  String get codeStopped => lookup('joinCodeStopped');
  String get makeCode => lookup('partyCodeMake');
  String get makeCodeDetail => lookup('joinMakeCodeDetail');
  String codeMade(String code) => fill('joinCodeMade', [code]);
  String get joinWithCode => lookup('partyCodeEnter');
  String get joinWithCodeDetail => lookup('joinWithCodeDetail');
  String get lookUp => lookup('lookUp');
  String codeParty(String host) => fill('partyCodeOf', [host]);
  String codeShare(String host) => fill('joinCodeShare', [host]);
  String get codeGame => lookup('codeGame');
  String get askedParty => lookup('joinAskedParty');
  String get askedShare => lookup('joinAskedShare');
  String get invitedParty => lookup('invitedParty');
  String get invitedShare => lookup('joinInvitedShare');
  String get alreadyIn => lookup('joinAlreadyIn');
  String get noSuchCode => lookup('joinNoSuchCode');
  String get notACode => lookup('joinNotACode');
  String get tooMany => lookup('joinTooMany');
  String people(int size, int max) => fill('people', [size, max]);
  String get deafen => lookup('joinDeafen');
  String get undeafen => lookup('undeafen');
  String get deafenDetail => lookup('joinDeafenDetail');
  String get deafened => lookup('joinDeafened');
  String get discordLink => lookup('partyDiscord');
  String get discordLinkDetail => lookup('joinDiscordLinkDetail');
  String get discordLinkSaved => lookup('partyDiscordSaved');
  String get discordLinkRemoved => lookup('partyDiscordRemoved');
  String get discordLinkBad => lookup('joinDiscordLinkBad');
  String get openDiscord => lookup('partyDiscordOpen');
  String get remove => lookup('remove');
  String get vibrationTest => lookup('vibrationTest');

  /// What asking with a code came to, for the line under the card.
  String asked(JoinKind kind, JoinState state) => switch ((kind, state)) {
    (_, JoinState.member) => alreadyIn,
    (JoinKind.sharePlay, JoinState.invited) => invitedShare,
    (_, JoinState.invited) => invitedParty,
    (JoinKind.sharePlay, _) => askedShare,
    _ => askedParty,
  };

  /// Why a code did not open or could not be used.
  String codeFailure(Object error) => switch (error) {
    TogetherProblem(code: 'not_found') => noSuchCode,
    TogetherProblem(code: 'rate_limited') => tooMany,
    TogetherProblem(:final title) when title.isNotEmpty => title,
    _ => togetherUnreachable,
  };

  /// "14:05", or "26 Oct 14:05" when it is not today.
  String endsAt(DateTime when, {DateTime? now}) {
    final today = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(when.hour)}:${two(when.minute)}';
    if (when.year == today.year &&
        when.month == today.month &&
        when.day == today.day) {
      return time;
    }
    return '${when.day} ${lookup('monthShort${when.month}')} $time';
  }
}
