import 'strings.dart';

/// The friends-only name and picture (AnyTogether's private identity): their texts, as the
/// launchers word them.
extension PrivateTexts on Strings {
  String get privateTitle => lookup('privateTitle');
  String get privateLead => lookup('privateLead');
  String get privateName => lookup('privateName');
  String get privateNameHelper => lookup('privateNameHelper');
  String get privatePicture => lookup('privatePicture');
  String get privatePictureHint => lookup('privatePictureHint');
  String get privatePictureRemove => lookup('privatePictureRemove');
  String get privateBadge => lookup('privateBadge');
}
