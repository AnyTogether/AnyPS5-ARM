import 'package:flutter/foundation.dart';

import 'strings.dart';
import 'together/messages.dart';

/// Reactions, replies, editing and unsending, receipts, pinning and muting in messages, in
/// English and Turkish, beside [Strings]. The wording follows the website's.
extension ChatTexts on Strings {
  String _c(String key) =>
      (language == 'tr' ? _tr : _en)[key] ?? _en[key] ?? key;

  String get react => _c('react');
  String reactionLabel(MessageReaction reaction) =>
      _c('reaction_${reaction.name}');
  String get reply => _c('reply');
  String replyingTo(String name) => _c('replyingTo').replaceAll('{name}', name);
  String get earlierMessage => _c('earlierMessage');
  String get editMessage => _c('edit');
  String get unsend => _c('unsend');
  String get confirmUnsend => _c('confirmUnsend');
  String get editLimit => _c('editLimit');
  String get messageActions => _c('messageActions');
  String get conversationActions => _c('conversationActions');

  /// "Sent", "Delivered", "Read", "Seen by 2", "Seen by everyone".
  String receipt(Receipt receipt) => switch (receipt.kind) {
    ReceiptKind.sent => _c('receiptSent'),
    ReceiptKind.delivered => _c('receiptDelivered'),
    ReceiptKind.read => _c('receiptRead'),
    ReceiptKind.seen when receipt.everyone => _c('seenByEveryone'),
    ReceiptKind.seen => _c('seenBy').replaceAll('{n}', '${receipt.count}'),
  };

  String get pinConversation => _c('pin');
  String get unpinConversation => _c('unpin');
  String get pinnedMark => _c('pinned');
  String pinFull(int max) => _c('pinFull').replaceAll('{max}', '$max');
  String get muteConversation => _c('mute');
  String get unmuteConversation => _c('unmute');
  String get mutedMark => _c('muted');

  String get readReceipts => _c('readReceipts');
  String get readReceiptsOn => _c('readReceiptsOn');
  String get readReceiptsOff => _c('readReceiptsOff');
  String get readReceiptsHint => _c('readReceiptsHint');
}

/// The keys each language has, for the test that keeps the two in step.
@visibleForTesting
Iterable<String> chatTextKeys(String language) =>
    (language == 'tr' ? _tr : _en).keys;

const _en = {
  'react': 'React',
  'reaction_like': 'Like',
  'reaction_love': 'Love',
  'reaction_laugh': 'Haha',
  'reaction_wow': 'Wow',
  'reaction_sad': 'Sad',
  'reaction_fire': 'Fire',
  'reaction_gg': 'GG',
  'reply': 'Reply',
  'replyingTo': 'Replying to {name}',
  'earlierMessage': 'An earlier message',
  'edit': 'Edit',
  'unsend': 'Unsend',
  'confirmUnsend': "Unsend this message for everyone? It can't be undone.",
  'editLimit': "This message can't be edited any more.",
  'messageActions': 'Message actions',
  'conversationActions': 'Conversation options',
  'receiptSent': 'Sent',
  'receiptDelivered': 'Delivered',
  'receiptRead': 'Read',
  'seenBy': 'Seen by {n}',
  'seenByEveryone': 'Seen by everyone',
  'pin': 'Pin to top',
  'unpin': 'Unpin',
  'pinned': 'Pinned',
  'pinFull': 'You can pin up to {max} conversations.',
  'mute': 'Mute notifications',
  'unmute': 'Unmute',
  'muted': 'Muted',
  'readReceipts': 'Send read receipts',
  'readReceiptsOn': 'On',
  'readReceiptsOff': 'Off',
  'readReceiptsHint': "When off, people don't see when you've read their messages, and you don't see theirs. Delivered still shows.",
};

const _tr = {
  'react': 'Tepki ver',
  'reaction_like': 'Beğen',
  'reaction_love': 'Sevgi',
  'reaction_laugh': 'Haha',
  'reaction_wow': 'Vay',
  'reaction_sad': 'Üzgün',
  'reaction_fire': 'Ateş',
  'reaction_gg': 'GG',
  'reply': 'Yanıtla',
  'replyingTo': '{name} kişisine yanıt',
  'earlierMessage': 'Önceki bir mesaj',
  'edit': 'Düzenle',
  'unsend': 'Geri al',
  'confirmUnsend': 'Bu mesaj herkesten geri alınsın mı? Bu geri döndürülemez.',
  'editLimit': 'Bu mesaj artık düzenlenemez.',
  'messageActions': 'Mesaj seçenekleri',
  'conversationActions': 'Konuşma seçenekleri',
  'receiptSent': 'Gönderildi',
  'receiptDelivered': 'İletildi',
  'receiptRead': 'Okundu',
  'seenBy': '{n} kişi gördü',
  'seenByEveryone': 'Herkes gördü',
  'pin': 'En üste sabitle',
  'unpin': 'Sabitlemeyi kaldır',
  'pinned': 'Sabitlendi',
  'pinFull': 'En fazla {max} konuşma sabitleyebilirsin.',
  'mute': 'Bildirimleri sessize al',
  'unmute': 'Sesi aç',
  'muted': 'Sessizde',
  'readReceipts': 'Okundu bilgisi gönder',
  'readReceiptsOn': 'Açık',
  'readReceiptsOff': 'Kapalı',
  'readReceiptsHint': 'Kapalıyken mesajlarını okuduğunu kimse görmez, sen de onlarınkini görmezsin. İletildi bilgisi yine görünür.',
};

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTablesChat() => {'en': _en, 'tr': _tr};
