import 'package:flutter/foundation.dart';

import 'strings.dart';

/// The friends-only name and picture (AnyTogether's private identity): their texts, English
/// and Turkish, as the launchers word them.
extension PrivateTexts on Strings {
  String _s(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String get privateTitle => _s('privateTitle');
  String get privateLead => _s('privateLead');
  String get privateName => _s('privateName');
  String get privateNameHelper => _s('privateNameHelper');
  String get privatePicture => _s('privatePicture');
  String get privatePictureHint => _s('privatePictureHint');
  String get privatePictureRemove => _s('privatePictureRemove');
  String get privateBadge => _s('privateBadge');
}

const _en = <String, String>{
  'privateTitle': 'Friends only',
  'privateLead': 'A name and picture only your accepted friends see, always next to your @handle. Everyone else sees the public ones.',
  'privateName': 'Friends-only name',
  'privateNameHelper': 'Your real name, say. Leave it empty to clear it',
  'privatePicture': 'Choose picture',
  'privatePictureHint': 'Friends see it in place of your public picture',
  'privatePictureRemove': 'Remove',
  'privateBadge': 'Friends only',
};

const _tr = <String, String>{
  'privateTitle': 'Yalnızca arkadaşlar',
  'privateLead': 'Yalnızca kabul ettiğin arkadaşlarının gördüğü bir ad ve fotoğraf, her zaman @kullanıcı adının yanında. Diğer herkes herkese açık olanları görür.',
  'privateName': 'Arkadaşlara görünen ad',
  'privateNameHelper': 'Örneğin gerçek adın. Temizlemek için boş bırak',
  'privatePicture': 'Fotoğraf seç',
  'privatePictureHint':
      'Arkadaşların herkese açık fotoğrafın yerine bunu görür',
  'privatePictureRemove': 'Kaldır',
  'privateBadge': 'Yalnızca arkadaşlar',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesPrivate() => {'en': _en, 'tr': _tr};
