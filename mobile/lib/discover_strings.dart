import 'strings.dart';

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
}

const _en = {
  'joinable': 'Joinable',
  'joinableCount': 'Joinable · {n}/{max}',
  'joinableHint': 'Join from AnyTogether in the launcher on your Mac.',
};

const _tr = {
  'joinable': 'Katılınabilir',
  'joinableCount': 'Katılınabilir · {n}/{max}',
  'joinableHint': "Mac'teki launcher'da AnyTogether'dan katıl.",
};
