import 'strings.dart';

/// The questions social steps ask before they happen, and Update Required, beside [Strings], their
/// texts in assets/l10n. The wording follows the website's and the Mac launcher's.
extension SafetyTexts on Strings {
  String askRemoveFriend(String name) => fill('askRemoveFriend', [name]);
  String get askLeaveParty => lookup('askLeaveParty');
  String askKick(String name) => fill('askKick', [name]);
  String get askClosePost => lookup('askClosePost');

  String get updateRequiredTitle => lookup('updateRequiredTitle');
  String updateRequiredBody(String minimum, String? current) => current == null
      ? fill('updateRequiredBody', [minimum])
      : fill('updateRequiredBodyVersion', [minimum, current]);
  String get updateRequiredUpdate => lookup('updateRequiredUpdate');
  String get updateRequiredLater => lookup('updateRequiredLater');
}
