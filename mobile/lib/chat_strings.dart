import 'strings.dart';
import 'together/messages.dart';

/// Reactions, replies, editing and unsending, receipts, pinning and muting in messages, beside
/// [Strings], their texts in assets/l10n. The wording follows the website's.
extension ChatTexts on Strings {
  String get react => lookup('react');
  String reactionLabel(MessageReaction reaction) =>
      lookup('reaction_${reaction.name}');
  String get reply => lookup('messagesReply');
  String replyingTo(String name) => fill('replyingTo', [name]);
  String get earlierMessage => lookup('earlierMessage');
  String get editMessage => lookup('messagesEdit');
  String get unsend => lookup('messagesUnsend');
  String get confirmUnsend => lookup('messagesUnsendConfirm');
  String get editLimit => lookup('messagesEditLimit');
  String get messageActions => lookup('messageActions');
  String get conversationActions => lookup('conversationActions');

  /// "Sent", "Delivered", "Read", "Seen by 2", "Seen by everyone".
  String receipt(Receipt receipt) => switch (receipt.kind) {
    ReceiptKind.sent => lookup('receiptSent'),
    ReceiptKind.delivered => lookup('receiptDelivered'),
    ReceiptKind.read => lookup('receiptRead'),
    ReceiptKind.seen when receipt.everyone => lookup('receiptSeenByEveryone'),
    ReceiptKind.seen => fill('seenBy', ['${receipt.count}']),
  };

  String get pinConversation => lookup('conversationPin');
  String get unpinConversation => lookup('conversationUnpin');
  String get pinnedMark => lookup('conversationPinned');
  String pinFull(int max) => fill('pinFull', [max]);
  String get muteConversation => lookup('conversationMute');
  String get unmuteConversation => lookup('unmute');
  String get mutedMark => lookup('conversationMuted');

  String get readReceipts => lookup('readReceipts');
  String get readReceiptsOn => lookup('on');
  String get readReceiptsOff => lookup('off');
  String get readReceiptsHint => lookup('readReceiptsHint');
}
