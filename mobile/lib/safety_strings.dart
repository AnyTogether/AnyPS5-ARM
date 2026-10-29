import 'package:flutter/foundation.dart';

import 'strings.dart';

/// The questions social steps ask before they happen, and Update Required, in English and
/// Turkish, beside [Strings]. The wording follows the website's and the Mac launcher's.
extension SafetyTexts on Strings {
  String _k(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String _fill(String key, Map<String, Object> values) {
    var text = _k(key);
    values.forEach(
      (name, value) => text = text.replaceAll('{$name}', '$value'),
    );
    return text;
  }

  String askRemoveFriend(String name) =>
      _fill('askRemoveFriend', {'name': name});
  String get askLeaveParty => _k('askLeaveParty');
  String askKick(String name) => _fill('askKick', {'name': name});
  String get askClosePost => _k('askClosePost');

  String get updateRequiredTitle => _k('updateRequiredTitle');
  String updateRequiredBody(String minimum, String? current) => current == null
      ? _fill('updateRequiredBody', {'min': minimum})
      : _fill('updateRequiredBodyVersion', {'min': minimum, 'v': current});
  String get updateRequiredUpdate => _k('updateRequiredUpdate');
  String get updateRequiredLater => _k('updateRequiredLater');
}

const _en = {
  'askRemoveFriend': 'Remove {name} from your friends? You need a new request to be friends again.',
  'askLeaveParty': 'Leave the party? Voice ends for you, and an invite-only party takes a new invite to get back in.',
  'askKick':
      'Remove {name} from the party? They need a new invite to come back.',
  'askClosePost': 'Close this post? Its requests go with it.',
  'updateRequiredTitle': 'Update required',
  'updateRequiredBody': 'AnyTogether needs AnyPS5 Remote {min} or newer. Friends, parties and messages wait for the update; the pad still works.',
  'updateRequiredBodyVersion': 'AnyTogether needs AnyPS5 Remote {min} or newer; this is {v}. Friends, parties and messages wait for the update; the pad still works.',
  'updateRequiredUpdate': 'Update',
  'updateRequiredLater': 'Later',
};

const _tr = {
  'askRemoveFriend': '{name} arkadaşlarından çıkarılsın mı? Yeniden arkadaş olmak için yeni bir istek gerekir.',
  'askLeaveParty': 'Partiden ayrılınsın mı? Sesli sohbet senin için biter; yalnızca davetle girilen partiye dönmek için yeni davet gerekir.',
  'askKick':
      '{name} partiden çıkarılsın mı? Geri gelmek için yeni bir davet gerekir.',
  'askClosePost': 'Bu ilan kapatılsın mı? İstekleri de gider.',
  'updateRequiredTitle': 'Güncelleme gerekli',
  'updateRequiredBody': 'AnyTogether için AnyPS5 Remote {min} ya da daha yenisi gerekiyor. Arkadaşlar, partiler ve mesajlar güncellemeyi bekliyor; kumanda yine çalışır.',
  'updateRequiredBodyVersion': 'AnyTogether için AnyPS5 Remote {min} ya da daha yenisi gerekiyor; bu sürüm {v}. Arkadaşlar, partiler ve mesajlar güncellemeyi bekliyor; kumanda yine çalışır.',
  'updateRequiredUpdate': 'Güncelle',
  'updateRequiredLater': 'Sonra',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesSafety() => {'en': _en, 'tr': _tr};
