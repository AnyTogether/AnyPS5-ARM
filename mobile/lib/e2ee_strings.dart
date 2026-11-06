import 'strings.dart';

/// End-to-end encrypted messages and reporting a message, beside [Strings], their texts in
/// assets/l10n. The wording is docs/e2ee.md's (AnyTogether), the same on every client.
extension E2eeTexts on Strings {
  String get e2eeOn => lookup('e2eeOn');
  String e2eeOnDetail(String name) => fill('e2eeOnDetail', [name]);
  String get e2eeOff => lookup('e2eeOff');
  String e2eeOffDetail(String name) => fill('e2eeOffDetail', [name]);
  String e2eeNoDevice(String name) => fill('e2eeNoDevice', [name]);
  String get e2eeSafetyNumber => lookup('e2eeSafetyNumber');
  String e2eeSafetyHow(String name) => fill('e2eeSafetyHow', [name]);
  String get e2eeMarkCompared => lookup('e2eeMarkCompared');
  String get e2eeCompared => lookup('e2eeCompared');
  String e2eeDevicesChanged(String name) => fill('e2eeDevicesChanged', [name]);
  String get e2eeMyDevicesChanged => lookup('e2eeMyDevicesChanged');
  String get e2eeCompare => lookup('e2eeCompare');
  String get e2eeDismiss => lookup('e2eeDismiss');
  String get e2eeDevices => lookup('e2eeDevices');
  String get e2eeYou => lookup('e2eeYou');
  String get e2eeNewDeviceNote => lookup('e2eeNewDeviceNote');
  String get e2eeBeforeDevice => lookup('e2eeBeforeDevice');
  String get e2eeUndecryptable => lookup('e2eeUndecryptable');
  String get e2eePreview => lookup('e2eePreview');

  /// A push or banner for a sealed message, which carries no text: "Sent you a message."
  String get e2eeNotification => lookup('e2eeNotification');
  String get e2eeReportNote => lookup('e2eeReportNote');
  String get e2eeThisDevice => lookup('e2eeThisDevice');

  String get messageReport => lookup('messageReport');
  String messageReportLead(String name) => fill('messageReportLead', [name]);

  /// The API's report reasons, in its order.
  static const reportReasons = [
    'spam',
    'harassment',
    'hate',
    'sexual',
    'impersonation',
    'cheating',
    'piracy',
    'other',
  ];

  String reportReason(String reason) => lookup('reportReason_$reason');
  String get reportSent => lookup('reportSent');
}
