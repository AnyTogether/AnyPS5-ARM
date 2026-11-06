import 'package:flutter/material.dart';

import '../chat_strings.dart';
import '../media_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/messages.dart';
import '../together/party_chat.dart';
import '../together/people.dart';
import '../together/together_account.dart';
import '../together/typing.dart';
import 'messages_view.dart';
import 'report_sheet.dart';
import 'together_widgets.dart';

/// The party's chat beside its voice: the thread bottom up, who is typing, the message being
/// answered, and a text-only composer. While it is on screen the chat is read.
class PartyChatPanel extends StatefulWidget {
  const PartyChatPanel({
    super.key,
    required this.chat,
    required this.typing,
    required this.me,
  });

  final PartyChat chat;
  final Typing typing;
  final String? me;

  @override
  State<PartyChatPanel> createState() => _PartyChatPanelState();
}

class _PartyChatPanelState extends State<PartyChatPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  ChatMessage? _reply;

  PartyChat get _chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _chat.show();
    _scroll.addListener(_nearTop);
  }

  @override
  void dispose() {
    _chat.hide();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The thread runs bottom up: near its end are the older messages.
  void _nearTop() {
    if (_scroll.position.extentAfter < 120 && _chat.more) {
      _chat.older().catchError((_) {});
    }
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    final reply = _reply?.conversationId == _chat.id ? _reply : null;
    _text.clear();
    setState(() => _reply = null);
    _chat.send(text, replyTo: reply);
  }

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  /// A name for who wrote: me, someone seen in the party, or a former member.
  String _name(Strings texts, String? userId) => userId == widget.me
      ? texts.messagesYou
      : _chat.author(userId)?.displayName ?? texts.formerMember;

  Person _person(Strings texts, String? userId) =>
      _chat.author(userId) ??
      Person(id: userId ?? '', handle: '', displayName: texts.formerMember);

  Future<void> _actions(ChatMessage message) async {
    final me = widget.me;
    final mine = message.authorId == me;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: const Color(0xFF151821),
      builder: (_) => Texts(
        strings: Texts.of(context),
        child: MessageSheet(
          message: message,
          me: me,
          canEdit: message.canEdit(me),
          canUnsend: mine,
          canReport: !mine,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case MessageReaction reaction:
        await _react(message, reaction);
      case MessageAction.reply:
        setState(() => _reply = message);
        _focus.requestFocus();
      case MessageAction.edit:
        await _edit(message);
      case MessageAction.unsend:
        await _unsend(message);
      case MessageAction.report:
        await reportMessageSheet(
          context,
          send: (reason, note) => _chat.report(message, reason, note: note),
        );
    }
  }

  Future<void> _react(ChatMessage message, MessageReaction reaction) async {
    final texts = Texts.of(context);
    try {
      await _chat.react(message, reaction);
    } on Object catch (error) {
      if (mounted) _say(togetherFailure(texts, error));
    }
  }

  Future<void> _edit(ChatMessage message) async {
    final texts = Texts.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => Texts(
        strings: texts,
        child: EditMessageDialog(text: message.words ?? ''),
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    if (text.trim() == message.words?.trim()) return;
    try {
      await _chat.edit(message, text);
    } on Object catch (error) {
      if (!mounted) return;
      _say(switch (error) {
        TogetherProblem(code: 'edit_limit') ||
        TogetherProblem(status: 403) => texts.editLimit,
        _ => togetherFailure(texts, error),
      });
    }
  }

  Future<void> _unsend(ChatMessage message) async {
    final texts = Texts.of(context);
    if (!await askUnsend(context) || !mounted) return;
    try {
      await _chat.unsend(message);
      if (_reply?.id == message.id) setState(() => _reply = null);
    } on Object catch (error) {
      if (mounted) _say(togetherFailure(texts, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _thread(texts)),
          _typing(texts),
          if (_reply case final reply? when reply.conversationId == _chat.id)
            _replying(texts, reply),
          _composer(texts),
        ],
      ),
    );
  }

  Widget _thread(Strings texts) {
    final me = widget.me;
    if (!_chat.loaded) {
      return SingleChildScrollView(
        child: LoadingOrFailed(
          error: _chat.error,
          retry: () => _chat.load().catchError((_) {}),
        ),
      );
    }
    final thread = _chat.thread.reversed.toList();
    if (thread.isEmpty) return _empty(texts);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      itemCount: thread.length + (_chat.more ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == thread.length) {
          return Center(
            child: TextButton(
              onPressed: () => _chat.older().catchError((_) {}),
              child: Text(texts.messagesEarlier),
            ),
          );
        }
        final message = thread[index];
        final above = index + 1 < thread.length ? thread[index + 1] : null;
        final mine = message.authorId == me;
        return MessageBubble(
          key: ValueKey('party-${message.id}'),
          message: message,
          me: me,
          mine: mine,
          quote: message.replyTo == null || message.deleted
              ? null
              : MessageQuote(
                  key: ValueKey('quote-${message.seq}'),
                  target: _chat.thread
                      .where((m) => m.seq == message.replyTo)
                      .firstOrNull,
                  nameOf: (id) => _name(texts, id),
                  me: me,
                ),
          onActions: message.deleted || message.seq == 0
              ? null
              : () => _actions(message),
          onReact: (reaction) => _react(message, reaction),
          // Names who wrote, once for messages in a row.
          author: !mine && above?.authorId != message.authorId
              ? _person(texts, message.authorId)
              : null,
          onRetry: () => _chat.retry(message),
        );
      },
    );
  }

  /// No message yet: who reads it, under a quiet speech mark.
  Widget _empty(Strings texts) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 26,
                  color: Color(0x668AB4FF),
                ),
                const SizedBox(height: 8),
                Text(
                  texts.partyChatEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// "Ece is typing…" under the thread while someone else is.
  Widget _typing(Strings texts) => ListenableBuilder(
    listenable: widget.typing,
    builder: (context, _) {
      final id = _chat.id;
      final names = [
        if (id != null)
          for (final user in widget.typing.who(id))
            _chat.author(user)?.displayName ?? texts.formerMember,
      ];
      return AnimatedSize(
        duration: const Duration(milliseconds: 160),
        child: names.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                child: Text(
                  texts.typing(names),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
  Widget _replying(Strings texts, ChatMessage reply) => Container(
    margin: const EdgeInsets.only(top: 6),
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
                texts.replyingTo(_name(texts, reply.authorId)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  /// Text only: the party's chat takes no photos.
  Widget _composer(Strings texts) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
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
              hintText: texts.partyChatWrite,
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
              final id = _chat.id;
              if (id != null && text.trim().isNotEmpty) {
                widget.typing.typed(id);
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
