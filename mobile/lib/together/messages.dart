import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'people.dart';
import 'storage.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// A UUIDv7: the time first, then randomness; the id a message is sent with, so a message sent
/// twice is kept once.
String uuidv7([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  final ms = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < 6; i++) {
    bytes[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  bytes[6] = 0x70 | (bytes[6] & 0x0f);
  bytes[8] = 0x80 | (bytes[8] & 0x3f);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// How long after sending one's own message may still be edited, and how many times.
const editWindow = Duration(minutes: 15);
const maxMessageEdits = 20;

/// The most conversations one person keeps pinned at the top of their list.
const maxPinned = 5;

/// The reactions a message can get, one of each per person, in the API's fixed order.
enum MessageReaction {
  like('👍'),
  love('❤️'),
  laugh('😂'),
  wow('😮'),
  sad('😢'),
  fire('🔥'),
  gg('GG');

  const MessageReaction(this.glyph);

  /// How it is drawn: an emoji, or the letters "GG".
  final String glyph;

  static MessageReaction? parse(Object? name) =>
      values.where((r) => r.name == name).firstOrNull;
}

/// One reaction on a message: how many added it, and who.
class ReactionCount {
  const ReactionCount(this.reaction, this.userIds) : count = userIds.length;

  const ReactionCount._(this.reaction, this.count, this.userIds);

  /// Null for a reaction this phone does not know.
  static ReactionCount? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final reaction = MessageReaction.parse(json['reaction']);
    if (reaction == null) return null;
    final userIds = [
      for (final id in (json['userIds'] as List? ?? const []))
        if (id is String) id,
    ];
    return ReactionCount._(
      reaction,
      (json['count'] as num? ?? userIds.length).toInt(),
      userIds,
    );
  }

  final MessageReaction reaction;
  final int count;
  final List<String> userIds;
}

/// One message in a conversation; a deleted one keeps its place with no text. [pending] while
/// it is on its way, [failed] when it did not get there. A message with media has its [kind]
/// and [attachments]; its [text] is then the caption or a stand-in such as "[photo]" for
/// clients that know no media, and [caption] the caption alone.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.seq,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.edited = false,
    this.deleted = false,
    this.pending = false,
    this.failed = false,
    this.problem,
    this.kind = MediaKind.text,
    this.caption,
    this.attachments = const [],
    this.mediaId,
    this.replyTo,
    this.editCount = 0,
    this.reactions = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    conversationId: json['conversationId'] as String,
    seq: (json['seq'] as num).toInt(),
    authorId: json['authorId'] as String?,
    text: json['text'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    edited: json['editedAt'] != null,
    deleted: json['deletedAt'] != null,
    kind: MediaKind.parse(json['kind']),
    caption: json['caption'] as String?,
    attachments: [
      for (final attachment in (json['attachments'] as List? ?? const []))
        if (attachment is Map<String, dynamic>) Attachment.fromJson(attachment),
    ],
    replyTo: (json['replyTo'] as num?)?.toInt(),
    editCount: (json['editCount'] as num? ?? 0).toInt(),
    // An unsent message keeps none.
    reactions: json['deletedAt'] != null
        ? const []
        : reactionsFrom(json['reactions']),
  );

  static List<ReactionCount> reactionsFrom(Object? json) => [
    for (final item in (json is List ? json : const []))
      ?ReactionCount.fromJson(item),
  ];

  final String id;
  final String conversationId;

  /// Its place in the conversation; 0 until the server gave it one.
  final int seq;
  final String? authorId;
  final String? text;
  final DateTime createdAt;
  final bool edited;
  final bool deleted;
  final bool pending;
  final bool failed;

  /// Why it did not get there, as the API said: link_blocked (its extra names the domain),
  /// forbidden (not friends any more); null when it may simply be sent again.
  final TogetherProblem? problem;

  final MediaKind kind;
  final String? caption;
  final List<Attachment> attachments;

  /// A photo from this phone already kept on the server, so sending again does not upload it
  /// twice.
  final String? mediaId;

  /// The seq of the message this one answers, in the same conversation.
  final int? replyTo;

  /// How often it was edited (at most [maxMessageEdits]).
  final int editCount;

  /// Its reactions in the fixed order; none once unsent.
  final List<ReactionCount> reactions;

  /// [me] added this reaction.
  bool reacted(MessageReaction reaction, String? me) => reactions.any(
    (r) => r.reaction == reaction && me != null && r.userIds.contains(me),
  );

  /// One's own text (or caption) on the server, within [editWindow] and under
  /// [maxMessageEdits].
  bool canEdit(String? me, {DateTime? now}) {
    if (me == null || authorId != me || deleted || seq == 0) return false;
    if (editCount >= maxMessageEdits) return false;
    if ((now ?? DateTime.now()).difference(createdAt) >= editWindow) {
      return false;
    }
    return kind == MediaKind.text || (caption?.isNotEmpty ?? false);
  }

  /// The words shown: the text, or a caption under media (never the stand-in).
  String? get words => kind == MediaKind.text
      ? text
      : (caption?.isEmpty ?? true)
      ? null
      : caption;

  /// The same message with other reactions.
  ChatMessage withReactions(List<ReactionCount> reactions) =>
      _copy(reactions: reactions);

  /// The same message unsent: its place kept, nothing in it.
  ChatMessage get unsent => ChatMessage(
    id: id,
    conversationId: conversationId,
    seq: seq,
    authorId: authorId,
    text: null,
    createdAt: createdAt,
    edited: edited,
    deleted: true,
    kind: kind,
    replyTo: replyTo,
    editCount: editCount,
  );

  ChatMessage _copy({List<ReactionCount>? reactions}) => ChatMessage(
    id: id,
    conversationId: conversationId,
    seq: seq,
    authorId: authorId,
    text: text,
    createdAt: createdAt,
    edited: edited,
    deleted: deleted,
    pending: pending,
    failed: failed,
    problem: problem,
    kind: kind,
    caption: caption,
    attachments: attachments,
    mediaId: mediaId,
    replyTo: replyTo,
    editCount: editCount,
    reactions: reactions ?? this.reactions,
  );

  /// Sending it again would only be refused again.
  bool get refused => switch (problem?.code) {
    'link_blocked' ||
    'forbidden' ||
    'quota_exceeded' ||
    'payload_too_large' ||
    'unsupported_media_type' ||
    'bad_image' ||
    'restricted_by_family' ||
    'storage_disabled' => true,
    _ => false,
  };

  /// The same message on its way again, or failed with [problem].
  ChatMessage settling({
    bool pending = false,
    bool failed = false,
    TogetherProblem? problem,
    String? mediaId,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    seq: 0,
    authorId: authorId,
    text: text,
    createdAt: createdAt,
    pending: pending,
    failed: failed,
    problem: problem,
    kind: kind,
    caption: caption,
    attachments: attachments,
    mediaId: mediaId ?? this.mediaId,
    replyTo: replyTo,
  );
}

/// How far another member of a conversation has got: [readSeq] is null unless both share
/// read receipts, [deliveredSeq] null in groups.
class MemberReceipt {
  const MemberReceipt({required this.userId, this.readSeq, this.deliveredSeq});

  factory MemberReceipt.fromJson(Map<String, dynamic> json) => MemberReceipt(
    userId: json['userId'] as String,
    readSeq: (json['readSeq'] as num?)?.toInt(),
    deliveredSeq: (json['deliveredSeq'] as num?)?.toInt(),
  );

  final String userId;
  final int? readSeq;
  final int? deliveredSeq;
}

enum ReceiptKind { sent, delivered, read, seen }

/// Where one's own message has got: sent, delivered or read in a direct chat; seen by
/// [count] in a group, [everyone] when all have.
class Receipt {
  const Receipt(this.kind, {this.count = 0, this.everyone = false});

  final ReceiptKind kind;
  final int count;
  final bool everyone;
}

/// The receipt of [message] in [conversation] for [me]; null for someone else's message, a
/// removed one, one not on the server yet, or an older server without receipts.
Receipt? receiptOf(Conversation conversation, ChatMessage message, String? me) {
  final receipts = conversation.receipts;
  if (me == null ||
      message.authorId != me ||
      message.deleted ||
      message.seq == 0 ||
      receipts == null) {
    return null;
  }
  if (conversation.group) {
    final count = receipts
        .where((r) => r.readSeq != null && r.readSeq! >= message.seq)
        .length;
    return Receipt(
      ReceiptKind.seen,
      count: count,
      everyone: count > 0 && count == receipts.length,
    );
  }
  final other = receipts.firstOrNull;
  if (other == null) return null;
  if ((other.readSeq ?? 0) >= message.seq) {
    return const Receipt(ReceiptKind.read);
  }
  if ((other.deliveredSeq ?? 0) >= message.seq) {
    return const Receipt(ReceiptKind.delivered);
  }
  return const Receipt(ReceiptKind.sent);
}

/// A direct conversation with a friend or a group.
class Conversation {
  const Conversation({
    required this.id,
    required this.group,
    required this.title,
    required this.members,
    required this.lastSeq,
    required this.readSeq,
    required this.lastMessage,
    required this.updatedAt,
    int? unread,
    this.pinned = false,
    this.muted = false,
    this.receipts,
  }) : unread = unread ?? (lastSeq > readSeq ? lastSeq - readSeq : 0);

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    group: json['kind'] == 'group',
    title: json['title'] as String?,
    members: [
      for (final member in (json['members'] as List? ?? const []))
        Person.fromJson(member as Map<String, dynamic>),
    ],
    lastSeq: (json['lastSeq'] as num? ?? 0).toInt(),
    readSeq: (json['readSeq'] as num? ?? 0).toInt(),
    lastMessage: json['lastMessage'] is Map<String, dynamic>
        ? ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
        : null,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    // Counted by the server; worked out from the marks for an older one.
    unread: (json['unread'] as num?)?.toInt(),
    pinned: json['pinned'] == true,
    muted: json['muted'] == true,
    receipts: json['receipts'] is List
        ? [
            for (final r in json['receipts'] as List)
              if (r is Map<String, dynamic>) MemberReceipt.fromJson(r),
          ]
        : null,
  );

  final String id;
  final bool group;
  final String? title;
  final List<Person> members;
  final int lastSeq;
  final int readSeq;
  final ChatMessage? lastMessage;
  final DateTime updatedAt;

  /// Others' messages after [readSeq] that were not unsent.
  final int unread;
  final bool pinned;
  final bool muted;

  /// One for each other member; null from an older server.
  final List<MemberReceipt>? receipts;

  /// Everyone in it but [me].
  List<Person> others(String? me) =>
      members.where((person) => person.id != me).toList();

  /// Its title, or the people in it.
  String name(String? me) =>
      title ??
      (others(me).isEmpty
          ? '…'
          : others(me).map((person) => person.displayName).join(', '));

  Person? author(String? id) =>
      members.where((person) => person.id == id).firstOrNull;

  Conversation copyWith({
    int? lastSeq,
    int? readSeq,
    ChatMessage? lastMessage,
    DateTime? updatedAt,
    int? unread,
    List<MemberReceipt>? receipts,
  }) => Conversation(
    id: id,
    group: group,
    title: title,
    members: members,
    lastSeq: lastSeq ?? this.lastSeq,
    readSeq: readSeq ?? this.readSeq,
    lastMessage: lastMessage ?? this.lastMessage,
    updatedAt: updatedAt ?? this.updatedAt,
    unread: unread ?? this.unread,
    pinned: pinned,
    muted: muted,
    receipts: receipts ?? this.receipts,
  );

  /// After a read or delivered mark from another member: their receipt raised, never lowered.
  Conversation marked(String userId, int upTo, {required bool read}) {
    final list = receipts;
    if (list == null) return this;
    return copyWith(
      receipts: [
        for (final r in list)
          if (r.userId != userId)
            r
          else
            MemberReceipt(
              userId: r.userId,
              readSeq: read ? max(r.readSeq ?? 0, upTo) : r.readSeq,
              // Groups keep no delivered marks.
              deliveredSeq: r.deliveredSeq == null && group
                  ? null
                  : max(r.deliveredSeq ?? 0, upTo),
            ),
      ],
    );
  }
}

/// Pinned conversations first, then the newest; the order given among equals.
List<Conversation> pinnedFirst(Iterable<Conversation> list) {
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      if (a.$2.pinned != b.$2.pinned) return a.$2.pinned ? -1 : 1;
      final byTime = b.$2.updatedAt.compareTo(a.$2.updatedAt);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, c) in indexed) c];
}

/// Messages on the phone: the conversations newest first with what is unread, the one open
/// with its thread, sending (kept once however often it is sent), and everything live.
class Messages extends ChangeNotifier {
  Messages({required this.account, required this.socket}) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final StreamSubscription<TogetherEvent> _events;

  List<Conversation> conversations = const [];

  /// Messages not read yet, over every conversation.
  int unread = 0;
  bool loaded = false;

  /// The conversation shown, its messages oldest first, and whether older ones are left.
  String? openId;
  List<ChatMessage> thread = const [];
  bool more = false;
  bool loadingThread = false;
  bool _older = false;

  /// My own read receipts setting as another device last told it; null until it does.
  bool? readReceipts;

  String? get _me => account.user?.id;

  Conversation? byId(String? id) =>
      conversations.where((c) => c.id == id).firstOrNull;

  Conversation? get open => byId(openId);

  Future<void> refresh() async {
    final list = await account.call('GET', 'me/conversations');
    // The server's order already: pinned first, then the newest.
    conversations = [
      for (final json in (list['conversations'] as List? ?? const []))
        Conversation.fromJson(json as Map<String, dynamic>),
    ];
    loaded = true;
    await _countUnread();
    final shown = open;
    if (shown != null && shown.unread > 0) await _read(shown);
  }

  Future<void> _countUnread() async {
    final count = await account.call('GET', 'me/conversations/unread');
    unread = (count['messages'] as num? ?? 0).toInt();
    notifyListeners();
  }

  /// Shows a conversation: its newest messages, and read up to them.
  Future<void> show(String id) async {
    openId = id;
    thread = const [];
    more = false;
    loadingThread = true;
    notifyListeners();
    try {
      final page = await account.call(
        'GET',
        'conversations/$id/messages?limit=50',
      );
      if (openId != id) return;
      thread = _page(page);
      more = page['more'] == true;
    } finally {
      if (openId == id) {
        loadingThread = false;
        notifyListeners();
      }
    }
    final conversation = byId(id);
    if (conversation != null) await _read(conversation);
  }

  /// Nothing shown any more: new messages count as unread again.
  void hide() {
    openId = null;
    thread = const [];
    more = false;
    notifyListeners();
  }

  /// The conversation with a friend, made the first time, and shown.
  Future<void> withFriend(String userId) async {
    final json = await account.call('POST', 'conversations', {
      'members': [userId],
    });
    final conversation = Conversation.fromJson(json);
    if (byId(conversation.id) == null) {
      conversations = [conversation, ...conversations];
    }
    await show(conversation.id);
  }

  /// Older messages above the ones shown.
  Future<void> older() async {
    final id = openId;
    if (id == null || !more || thread.isEmpty || _older) return;
    _older = true;
    final Map<String, dynamic> page;
    try {
      page = await account.call(
        'GET',
        'conversations/$id/messages?limit=50&before=${thread.first.seq}',
      );
    } finally {
      _older = false;
    }
    if (openId != id) return;
    final known = thread.map((m) => m.id).toSet();
    thread = [..._page(page).where((m) => !known.contains(m.id)), ...thread];
    more = page['more'] == true;
    notifyListeners();
  }

  /// Sends a text to the open conversation, as an answer to [replyTo] when given; it shows at
  /// once and settles when the server has it.
  Future<void> send(String text, {ChatMessage? replyTo}) async {
    final id = openId;
    final trimmed = text.trim();
    if (id == null || trimmed.isEmpty) return;
    final message = ChatMessage(
      id: uuidv7(),
      conversationId: id,
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

  /// Sends a photo (PNG, JPEG or WebP bytes) with an optional caption to the open
  /// conversation: it shows at once from the phone's own bytes, goes up as media, then in a
  /// message.
  Future<void> sendPhoto(Uint8List bytes, {String? caption}) async {
    final id = openId;
    if (id == null || bytes.isEmpty) return;
    final trimmed = caption?.trim();
    final message = ChatMessage(
      id: uuidv7(),
      conversationId: id,
      seq: 0,
      authorId: _me,
      text: trimmed == null || trimmed.isEmpty ? null : trimmed,
      caption: trimmed == null || trimmed.isEmpty ? null : trimmed,
      createdAt: DateTime.now(),
      pending: true,
      kind: MediaKind.image,
      attachments: [Attachment(id: '', kind: MediaKind.image, local: bytes)],
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
    var mediaId = message.mediaId;
    try {
      final local = message.attachments.firstOrNull?.local;
      if (mediaId == null && local != null) {
        mediaId = (await account.uploadImage(local)).id;
      }
      final json = await account.call(
        'POST',
        'conversations/${message.conversationId}/messages',
        {
          'clientId': message.id,
          if (message.text != null) 'text': message.text,
          if (message.replyTo != null) 'replyTo': message.replyTo,
          if (mediaId != null)
            'attachments': [
              {'mediaId': mediaId},
            ],
        },
      );
      _arrived(ChatMessage.fromJson(json));
    } on Object catch (error) {
      _replace(
        message.settling(
          failed: true,
          problem: error is TogetherProblem ? error : null,
          mediaId: mediaId,
        ),
      );
    }
  }

  /// New words for one's own message (or its caption); the server's copy replaces it. A
  /// [TogetherProblem] when it may not be edited any more (403, or 409 edit_limit).
  Future<void> edit(ChatMessage message, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || message.seq == 0) return;
    final json = await account.call(
      'PATCH',
      'conversations/${message.conversationId}/messages/${message.seq}',
      {'text': trimmed},
    );
    _changed(ChatMessage.fromJson(json));
  }

  /// Takes one's own message back for everyone; its place stays, empty.
  Future<void> unsend(ChatMessage message) async {
    if (message.seq == 0) return;
    await account.call(
      'DELETE',
      'conversations/${message.conversationId}/messages/${message.seq}',
    );
    _changed(message.unsent);
  }

  /// Adds [reaction] to a message, or takes it back when it is mine already: shown at once,
  /// then as the server counts it; as it was when the server did not take it.
  Future<void> react(ChatMessage message, MessageReaction reaction) async {
    if (message.seq == 0 || message.deleted) return;
    final me = _me;
    if (me == null) return;
    final mine = message.reacted(reaction, me);
    final before = message.reactions;
    final guess = <ReactionCount>[
      for (final r in MessageReaction.values)
        if (r == reaction)
          ?_toggled(
            before.where((c) => c.reaction == r).firstOrNull,
            r,
            me,
            mine,
          )
        else
          ...before.where((c) => c.reaction == r),
    ];
    _reactions(message.conversationId, message.seq, guess);
    try {
      final json = await account.call(
        mine ? 'DELETE' : 'PUT',
        'conversations/${message.conversationId}/messages/${message.seq}/reactions/${reaction.name}',
      );
      _reactions(
        message.conversationId,
        message.seq,
        ChatMessage.reactionsFrom(json['reactions']),
      );
    } on Object {
      _reactions(message.conversationId, message.seq, before);
      rethrow;
    }
  }

  static ReactionCount? _toggled(
    ReactionCount? count,
    MessageReaction reaction,
    String me,
    bool mine,
  ) {
    final who = [...?count?.userIds];
    mine ? who.remove(me) : who.add(me);
    return who.isEmpty ? null : ReactionCount(reaction, who);
  }

  /// A message's reactions replaced, in the thread and as a conversation's last message.
  void _reactions(
    String conversationId,
    int seq,
    List<ReactionCount> reactions,
  ) {
    bool same(ChatMessage m) =>
        m.conversationId == conversationId && m.seq == seq;
    if (conversationId == openId) {
      thread = [
        for (final m in thread) same(m) ? m.withReactions(reactions) : m,
      ];
    }
    conversations = [
      for (final c in conversations)
        if (c.lastMessage != null && same(c.lastMessage!))
          c.copyWith(lastMessage: c.lastMessage!.withReactions(reactions))
        else
          c,
    ];
    notifyListeners();
  }

  /// Pins a conversation to the top of the list or unpins it. A [TogetherProblem] "full"
  /// when [maxPinned] are pinned already.
  Future<void> pin(String id, bool pinned) =>
      _set(id, 'pin', {'pinned': pinned});

  /// Mutes a conversation's notifications, or unmutes it.
  Future<void> mute(String id, bool muted) =>
      _set(id, 'mute', {'muted': muted});

  Future<void> _set(String id, String what, Map<String, dynamic> body) async {
    final json = await account.call('PUT', 'conversations/$id/$what', body);
    final next = Conversation.fromJson(json);
    conversations = pinnedFirst([
      for (final c in conversations)
        if (c.id == id) next else c,
    ]);
    notifyListeners();
  }

  /// My read receipts setting changed here: the list again, since what others' receipts
  /// show changes with it.
  void receiptsChanged(bool on) {
    readReceipts = on;
    notifyListeners();
    refresh().catchError((_) {});
  }

  void _replace(ChatMessage message) {
    thread = [
      for (final m in thread)
        if (m.id == message.id) message else m,
    ];
    notifyListeners();
  }

  /// A message the server has (sent here, or live from the gateway): into the thread when it is
  /// open, and to the top of the list.
  void _arrived(ChatMessage message) {
    final mine = message.authorId == _me;
    if (message.conversationId == openId) {
      final at = thread.indexWhere((m) => m.id == message.id);
      if (at >= 0) {
        thread = [...thread]..[at] = message;
      } else {
        thread = [...thread, message]..sort(_order);
      }
    }
    final conversation = byId(message.conversationId);
    if (conversation == null) {
      refresh().catchError((_) {});
      notifyListeners();
      return;
    }
    if (message.seq <= conversation.readSeq && !mine) {
      notifyListeners();
      return;
    }
    // Mine is read already; one in the open conversation is read just after.
    final counts = !mine && message.seq > conversation.lastSeq;
    final next = conversation.copyWith(
      lastSeq: max(conversation.lastSeq, message.seq),
      readSeq: mine ? max(conversation.readSeq, message.seq) : null,
      lastMessage: message.seq >= conversation.lastSeq ? message : null,
      updatedAt: message.createdAt,
      unread: mine ? 0 : conversation.unread + (counts ? 1 : 0),
    );
    if (counts) unread++;
    conversations = pinnedFirst([
      next,
      ...conversations.where((c) => c.id != message.conversationId),
    ]);
    notifyListeners();
    if (message.conversationId == openId && !mine) {
      _read(next).catchError((_) {});
    }
  }

  /// An edit or a deletion: changed where it shows, nothing moves.
  void _changed(ChatMessage message) {
    if (message.conversationId == openId) _replace(message);
    conversations = [
      for (final c in conversations)
        if (c.lastMessage?.id == message.id)
          c.copyWith(lastMessage: message)
        else
          c,
    ];
    notifyListeners();
  }

  /// Read up to the newest message, here and on the server.
  Future<void> _read(Conversation conversation) async {
    final before = byId(conversation.id) ?? conversation;
    final upTo = before.lastSeq;
    if (before.readSeq >= upTo && before.unread == 0) return;
    unread = max(0, unread - before.unread);
    conversations = [
      for (final c in conversations)
        if (c.id == before.id) c.copyWith(readSeq: upTo, unread: 0) else c,
    ];
    notifyListeners();
    await account.call('POST', 'conversations/${before.id}/read', {
      'upToSeq': upTo,
    });
  }

  void clear() {
    conversations = const [];
    unread = 0;
    loaded = false;
    openId = null;
    thread = const [];
    more = false;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    switch (event.type) {
      case 'live.ready':
        refresh().then((_) => _catchUp()).catchError((_) {});
      case 'message.created':
        final message = ChatMessage.fromJson(data);
        _arrived(message);
        _delivered(message);
      case 'message.updated':
        _changed(ChatMessage.fromJson(data));
      case 'message.deleted':
        final message = ChatMessage.fromJson(data);
        final conversation = byId(message.conversationId);
        _changed(message);
        // An unread one gone: what is left unread is the server's to count.
        if (conversation != null &&
            message.authorId != _me &&
            message.seq > conversation.readSeq) {
          refresh().catchError((_) {});
        }
      case 'message.reactions':
        _reactions(
          data['conversationId'] as String? ?? '',
          (data['seq'] as num? ?? 0).toInt(),
          ChatMessage.reactionsFrom(data['reactions']),
        );
      case 'conversation.read' when data['userId'] == _me:
        // Read on another device.
        final id = data['conversationId'];
        final upTo = (data['upToSeq'] as num? ?? 0).toInt();
        final left = (data['unread'] as num?)?.toInt();
        conversations = [
          for (final c in conversations)
            if (c.id == id)
              c.copyWith(
                readSeq: max(c.readSeq, upTo),
                unread: left ?? max(0, c.lastSeq - max(c.readSeq, upTo)),
              )
            else
              c,
        ];
        _countUnread().catchError((_) {});
      case 'conversation.read' || 'conversation.delivered':
        // Someone else's mark: their receipt.
        final id = data['conversationId'];
        final user = data['userId'];
        final upTo = (data['upToSeq'] as num?)?.toInt();
        if (user is! String || upTo == null) return;
        conversations = [
          for (final c in conversations)
            if (c.id == id)
              c.marked(user, upTo, read: event.type == 'conversation.read')
            else
              c,
        ];
        notifyListeners();
      case 'messages.settings':
        if (data['readReceipts'] is bool) {
          readReceipts = data['readReceipts'] as bool;
          notifyListeners();
          refresh().catchError((_) {});
        }
      case 'conversation.updated':
        if (data['removed'] == true && data['conversationId'] == openId) {
          hide();
        }
        refresh().catchError((_) {});
    }
  }

  /// Someone else's message in a direct conversation not on screen reached this phone: the
  /// server is told, so its author sees it delivered. (Opening it reads it, which says more.)
  void _delivered(ChatMessage message) {
    final conversation = byId(message.conversationId);
    if (message.authorId == _me ||
        message.seq == 0 ||
        message.conversationId == openId ||
        conversation == null ||
        conversation.group) {
      return;
    }
    account
        .call('POST', 'conversations/${message.conversationId}/delivered', {
          'upToSeq': message.seq,
        })
        .catchError((_) => const <String, dynamic>{});
  }

  /// After a reconnect, the open thread gets what came while the socket was away.
  Future<void> _catchUp() async {
    final id = openId;
    final last = thread.where((m) => m.seq > 0).lastOrNull;
    if (id == null || last == null) return;
    final page = await account.call(
      'GET',
      'conversations/$id/messages?limit=100&after=${last.seq}',
    );
    _page(page).forEach(_arrived);
  }

  static List<ChatMessage> _page(Map<String, dynamic> page) => [
    for (final json in (page['messages'] as List? ?? const []))
      ChatMessage.fromJson(json as Map<String, dynamic>),
  ];

  /// By place in the conversation; the ones still on their way last.
  static int _order(ChatMessage a, ChatMessage b) {
    if (a.seq == 0 || b.seq == 0) return a.seq == 0 ? (b.seq == 0 ? 0 : 1) : -1;
    return a.seq.compareTo(b.seq);
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
