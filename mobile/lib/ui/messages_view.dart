import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../chat_strings.dart';
import '../media_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/groups.dart';
import '../together/messages.dart';
import '../together/people.dart';
import '../together/storage.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import 'message_media.dart';
import 'profile_edit.dart' show pickFromLibrary;
import 'together_widgets.dart';

export 'message_media.dart' show MessageMedia;

/// Messages: the conversations on the left, the open one on the right with its composer at the
/// bottom, the way a phone held sideways has room for both.
class MessagesPane extends StatefulWidget {
  const MessagesPane({super.key, required this.hub, this.pickPhoto});

  final TogetherHub hub;

  /// Picks a photo to send; the phone's library unless a test says otherwise.
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<MessagesPane> createState() => _MessagesPaneState();
}

class _MessagesPaneState extends State<MessagesPane> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final Messages _messages = widget.hub.messages;

  /// The message the next one answers; dropped when another conversation opens.
  ChatMessage? _reply;

  ChatMessage? get _replyTo =>
      _reply?.conversationId == _messages.openId ? _reply : null;

  /// The server keeps photos: the composer can attach one.
  late bool _storage = widget.hub.account.storage?.enabled ?? false;

  @override
  void initState() {
    super.initState();
    if (!_messages.loaded) _messages.refresh().catchError((_) {});
    _scroll.addListener(_nearTop);
    widget.hub.account.storageEnabled().then((on) {
      if (mounted && on != _storage) setState(() => _storage = on);
    });
  }

  /// A photo from the library to the open conversation, with what is typed as its caption.
  Future<void> _attach() async {
    final texts = Texts.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final Uint8List? bytes;
    try {
      bytes = await (widget.pickPhoto ?? pickFromLibrary)();
    } on Object {
      return;
    }
    if (bytes == null || bytes.isEmpty || !mounted) return;
    final most = widget.hub.account.storage?.imageMax ?? 10 * 1024 * 1024;
    if (bytes.length > most) {
      messenger?.showSnackBar(SnackBar(content: Text(texts.photoTooBig)));
      return;
    }
    final caption = _text.text;
    _text.clear();
    await _messages.sendPhoto(bytes, caption: caption);
  }

  @override
  void dispose() {
    // Not shown any more: what comes in is unread again.
    _messages.hide();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The thread runs bottom up: near its end are the older messages.
  void _nearTop() {
    if (_scroll.position.extentAfter < 120 && _messages.more) {
      _messages.older().catchError((_) {});
    }
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    final reply = _replyTo;
    _text.clear();
    setState(() => _reply = null);
    _messages.send(text, replyTo: reply);
  }

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  /// React, reply, edit or unsend: what can be done with a message, picked from a sheet.
  Future<void> _actions(ChatMessage message) async {
    final me = widget.hub.me;
    final mine = message.authorId == me;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      showDragHandle: false,
      builder: (context) => _MessageSheet(
        message: message,
        me: me,
        canEdit: message.canEdit(me),
        canUnsend: mine,
      ),
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case MessageReaction reaction:
        await _react(message, reaction);
      case _MessageAction.reply:
        setState(() => _reply = message);
        _focus.requestFocus();
      case _MessageAction.edit:
        await _edit(message);
      case _MessageAction.unsend:
        await _unsend(message);
    }
  }

  Future<void> _react(ChatMessage message, MessageReaction reaction) async {
    final texts = Texts.of(context);
    try {
      await _messages.react(message, reaction);
    } on Object catch (error) {
      if (mounted) _say(togetherFailure(texts, error));
    }
  }

  Future<void> _edit(ChatMessage message) async {
    final texts = Texts.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(text: message.words ?? ''),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    if (text.trim() == message.words?.trim()) return;
    try {
      await _messages.edit(message, text);
    } on Object catch (error) {
      if (!mounted) return;
      _say(switch (error) {
        // Past the edit window (403) or the edit limit (409).
        TogetherProblem(code: 'edit_limit') ||
        TogetherProblem(status: 403) => texts.editLimit,
        _ => togetherFailure(texts, error),
      });
    }
  }

  Future<void> _unsend(ChatMessage message) async {
    final texts = Texts.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151821),
        content: Text(
          texts.confirmUnsend,
          style: const TextStyle(color: Colors.white70, fontSize: 14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              texts.cancel,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: togetherError,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(texts.unsend),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await _messages.unsend(message);
      if (_reply?.id == message.id) setState(() => _reply = null);
    } on Object catch (error) {
      if (mounted) _say(togetherFailure(texts, error));
    }
  }

  /// Pin or unpin, mute or unmute a conversation.
  Future<void> _conversationActions(Conversation conversation) async {
    final texts = Texts.of(context);
    final picked = await showModalBottomSheet<_ConversationAction>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetRow(
                icon: conversation.pinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                label: conversation.pinned
                    ? texts.unpinConversation
                    : texts.pinConversation,
                onTap: () => Navigator.of(context).pop(_ConversationAction.pin),
              ),
              _SheetRow(
                icon: conversation.muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                label: conversation.muted
                    ? texts.unmuteConversation
                    : texts.muteConversation,
                onTap: () =>
                    Navigator.of(context).pop(_ConversationAction.mute),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      if (picked == _ConversationAction.pin) {
        await _messages.pin(conversation.id, !conversation.pinned);
      } else {
        await _messages.mute(conversation.id, !conversation.muted);
      }
    } on Object catch (error) {
      if (!mounted) return;
      _say(switch (error) {
        TogetherProblem(code: 'full') => texts.pinFull(maxPinned),
        _ => togetherFailure(texts, error),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: _messages,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 248, child: _list(texts)),
          const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
          Expanded(child: _thread(texts)),
        ],
      ),
    );
  }

  Widget _list(Strings texts) {
    final me = widget.hub.me;
    final list = _messages.conversations;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 0, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  texts.messages,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: texts.newGroup,
                onPressed: _newGroup,
                icon: const Icon(
                  Icons.group_add_rounded,
                  color: togetherAccent,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
        if (_messages.loaded && list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              texts.messagesNone,
              style: const TextStyle(color: Colors.white54, fontSize: 13.5),
            ),
          ),
        for (final conversation in list)
          _ConversationRow(
            conversation: conversation,
            me: me,
            selected: conversation.id == _messages.openId,
            onTap: () => _messages.show(conversation.id).catchError((_) {}),
            onLongPress: () => _conversationActions(conversation),
          ),
      ],
    );
  }

  Widget _thread(Strings texts) {
    final conversation = _messages.open;
    if (conversation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            texts.messagesPick,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ),
      );
    }
    final me = widget.hub.me;
    final others = conversation.others(me);
    final thread = _messages.thread.reversed.toList();
    // The receipt goes under my newest message on the server, and nowhere else.
    final newestMine = thread
        .where((m) => m.authorId == me && m.seq > 0)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Row(
            children: [
              if (others.length == 1)
                Avatar(person: others.single, size: 32)
              else
                const Icon(Icons.groups_rounded, color: togetherAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  conversation.name(me),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!conversation.group && others.length == 1)
                IconButton(
                  tooltip: texts.callFriend(others.single.displayName),
                  onPressed: widget.hub.calls.inCall
                      ? null
                      : () => widget.hub.calls.ring(others.single),
                  icon: const Icon(
                    Icons.call_outlined,
                    color: togetherAccent,
                    size: 20,
                  ),
                ),
              IconButton(
                tooltip: texts.conversationActions,
                onPressed: () => _conversationActions(conversation),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0x14FFFFFF)),
        Expanded(
          child: _messages.loadingThread && thread.isEmpty
              ? const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  itemCount: thread.length + (_messages.more ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == thread.length) {
                      return Center(
                        child: TextButton(
                          onPressed: () => _messages.older().catchError((_) {}),
                          child: Text(texts.messagesEarlier),
                        ),
                      );
                    }
                    final message = thread[index];
                    final above = index + 1 < thread.length
                        ? thread[index + 1]
                        : null;
                    return _Bubble(
                      message: message,
                      me: me,
                      mine: message.authorId == me,
                      quote: message.replyTo == null || message.deleted
                          ? null
                          : _Quote(
                              key: ValueKey('quote-${message.seq}'),
                              target: _messages.thread
                                  .where((m) => m.seq == message.replyTo)
                                  .firstOrNull,
                              conversation: conversation,
                              me: me,
                            ),
                      receipt: identical(message, newestMine)
                          ? receiptOf(conversation, message, me)
                          : null,
                      onActions: message.deleted || message.seq == 0
                          ? null
                          : () => _actions(message),
                      onReact: (reaction) => _react(message, reaction),
                      // A group names who wrote, once for messages in a row.
                      author:
                          conversation.group &&
                              message.authorId != me &&
                              above?.authorId != message.authorId
                          ? conversation.author(message.authorId)
                          : null,
                      onRetry: () => _messages.retry(message),
                    );
                  },
                ),
        ),
        _typing(texts, conversation),
        if (_replyTo case final reply?) _replying(texts, conversation, reply),
        _composer(texts),
      ],
    );
  }

  /// "Ece is typing…" under the thread while someone else is.
  Widget _typing(Strings texts, Conversation conversation) => ListenableBuilder(
    listenable: widget.hub.typing,
    builder: (context, _) {
      final names = [
        for (final id in widget.hub.typing.who(conversation.id))
          conversation.author(id)?.displayName ?? '…',
      ];
      return AnimatedSize(
        duration: const Duration(milliseconds: 160),
        child: names.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text(
                  texts.typing(names),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
      );
    },
  );

  /// "Replying to Ece" and what she wrote, above the composer, with a way out.
  Widget _replying(
    Strings texts,
    Conversation conversation,
    ChatMessage reply,
  ) {
    final me = widget.hub.me;
    final name = reply.authorId == me
        ? texts.messagesYou
        : conversation.author(reply.authorId)?.displayName ?? '…';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: togetherAccent, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: togetherAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texts.replyingTo(name),
                  style: const TextStyle(
                    color: togetherAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  texts.messagePreview(reply),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: texts.cancel,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _reply = null),
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  /// A group with the friends picked, and a name if one is given.
  Future<void> _newGroup() async {
    final texts = Texts.of(context);
    final friends = widget.hub.friends;
    if (!friends.loaded) await friends.refresh().catchError((_) {});
    if (!mounted) return;
    final picked = await showDialog<(List<String>, String)>(
      context: context,
      builder: (_) => _NewGroupDialog(
        friends: [for (final friend in friends.friends) friend.person],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await _messages.startGroup(picked.$1, title: picked.$2);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(togetherFailure(texts, error))));
      }
    }
  }

  Widget _composer(Strings texts) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
    child: Row(
      children: [
        if (_storage)
          IconButton(
            tooltip: texts.sendPhoto,
            onPressed: _messages.openId == null ? null : _attach,
            icon: const Icon(
              Icons.add_photo_alternate_outlined,
              color: togetherAccent,
              size: 22,
            ),
          ),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 3,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: texts.messagesWrite,
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: const Color(0x14FFFFFF),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (text) {
              final id = _messages.openId;
              if (id != null && text.trim().isNotEmpty) {
                widget.hub.typing.typed(id);
              }
            },
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filled(
          tooltip: texts.messagesSend,
          onPressed: _send,
          style: IconButton.styleFrom(
            backgroundColor: togetherAccent,
            foregroundColor: togetherInk,
          ),
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    ),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.me,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Conversation conversation;
  final String? me;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final others = conversation.others(me);
    final last = conversation.lastMessage;
    final unread = conversation.unread;
    final preview = last == null
        ? ''
        : last.deleted
        ? texts.messagesDeleted
        : '${last.authorId == me ? '${texts.messagesYou}: ' : ''}${texts.messagePreview(last)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0x1F8AB4FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                if (others.length == 1)
                  Avatar(person: others.single, size: 36)
                else
                  const SizedBox.square(
                    dimension: 36,
                    child: Icon(Icons.groups_rounded, color: togetherAccent),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.name(me),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: unread > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (conversation.muted)
                            _Mark(
                              icon: Icons.notifications_off_rounded,
                              label: texts.mutedMark,
                            ),
                          if (conversation.pinned)
                            _Mark(
                              icon: Icons.push_pin_rounded,
                              label: texts.pinnedMark,
                            ),
                          Text(
                            _when(conversation.updatedAt),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unread > 0
                                    ? Colors.white70
                                    : Colors.white38,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          if (unread > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                // Muted: still counted, without the call to look.
                                color: conversation.muted
                                    ? Colors.white24
                                    : togetherAccent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: TextStyle(
                                  color: conversation.muted
                                      ? Colors.white
                                      : togetherInk,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The time today, the day and month before.
String _when(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${two(local.hour)}:${two(local.minute)}';
  }
  return '${local.day}.${two(local.month)}';
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.me,
    required this.mine,
    required this.author,
    required this.onRetry,
    this.quote,
    this.receipt,
    this.onActions,
    this.onReact,
  });

  final ChatMessage message;
  final String? me;
  final bool mine;
  final Person? author;
  final VoidCallback onRetry;

  /// The message this one answers, drawn above its words.
  final Widget? quote;

  /// Where my newest message has got; null under every other one.
  final Receipt? receipt;

  /// Opens what can be done with it; null for one removed or still on its way.
  final VoidCallback? onActions;

  /// A reaction chip tapped: mine goes, another's is added.
  final ValueChanged<MessageReaction>? onReact;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final shown = message.words ?? (message.kind == MediaKind.text ? '' : null);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? const Color(0x338AB4FF) : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: message.failed ? Border.all(color: togetherError) : null,
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ?quote,
          if (!message.deleted && message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: MessageMedia(message: message, mine: mine),
            ),
          if (message.deleted || shown != null)
            Text(
              message.deleted ? texts.messagesDeleted : shown ?? '',
              style: TextStyle(
                color: message.deleted ? Colors.white38 : Colors.white,
                fontSize: 14.5,
                fontStyle: message.deleted
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            message.failed
                ? switch (message.problem?.code) {
                    'link_blocked' => texts.linkBlocked(
                      message.problem?.extra?['domain'] as String?,
                    ),
                    'forbidden' => texts.cannotMessage,
                    _ when message.problem != null => texts.mediaProblem(
                      message.problem!,
                    ),
                    _ => texts.messagesFailed,
                  }
                : [
                    _when(message.createdAt),
                    if (message.edited && !message.deleted)
                      texts.messagesEdited,
                  ].join(' · '),
            style: TextStyle(
              color: message.failed ? togetherError : Colors.white38,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
    final retry = message.failed && !message.refused;
    final touchable = GestureDetector(
      onTap: retry ? onRetry : null,
      onLongPress: onActions,
      child: bubble,
    );
    // A quiet button beside the bubble says a long press is not the only way in.
    final more = onActions == null
        ? const SizedBox(width: 28)
        : IconButton(
            tooltip: texts.messageActions,
            onPressed: onActions,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(
              Icons.more_horiz_rounded,
              size: 16,
              color: Colors.white24,
            ),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (author != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2, top: 4),
              child: Text(
                author!.displayName,
                style: const TextStyle(
                  color: togetherAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (mine) more,
              Flexible(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: message.pending ? 0.55 : 1,
                  child: touchable,
                ),
              ),
              if (!mine) more,
            ],
          ),
          if (message.reactions.isNotEmpty && !message.deleted)
            Padding(
              padding: EdgeInsets.only(
                top: 3,
                left: mine ? 0 : 4,
                right: mine ? 4 : 0,
              ),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final count in message.reactions)
                    _ReactionChip(
                      key: ValueKey(
                        'reaction-${message.seq}-${count.reaction.name}',
                      ),
                      count: count,
                      mine: me != null && count.userIds.contains(me),
                      label: texts.reactionLabel(count.reaction),
                      onTap: onReact == null
                          ? null
                          : () => onReact!(count.reaction),
                    ),
                ],
              ),
            ),
          if (receipt case final receipt?)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 4),
              child: Text(
                texts.receipt(receipt),
                style: TextStyle(
                  color: receipt.kind == ReceiptKind.read || receipt.everyone
                      ? togetherAccent
                      : Colors.white38,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A reaction under a bubble: its glyph, how many when more than one, lit when it is mine.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    super.key,
    required this.count,
    required this.mine,
    required this.label,
    required this.onTap,
  });

  final ReactionCount count;
  final bool mine;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: mine,
    label: count.count > 1 ? '$label ${count.count}' : label,
    excludeSemantics: true,
    child: Material(
      color: mine ? const Color(0x2E8AB4FF) : const Color(0x14FFFFFF),
      shape: StadiumBorder(
        side: BorderSide(
          color: mine ? const Color(0x998AB4FF) : Colors.transparent,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Glyph(count.reaction, size: 13),
              if (count.count > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '${count.count}',
                  style: TextStyle(
                    color: mine ? togetherAccent : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// A reaction drawn: an emoji, or "GG" set as a small badge.
class _Glyph extends StatelessWidget {
  const _Glyph(this.reaction, {required this.size});

  final MessageReaction reaction;
  final double size;

  @override
  Widget build(BuildContext context) => reaction == MessageReaction.gg
      ? Text(
          reaction.glyph,
          style: TextStyle(
            color: togetherAccent,
            fontSize: size * 0.82,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            height: 1.25,
          ),
        )
      : Text(reaction.glyph, style: TextStyle(fontSize: size, height: 1.2));
}

/// The message a reply answers, above its words: who wrote it and what, as far as the loaded
/// thread knows it.
class _Quote extends StatelessWidget {
  const _Quote({
    super.key,
    required this.target,
    required this.conversation,
    required this.me,
  });

  final ChatMessage? target;
  final Conversation conversation;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final target = this.target;
    final name = target == null
        ? null
        : target.authorId == me
        ? texts.messagesYou
        : conversation.author(target.authorId)?.displayName;
    final text = target == null
        ? texts.earlierMessage
        : target.deleted
        ? texts.messagesDeleted
        : texts.messagePreview(target);
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.fromLTRB(9, 4, 10, 5),
      decoration: const BoxDecoration(
        color: Color(0x14000000),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        border: Border(left: BorderSide(color: togetherAccent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (name != null)
            Text(
              name,
              style: const TextStyle(
                color: togetherAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12.5,
              fontStyle: target == null || target.deleted
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small mark in a conversation's row: pinned, muted.
class _Mark extends StatelessWidget {
  const _Mark({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Icon(icon, size: 12.5, color: Colors.white38),
    ),
  );
}

enum _MessageAction { reply, edit, unsend }

enum _ConversationAction { pin, mute }

/// What can be done with a message: the seven reactions on top, then reply, and on one's
/// own, edit and unsend. Pops a [MessageReaction] or a [_MessageAction].
class _MessageSheet extends StatelessWidget {
  const _MessageSheet({
    required this.message,
    required this.me,
    required this.canEdit,
    required this.canUnsend,
  });

  final ChatMessage message;
  final String? me;
  final bool canEdit;
  final bool canUnsend;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  texts.react,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final reaction in MessageReaction.values)
                  _ReactionButton(
                    reaction: reaction,
                    label: texts.reactionLabel(reaction),
                    picked: message.reacted(reaction, me),
                    onTap: () => Navigator.of(context).pop(reaction),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            const SizedBox(height: 4),
            _SheetRow(
              icon: Icons.reply_rounded,
              label: texts.reply,
              onTap: () => Navigator.of(context).pop(_MessageAction.reply),
            ),
            if (canEdit)
              _SheetRow(
                icon: Icons.edit_outlined,
                label: texts.editMessage,
                onTap: () => Navigator.of(context).pop(_MessageAction.edit),
              ),
            if (canUnsend)
              _SheetRow(
                icon: Icons.undo_rounded,
                label: texts.unsend,
                color: togetherError,
                onTap: () => Navigator.of(context).pop(_MessageAction.unsend),
              ),
          ],
        ),
      ),
    );
  }
}

/// One reaction to pick in the sheet: lit when it is mine already (picking it takes it back).
class _ReactionButton extends StatefulWidget {
  const _ReactionButton({
    required this.reaction,
    required this.label,
    required this.picked,
    required this.onTap,
  });

  final MessageReaction reaction;
  final String label;
  final bool picked;
  final VoidCallback onTap;

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.label,
    child: Semantics(
      button: true,
      selected: widget.picked,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.88 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.picked
                  ? const Color(0x2E8AB4FF)
                  : const Color(0x0DFFFFFF),
              border: Border.all(
                color: widget.picked
                    ? const Color(0x998AB4FF)
                    : Colors.transparent,
              ),
            ),
            child: _Glyph(widget.reaction, size: 22),
          ),
        ),
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: color, fontSize: 14.5)),
        ],
      ),
    ),
  );
}

/// New words for one's own message, in place of the old.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.text});

  final String text;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF151821),
      title: Text(
        texts.editMessage,
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: const Color(0x14FFFFFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            texts.cancel,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => FilledButton(
            onPressed: _text.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_text.text),
            child: Text(texts.save),
          ),
        ),
      ],
    );
  }
}

/// Friends to pick for a new group (at most [maxGroupMembers] people with you), and its name.
class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog({required this.friends});

  final List<Person> friends;

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final _name = TextEditingController();
  final _picked = <String>{};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final full = _picked.length + 1 >= maxGroupMembers;
    return Dialog(
      backgroundColor: const Color(0xFF151821),
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  texts.newGroup,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    maxLength: 80,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: texts.groupName,
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0x14FFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              full
                  ? texts.groupFull(maxGroupMembers)
                  : widget.friends.isEmpty
                  ? texts.noFriendsToMessage
                  : texts.groupPick,
              style: TextStyle(
                color: full ? togetherAway : Colors.white54,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 4.4,
                children: [
                  for (final person in widget.friends)
                    _Pickable(
                      person: person,
                      picked: _picked.contains(person.id),
                      onTap: !_picked.contains(person.id) && full
                          ? null
                          : () => setState(
                              () => _picked.contains(person.id)
                                  ? _picked.remove(person.id)
                                  : _picked.add(person.id),
                            ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  texts.groupPicked(_picked.length + 1, maxGroupMembers),
                  style: const TextStyle(color: Colors.white38, fontSize: 12.5),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    texts.cancel,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop((_picked.toList(), _name.text)),
                  child: Text(texts.startGroup),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pickable extends StatelessWidget {
  const _Pickable({
    required this.person,
    required this.picked,
    required this.onTap,
  });

  final Person person;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(3),
    child: Material(
      color: picked ? const Color(0x268AB4FF) : const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Avatar(person: person, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  person.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onTap == null ? Colors.white30 : Colors.white,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Icon(
                picked
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: picked ? togetherAccent : Colors.white24,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
