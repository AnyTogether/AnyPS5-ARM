import 'strings.dart';

/// Typing for the game on the phone's own keyboard, beside [Strings], their texts in assets/l10n.
extension TypingTexts on Strings {
  String get typeKicker => lookup('typeKicker');
  String get typeTitle => lookup('typeTitle');
  String get typeSend => lookup('typeSend');
  String get typeSearch => lookup('typeSearch');
  String get typeGo => lookup('typeGo');
  String get typeCancel => lookup('typeCancel');
  String get typeKeyboardHint => lookup('typeKeyboardHint');

  /// The Enter key's label the game asked for.
  String typeEnter(String enter) => switch (enter) {
    'search' => typeSearch,
    'go' => typeGo,
    _ => typeSend,
  };
}
