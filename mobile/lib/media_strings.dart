import 'strings.dart';
import 'together/messages.dart';
import 'together/storage.dart';
import 'together/together_account.dart';

/// Photos, clips and voice notes in messages, and the cloud storage they count against, beside
/// [Strings], their texts in assets/l10n. The wording follows the website's.
extension MediaTexts on Strings {
  String get mediaPhoto => lookup('photo');
  String get mediaClip => lookup('clip');
  String get mediaVoice => lookup('voiceNote');
  String get mediaRemoved => lookup('removed');
  String get mediaBlocked => lookup('blocked');
  String get mediaUnplayable => lookup('unplayable');
  String get sendPhoto => lookup('sendPhoto');
  String get photoCaption => lookup('photoCaption');
  String get photoTooBig => lookup('photoTooBig');
  String get storageTitle => lookup('storageTitle');
  String get storageSaves => lookup('storageSaves');
  String get storageMedia => lookup('storageMedia');
  String get storageDetail => lookup('storageDetail');
  String get storageFailed => lookup('storageFailed');

  /// "Photo", "Clip", "Voice note" for a kind of media.
  String mediaLabel(MediaKind kind) => switch (kind) {
    MediaKind.clip => mediaClip,
    MediaKind.voice => mediaVoice,
    _ => mediaPhoto,
  };

  /// What a conversation's line shows of a message: its text, or what media it holds and its
  /// caption.
  String messagePreview(ChatMessage message) {
    if (message.kind == MediaKind.text) return message.text ?? '';
    final caption = message.caption;
    final label = mediaLabel(message.kind);
    return caption == null || caption.isEmpty ? label : '$label: $caption';
  }

  /// "12.5 MB of 100 MB"
  String storageUsed(StorageUsage usage) =>
      fill('storageUsed', [megabytes(usage.used), megabytes(usage.limit)]);

  /// Bytes as megabytes: one decimal under 10 MB, none above.
  String megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    final text = mb < 10 && mb != mb.roundToDouble()
        ? decimal(mb, 1)
        : mb.round().toString();
    return '$text MB';
  }

  /// Why a photo was not sent, when the server said so; null for a plain failure.
  String? mediaProblemOrNull(TogetherProblem problem) => switch (problem.code) {
    'quota_exceeded' => lookup('quotaExceeded'),
    'payload_too_large' => photoTooBig,
    'unsupported_media_type' => lookup('unsupported'),
    'bad_image' || 'bad_media' => lookup('badImage'),
    'restricted_by_family' => lookup('family'),
    'storage_disabled' => lookup('storageOff'),
    _ => null,
  };

  String mediaProblem(TogetherProblem problem) =>
      mediaProblemOrNull(problem) ?? messagesFailed;
}
