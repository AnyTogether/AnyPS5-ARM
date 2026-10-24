import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/messages.dart';
import '../together/people.dart';
import '../together/together_hub.dart';
import 'together_widgets.dart';

/// Messages: the conversations on the left, the open one on the right with its composer at the
/// bottom, the way a phone held sideways has room for both.
class MessagesPane extends StatefulWidget {
  const MessagesPane({super.key, required this.hub});

  final TogetherHub hub;

  @override
  State<MessagesPane> createState() => _MessagesPaneState();
}

class _MessagesPaneState extends State<MessagesPane> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final Messages _messages = widget.hub.messages;

  @override
  void initState() {
    super.initState();
    if (!_messages.loaded) _messages.refresh().catchError((_) {});
    _scroll.addListener(_nearTop);
  }

  @override
  void dispose() {
    // Not shown any more: what comes in is unread again.
    _messages.hide();
    _text.dispose();
    _scroll.dispose();
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
    _text.clear();
    _messages.send(text);
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
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: Text(
            texts.messages,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
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
                      mine: message.authorId == me,
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
        _composer(texts),
      ],
    );
  }

  Widget _composer(Strings texts) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _text,
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
  });

  final Conversation conversation;
  final String? me;
  final bool selected;
  final VoidCallback onTap;

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
        : '${last.authorId == me ? '${texts.messagesYou}: ' : ''}${last.text ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0x1F8AB4FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
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
                                color: togetherAccent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: const TextStyle(
                                  color: togetherInk,
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
    required this.mine,
    required this.author,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool mine;
  final Person? author;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
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
          Text(
            message.deleted ? texts.messagesDeleted : message.text ?? '',
            style: TextStyle(
              color: message.deleted ? Colors.white38 : Colors.white,
              fontSize: 14.5,
              fontStyle: message.deleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.failed
                ? texts.messagesFailed
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
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: message.pending ? 0.55 : 1,
            child: message.failed
                ? GestureDetector(onTap: onRetry, child: bubble)
                : bubble,
          ),
        ],
      ),
    );
  }
}
