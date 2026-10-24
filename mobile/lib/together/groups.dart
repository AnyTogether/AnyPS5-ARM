import 'messages.dart';

/// The most people in a group conversation, its creator included.
const maxGroupMembers = 32;

/// Group conversations, beside the direct ones [Messages] makes.
extension GroupChats on Messages {
  /// A new group with these friends (and an optional name), shown at once.
  Future<void> startGroup(List<String> userIds, {String? title}) async {
    final name = title?.trim() ?? '';
    final json = await account.call('POST', 'conversations', {
      'members': userIds,
      'title': ?(name.isEmpty ? null : name),
      'group': true,
    });
    final conversation = Conversation.fromJson(json);
    if (byId(conversation.id) == null) {
      conversations = [conversation, ...conversations];
    }
    await show(conversation.id);
  }
}
