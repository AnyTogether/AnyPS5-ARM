import 'together_account.dart';

/// Why something is reported, as the API names it, in the order the sheet lists them.
enum ReportReason {
  spam,
  harassment,
  hate,
  sexual,
  impersonation,
  cheating,
  piracy,
  other,
}

/// What a report is about, as the API names it.
enum ReportTarget { message }

/// Sends a report for a moderator to read; its author is not told who sent it.
Future<void> sendReport(
  TogetherAccount account, {
  required ReportTarget target,
  required String id,
  required ReportReason reason,
  String? note,
}) async {
  final trimmed = note?.trim();
  await account.call('POST', 'reports', {
    'targetKind': target.name,
    'targetId': id,
    'reason': reason.name,
    if (trimmed != null && trimmed.isNotEmpty) 'note': trimmed,
  });
}
