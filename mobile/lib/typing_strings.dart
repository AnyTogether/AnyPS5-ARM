import 'package:flutter/foundation.dart';

import 'strings.dart';

/// Typing for the game on the phone's own keyboard, in English and Turkish, beside [Strings].
extension TypingTexts on Strings {
  String _y(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String get typeKicker => _y('typeKicker');
  String get typeTitle => _y('typeTitle');
  String get typeSend => _y('typeSend');
  String get typeSearch => _y('typeSearch');
  String get typeGo => _y('typeGo');
  String get typeCancel => _y('typeCancel');
  String get typeKeyboardHint => _y('typeKeyboardHint');

  /// The Enter key's label the game asked for.
  String typeEnter(String enter) => switch (enter) {
    'search' => typeSearch,
    'go' => typeGo,
    _ => typeSend,
  };

  static const _en = {
    'typeKicker': 'The game asks',
    'typeTitle': 'Type here',
    'typeSend': 'Send',
    'typeSearch': 'Search',
    'typeGo': 'Go',
    'typeCancel': 'Cancel',
    'typeKeyboardHint': 'What you type here goes into the game.',
  };

  static const _tr = {
    'typeKicker': 'Oyun soruyor',
    'typeTitle': 'Buraya yaz',
    'typeSend': 'Gönder',
    'typeSearch': 'Ara',
    'typeGo': 'Git',
    'typeCancel': 'Vazgeç',
    'typeKeyboardHint': 'Buraya yazdığın oyuna gider.',
  };
}

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesTyping() => {
  'en': TypingTexts._en,
  'tr': TypingTexts._tr,
};
