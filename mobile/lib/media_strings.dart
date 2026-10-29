import 'package:flutter/foundation.dart';

import 'strings.dart';
import 'together/messages.dart';
import 'together/storage.dart';
import 'together/together_account.dart';

/// Photos, clips and voice notes in messages, and the cloud storage they count against, in
/// English and Turkish, beside [Strings]. The wording follows the website's.
extension MediaTexts on Strings {
  String _m(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String get mediaPhoto => _m('photo');
  String get mediaClip => _m('clip');
  String get mediaVoice => _m('voice');
  String get mediaRemoved => _m('removed');
  String get mediaBlocked => _m('blocked');
  String get mediaUnplayable => _m('unplayable');
  String get sendPhoto => _m('sendPhoto');
  String get photoCaption => _m('photoCaption');
  String get photoTooBig => _m('photoTooBig');
  String get storageTitle => _m('storageTitle');
  String get storageSaves => _m('storageSaves');
  String get storageMedia => _m('storageMedia');
  String get storageDetail => _m('storageDetail');
  String get storageFailed => _m('storageFailed');

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
      (language == 'tr' ? '{u} / {l}' : '{u} of {l}')
          .replaceAll('{u}', megabytes(usage.used))
          .replaceAll('{l}', megabytes(usage.limit));

  /// Bytes as megabytes: one decimal under 10 MB, none above.
  String megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    final text = mb < 10 && mb != mb.roundToDouble()
        ? mb.toStringAsFixed(1)
        : mb.round().toString();
    return '${language == 'tr' ? text.replaceAll('.', ',') : text} MB';
  }

  /// Why a photo was not sent, when the server said so; null for a plain failure.
  String? mediaProblemOrNull(TogetherProblem problem) => switch (problem.code) {
    'quota_exceeded' => _m('quotaExceeded'),
    'payload_too_large' => photoTooBig,
    'unsupported_media_type' => _m('unsupported'),
    'bad_image' || 'bad_media' => _m('badImage'),
    'restricted_by_family' => _m('family'),
    'storage_disabled' => _m('storageOff'),
    _ => null,
  };

  String mediaProblem(TogetherProblem problem) =>
      mediaProblemOrNull(problem) ?? messagesFailed;
}

const _en = {
  'photo': 'Photo',
  'clip': 'Clip',
  'voice': 'Voice note',
  'removed': 'Removed',
  'blocked': 'Not available',
  'unplayable': 'This cannot be played here',
  'sendPhoto': 'Send a photo',
  'photoCaption': 'Add a caption…',
  'photoTooBig': 'That photo is too big: at most 10 MB.',
  'quotaExceeded':
      'Your cloud storage is full: delete saves or media to make room.',
  'unsupported': 'Only PNG, JPEG or WebP pictures can be sent.',
  'badImage': 'That picture cannot be read.',
  'family': 'Your family settings do not allow this.',
  'storageOff': 'This server does not keep photos.',
  'storageTitle': 'Cloud storage',
  'storageSaves': 'Saves',
  'storageMedia': 'Photos and clips',
  'storageDetail':
      'Cloud saves and the media you send share this space on AnyTogether.',
  'storageFailed': 'Storage could not be read.',
};

const _tr = {
  'photo': 'Fotoğraf',
  'clip': 'Klip',
  'voice': 'Sesli mesaj',
  'removed': 'Kaldırıldı',
  'blocked': 'Gösterilemiyor',
  'unplayable': 'Bu burada oynatılamıyor',
  'sendPhoto': 'Fotoğraf gönder',
  'photoCaption': 'Açıklama ekle…',
  'photoTooBig': 'Bu fotoğraf çok büyük: en fazla 10 MB.',
  'quotaExceeded': 'Bulut alanın dolu: yer açmak için kayıt ya da medya sil.',
  'unsupported': 'Yalnızca PNG, JPEG ya da WebP resimler gönderilebilir.',
  'badImage': 'Bu resim okunamıyor.',
  'family': 'Aile ayarların buna izin vermiyor.',
  'storageOff': 'Bu sunucu fotoğraf saklamıyor.',
  'storageTitle': 'Bulut alanı',
  'storageSaves': 'Kayıtlar',
  'storageMedia': 'Fotoğraflar ve klipler',
  'storageDetail':
      'Bulut kayıtları ve gönderdiğin medya AnyTogether\'da bu alanı paylaşır.',
  'storageFailed': 'Alan bilgisi okunamadı.',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesMedia() => {'en': _en, 'tr': _tr};
