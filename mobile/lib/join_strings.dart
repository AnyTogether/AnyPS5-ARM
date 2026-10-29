import 'package:flutter/foundation.dart';

import 'strings.dart';
import 'together/join_codes.dart';
import 'together/together_account.dart';

/// Join codes, a party's Discord link, deafening and testing the vibration, in English and
/// Turkish, beside [Strings]. The wording follows the Mac launcher's.
extension JoinTexts on Strings {
  String _j(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String get codeTitle => _j('codeTitle');
  String codeDetail(DateTime until, {DateTime? now}) =>
      _j('codeDetail').replaceAll('%@', endsAt(until, now: now));
  String get copyCode => _j('copyCode');
  String get copyLink => _j('copyLink');
  String get codeCopied => _j('codeCopied');
  String get linkCopied => _j('linkCopied');
  String get newCode => _j('newCode');
  String get stopCode => _j('stopCode');
  String get codeStopped => _j('codeStopped');
  String get makeCode => _j('makeCode');
  String get makeCodeDetail => _j('makeCodeDetail');
  String codeMade(String code) => _j('codeMade').replaceAll('%@', code);
  String get joinWithCode => _j('joinWithCode');
  String get joinWithCodeDetail => _j('joinWithCodeDetail');
  String get lookUp => _j('lookUp');
  String codeParty(String host) => _j('codeParty').replaceAll('%@', host);
  String codeShare(String host) => _j('codeShare').replaceAll('%@', host);
  String get codeGame => _j('codeGame');
  String get askedParty => _j('askedParty');
  String get askedShare => _j('askedShare');
  String get invitedParty => _j('invitedParty');
  String get invitedShare => _j('invitedShare');
  String get alreadyIn => _j('alreadyIn');
  String get noSuchCode => _j('noSuchCode');
  String get notACode => _j('notACode');
  String get tooMany => _j('tooMany');
  String people(int size, int max) =>
      _j('people').replaceAll('{n}', '$size').replaceAll('{m}', '$max');
  String get deafen => _j('deafen');
  String get undeafen => _j('undeafen');
  String get deafenDetail => _j('deafenDetail');
  String get deafened => _j('deafened');
  String get discordLink => _j('discordLink');
  String get discordLinkDetail => _j('discordLinkDetail');
  String get discordLinkSaved => _j('discordLinkSaved');
  String get discordLinkRemoved => _j('discordLinkRemoved');
  String get discordLinkBad => _j('discordLinkBad');
  String get openDiscord => _j('openDiscord');
  String get remove => _j('remove');
  String get vibrationTest => _j('vibrationTest');

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
    final months = language == 'tr' ? _trMonths : _enMonths;
    return '${when.day} ${months[when.month - 1]} $time';
  }
}

const _enMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _trMonths = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

const _en = {
  'codeTitle': 'Join code',
  'codeDetail': 'Anyone with it can ask to join · ends %@',
  'copyCode': 'Copy code',
  'copyLink': 'Copy link',
  'codeCopied': 'Code copied',
  'linkCopied': 'Link copied',
  'newCode': 'New code',
  'stopCode': 'Stop code',
  'codeStopped': 'The code no longer works',
  'makeCode': 'Make a join code',
  'codeMade': 'New code: %@',
  'makeCodeDetail': 'Share it or its link; you still say yes to each one',
  'joinWithCode': 'Join with a code',
  'joinWithCodeDetail': 'Type or paste a code or its link',
  'lookUp': 'Look up',
  'codeParty': "%@'s party",
  'codeShare': '%@ is sharing',
  'codeGame': 'Play Together: join it from the launcher',
  'askedParty': "Asked. You'll hear when the leader answers",
  'askedShare': "Asked. You'll hear when the host answers",
  'invitedParty': "You're invited: join from the invite above",
  'invitedShare': "You're invited: watch from the invite in Friends",
  'alreadyIn': "You're already in",
  'noSuchCode': 'No such code, or it no longer works',
  'notACode': 'A code is 8 letters and numbers',
  'tooMany': 'Too many requests. Try again in a while',
  'people': '{n} of {m}',
  'deafen': 'Deafen',
  'undeafen': 'Undeafen',
  'deafenDetail': 'Hear nobody, and your microphone is off',
  'deafened': 'deafened',
  'discordLink': 'Discord link',
  'discordLinkDetail': 'A discord.gg invite or a channel link',
  'discordLinkSaved': 'Discord link saved',
  'discordLinkRemoved': 'Discord link removed',
  'discordLinkBad': "That's not a Discord invite or channel link",
  'openDiscord': 'Open in Discord',
  'remove': 'Remove',
  'vibrationTest': 'Test',
};

const _tr = {
  'codeTitle': 'Katılma kodu',
  'codeDetail': 'Kodu olan katılmak isteyebilir · bitiş %@',
  'copyCode': 'Kodu kopyala',
  'copyLink': 'Bağlantıyı kopyala',
  'codeCopied': 'Kod kopyalandı',
  'linkCopied': 'Bağlantı kopyalandı',
  'newCode': 'Yeni kod',
  'stopCode': 'Kodu durdur',
  'codeStopped': 'Kod artık çalışmıyor',
  'makeCode': 'Katılma kodu oluştur',
  'codeMade': 'Yeni kod: %@',
  'makeCodeDetail':
      'Kodu ya da bağlantısını paylaş; her isteğe yine sen karar verirsin',
  'joinWithCode': 'Kodla katıl',
  'joinWithCodeDetail': 'Bir kod ya da bağlantısını yaz veya yapıştır',
  'lookUp': 'Bak',
  'codeParty': '%@ partisi',
  'codeShare': '%@ paylaşıyor',
  'codeGame': 'Birlikte Oyna: başlatıcıdan katıl',
  'askedParty': 'İstendi. Lider yanıt verince haber gelir',
  'askedShare': 'İstendi. Paylaşan yanıt verince haber gelir',
  'invitedParty': 'Davet edildin: yukarıdaki davetten katıl',
  'invitedShare': "Davet edildin: Arkadaşlar'daki davetten izle",
  'alreadyIn': 'Zaten içindesin',
  'noSuchCode': 'Böyle bir kod yok ya da artık çalışmıyor',
  'notACode': 'Kod 8 harf ve rakamdan oluşur',
  'tooMany': 'Çok fazla istek. Biraz sonra yeniden dene',
  'people': '{n} / {m}',
  'deafen': 'Sağırlaştır',
  'undeafen': 'Sesi aç',
  'deafenDetail': 'Kimseyi duymazsın, mikrofonun da kapanır',
  'deafened': 'duymuyor',
  'discordLink': 'Discord bağlantısı',
  'discordLinkDetail': 'discord.gg daveti ya da kanal bağlantısı',
  'discordLinkSaved': 'Discord bağlantısı kaydedildi',
  'discordLinkRemoved': 'Discord bağlantısı kaldırıldı',
  'discordLinkBad': 'Bu bir Discord daveti ya da kanal bağlantısı değil',
  'openDiscord': "Discord'da aç",
  'remove': 'Kaldır',
  'vibrationTest': 'Dene',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesJoin() => {'en': _en, 'tr': _tr};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, List<String>> oldMonths() => {'en': _enMonths, 'tr': _trMonths};
