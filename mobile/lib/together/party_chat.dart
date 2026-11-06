import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'messages.dart';
import 'parties.dart';
import 'people.dart';
import 'reports.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// The text chat beside a party's voice: an ordinary group conversation of the party's
/// members (the party's conversationId), kept apart from the conversation list. It follows the
/// party: joining brings its history, leaving or the party ending takes it away. While shown it
/// is read up to its newest message.
class PartyChat extends ChangeNotifier {
  PartyChat({
    required this.account,
    required this.socket,
    required this.parties,
  }) {
    _events = socket.events.listen(_event);
    parties.addListener(_partyChanged);
    _partyChanged();
  }

  /// The newest messages a new page holds.
  static const page = 40;

  final TogetherAccount account;
  final TogetherSocket socket;
  final Parties parties;
  late final StreamSubscription<TogetherEvent> _events;

  /// The chat of the party this phone is in; null when there is none.
  String? id;

  /// Its messages oldest first, and whether older ones are left.
  List<ChatMessage> thread = const [];
  bool more = false;
  bool loaded = false;

  /// Why the first page did not come, until it does.
  Object? error;

  /// Others' messages not read yet; nothing while the chat is shown.
  int unread = 0;

  bool _shown = false;
  bool _older = false;
  int _readSeq = 0;
  String? _partyId;

  /// Everyone seen in this party while the app ran, so a message from someone who has left
  /// still has their name.
  final _seen = <String, Person>{};

  /// Every party chat this phone had while it ran: a late event for one that ended is still
  /// not the inbox's.
  final _known = <String>{};

  String? get _me => account.user?.id;

  /// A party chat, now or earlier: not a conversation of the list.
  bool owns(String conversationId) => _known.contains(conversationId);

  /// Who wrote a message: someone seen in the party, null for a former member.
  Person? author(String? userId) => userId == null ? null : _seen[userId];

  void _partyChanged() {
    final party = parties.party;
    if (party?.id != _partyId) {
      _partyId = party?.id;
      _seen.clear();
    }
    for (final member in party?.members ?? const <Person>[]) {
      _seen[member.id] = member;
    }
    final next = party?.conversationId;
    if (next == id) return;
    _reset();
    id = next;
    if (next != null) {
      _known.add(next);
      load().catchError((_) {});
    }
    notifyListeners();
  }

  void _reset() {
    id = null;
    thread = const [];
    more = false;
    loaded = false;
    error = null;
    unread = 0;
    _readSeq = 0;
  }

  /// The newest page, and how far this account has read.
  Future<void> load() async {
    final chat = id;
    if (chat == null) return;
    if (error != null) {
      error = null;
      notifyListeners();
    }
    try {
      final view = await account.call('GET', 'conversations/$chat');
      final pageJson = await account.call(
        'GET',
        'conversations/$chat/messages?limit=$page',
      );
      if (id != chat) return;
      for (final member in (view['members'] as List? ?? const [])) {
        if (member is Map<String, dynamic> && member['userId'] is String) {
          final person = Person.fromJson(member);
          _seen.putIfAbsent(person.id, () => person);
        }
      }
      final fetched = messagesOf(pageJson);
      final ids = fetched.map((m) => m.id).toSet();
      thread = [...fetched, ...thread.where((m) => !ids.contains(m.id))]
        ..sort(byPlace);
      more = pageJson['more'] == true;
      _readSeq = (view['readSeq'] as num? ?? _newest).toInt();
      unread = max(0, (view['unread'] as num?)?.toInt() ?? _countUnread());
      loaded = true;
    } on Object catch (problem) {
      if (id == chat) error = problem;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
    if (_shown) await _read();
  }

  int get _newest => thread.where((m) => m.seq > 0).lastOrNull?.seq ?? 0;

  int _countUnread() => thread
      .where(
        (m) => m.seq > _readSeq && m.authorId != _me && !m.deleted && m.seq > 0,
      )
      .length;

  /// The chat is on screen: read up to its newest message, and whatever comes while it is.
  void show() {
    _shown = true;
    // After the frame that put it on screen.
    Future.microtask(_read).catchError((_) {});
  }

  /// Not on screen any more: what comes counts as unread.
  void hide() => _shown = false;

  Future<void> _read() async {
    final chat = id;
    final upTo = _newest;
    if (chat == null || !loaded) return;
    if (unread != 0) {
      unread = 0;
      notifyListeners();
    }
    if (upTo <= _readSeq) return;
    _readSeq = upTo;
    await account.call('POST', 'conversations/$chat/read', {'upToSeq': upTo});
  }

  /// Older messages above the ones shown.
  Future<void> older() async {
    final chat = id;
    final first = thread.where((m) => m.seq > 0).firstOrNull;
    if (chat == null || !more || first == null || _older) return;
    _older = true;
    final Map<String, dynamic> json;
    try {
      json = await account.call(
        'GET',
        'conversations/$chat/messages?limit=$page&before=${first.seq}',
      );
    } finally {
      _older = false;
    }
    if (id != chat) return;
    final known = thread.map((m) => m.id).toSet();
    thread = [
      ...messagesOf(json).where((m) => !known.contains(m.id)),
      ...thread,
    ];
    more = json['more'] == true;
    notifyListeners();
  }

  /// Sends a text, as an answer to [replyTo] when given; it shows at once and settles when the
  /// server has it. The party's chat takes text only.
  Future<void> send(String text, {ChatMessage? replyTo}) async {
    final chat = id;
    final trimmed = text.trim();
    if (chat == null || trimmed.isEmpty) return;
    final message = ChatMessage(
      id: uuidv7(),
      conversationId: chat,
      seq: 0,
      authorId: _me,
      text: trimmed,
      createdAt: DateTime.now(),
      pending: true,
      replyTo: replyTo != null && replyTo.seq > 0 ? replyTo.seq : null,
    );
    thread = [...thread, message];
    notifyListeners();
    await _deliver(message);
  }

  /// Sends again a message that did not get there, with the same id.
  Future<void> retry(ChatMessage message) async {
    final again = message.settling(pending: true);
    _replace(again);
    await _deliver(again);
  }

  Future<void> _deliver(ChatMessage message) async {
    try {
      final json = await account.call(
        'POST',
        'conversations/${message.conversationId}/messages',
        {
          'clientId': message.id,
          'text': message.text,
          if (message.replyTo != null) 'replyTo': message.replyTo,
        },
      );
      _arrived(ChatMessage.fromJson(json));
    } on Object catch (problem) {
      _replace(
        message.settling(
          failed: true,
          problem: problem is TogetherProblem ? problem : null,
        ),
      );
    }
  }

  /// New words for one's own message; the server's copy replaces it.
  Future<void> edit(ChatMessage message, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || message.seq == 0) return;
    final json = await account.call(
      'PATCH',
      'conversations/${message.conversationId}/messages/${message.seq}',
      {'text': trimmed},
    );
    _replace(ChatMessage.fromJson(json));
  }

  /// Takes one's own message back for everyone; its place stays, empty.
  Future<void> unsend(ChatMessage message) async {
    if (message.seq == 0) return;
    await account.call(
      'DELETE',
      'conversations/${message.conversationId}/messages/${message.seq}',
    );
    _replace(message.unsent);
  }

  /// Adds [reaction], or takes it back when it is mine already: shown at once, then as the
  /// server counts it; as it was when the server did not take it.
  Future<void> react(ChatMessage message, MessageReaction reaction) async {
    final me = _me;
    if (message.seq == 0 || message.deleted || me == null) return;
    final mine = message.reacted(reaction, me);
    final before = message.reactions;
    _reactions(message.seq, reactionsToggled(message, reaction, me));
    try {
      final json = await account.call(
        mine ? 'DELETE' : 'PUT',
        'conversations/${message.conversationId}/messages/${message.seq}/reactions/${reaction.name}',
      );
      _reactions(message.seq, ChatMessage.reactionsFrom(json['reactions']));
    } on Object {
      _reactions(message.seq, before);
      rethrow;
    }
  }

  /// Someone else's message, for a moderator to read.
  Future<void> report(
    ChatMessage message,
    ReportReason reason, {
    String? note,
  }) => sendReport(
    account,
    target: ReportTarget.message,
    id: message.id,
    reason: reason,
    note: note,
  );

  void _reactions(int seq, List<ReactionCount> reactions) {
    thread = [
      for (final m in thread)
        if (m.seq == seq) m.withReactions(reactions) else m,
    ];
    notifyListeners();
  }

  void _replace(ChatMessage message) {
    thread = [
      for (final m in thread)
        if (m.id == message.id) message else m,
    ];
    notifyListeners();
  }

  /// A message the server has, sent here or live: into its place once.
  void _arrived(ChatMessage message) {
    final at = thread.indexWhere((m) => m.id == message.id);
    if (at >= 0) {
      thread = [...thread]..[at] = message;
    } else {
      thread = [...thread, message]..sort(byPlace);
      if (message.authorId != _me && message.seq > _readSeq) unread++;
    }
    if (message.authorId == _me) _readSeq = max(_readSeq, message.seq);
    notifyListeners();
    if (_shown) _read().catchError((_) {});
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    final chat = id;
    if (event.type == 'live.ready') {
      if (chat != null) _catchUp(chat).catchError((_) {});
      return;
    }
    if (chat == null || data['conversationId'] != chat) return;
    switch (event.type) {
      case 'message.created':
        _arrived(ChatMessage.fromJson(data));
      case 'message.updated' || 'message.deleted':
        final message = ChatMessage.fromJson(data);
        if (thread.any((m) => m.id == message.id)) _replace(message);
      case 'message.reactions':
        _reactions(
          (data['seq'] as num? ?? 0).toInt(),
          ChatMessage.reactionsFrom(data['reactions']),
        );
      case 'conversation.read' when data['userId'] == _me:
        // Read on another device.
        final upTo = (data['upToSeq'] as num? ?? 0).toInt();
        _readSeq = max(_readSeq, upTo);
        final left = _countUnread();
        if (left != unread) {
          unread = left;
          notifyListeners();
        }
    }
  }

  /// After a reconnect: what came while the socket was away, or the first page when there was
  /// none yet.
  Future<void> _catchUp(String chat) async {
    final last = thread.where((m) => m.seq > 0).lastOrNull;
    if (!loaded || last == null) {
      await load();
      return;
    }
    final json = await account.call(
      'GET',
      'conversations/$chat/messages?limit=100&after=${last.seq}',
    );
    if (id != chat) return;
    messagesOf(json).forEach(_arrived);
  }

  void clear() {
    _reset();
    _partyId = null;
    _seen.clear();
    _shown = false;
    notifyListeners();
  }

  @override
  void dispose() {
    parties.removeListener(_partyChanged);
    _events.cancel();
    super.dispose();
  }
}
