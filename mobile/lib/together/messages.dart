import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'e2ee.dart';
import 'e2ee_devices.dart';
import 'people.dart';
import 'photo_clean.dart';
import 'sealed_media.dart';
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

/// Where a sealed message is on this phone: [plain] for one that is not sealed, [opening] until
/// it is opened, [open] when it opened and its author's signature holds, [noKey] when it was sent
/// before this phone was added, [failed] for anything else (it is never shown as plain text).
enum SealState { plain, opening, open, noKey, failed }

/// One message in a conversation; a deleted one keeps its place with no text. [pending] while
/// it is on its way, [failed] when it did not get there. A message with media has its [kind]
/// and [attachments]; its [text] is then the caption or a stand-in such as "[photo]" for
/// clients that know no media, and [caption] the caption alone. A sealed one (end-to-end
/// encrypted) has its text and the keys of its media in [sealed], and shows them once opened.
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
    this.sealed,
    this.seal = SealState.plain,
    this.payload,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final deleted = json['deletedAt'] != null;
    Sealed? sealed;
    var seal = SealState.plain;
    if (json['sealed'] != null && !deleted) {
      try {
        sealed = Sealed.fromJson(json['sealed']);
        seal = SealState.opening;
      } on E2eeError {
        seal = SealState.failed;
      }
    }
    final plain = seal == SealState.plain;
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      seq: (json['seq'] as num).toInt(),
      authorId: json['authorId'] as String?,
      // A sealed message's text is only the stand-in for older apps.
      text: plain ? json['text'] as String? : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      edited: json['editedAt'] != null,
      deleted: deleted,
      kind: MediaKind.parse(json['kind']),
      caption: plain ? json['caption'] as String? : null,
      attachments: [
        for (final attachment in (json['attachments'] as List? ?? const []))
          if (attachment is Map<String, dynamic>)
            Attachment.fromJson(attachment),
      ],
      replyTo: (json['replyTo'] as num?)?.toInt(),
      editCount: (json['editCount'] as num? ?? 0).toInt(),
      // An unsent message keeps none.
      reactions: deleted ? const [] : reactionsFrom(json['reactions']),
      sealed: sealed,
      seal: seal,
    );
  }

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

  /// End-to-end encrypted: as the server keeps it.
  final Sealed? sealed;
  final SealState seal;

  /// What it says once opened (or, on its way from this phone, what is sealed for it, with the
  /// photo's keys once it is uploaded).
  final Payload? payload;

  /// A sealed message that this phone cannot show: no key, or it did not open.
  bool get unreadable => seal == SealState.noKey || seal == SealState.failed;

  /// [me] added this reaction.
  bool reacted(MessageReaction reaction, String? me) => reactions.any(
    (r) => r.reaction == reaction && me != null && r.userIds.contains(me),
  );

  /// One's own text (or caption) on the server, within [editWindow] and under
  /// [maxMessageEdits]; a sealed one only once it is open here.
  bool canEdit(String? me, {DateTime? now}) {
    if (me == null || authorId != me || deleted || seq == 0) return false;
    if (sealed != null && seal != SealState.open) return false;
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

  /// A sealed message opened: its words and the keys of its media from [payload]. Media named
  /// in the payload that is not the message's own does not open.
  ChatMessage opened(Payload payload) {
    final keys = payload.attachment;
    final media = attachments.firstOrNull;
    if (keys != null && (media == null || media.id != keys.mediaId)) {
      return withSeal(SealState.failed);
    }
    if (keys == null && attachments.isNotEmpty) {
      return withSeal(SealState.failed);
    }
    final words = payload.text?.isEmpty ?? true ? null : payload.text;
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      seq: seq,
      authorId: authorId,
      text: words,
      createdAt: createdAt,
      edited: edited,
      deleted: deleted,
      pending: pending,
      failed: failed,
      problem: problem,
      kind: keys == null ? MediaKind.text : MediaKind.parse(keys.kind),
      caption: keys == null ? null : words,
      attachments: [
        if (media != null && keys != null)
          media.local != null ? media : media.opened(keys),
      ],
      mediaId: mediaId,
      replyTo: replyTo,
      editCount: editCount,
      reactions: reactions,
      sealed: sealed,
      seal: SealState.open,
      payload: payload,
    );
  }

  /// The same sealed message, not (or not yet) opened.
  ChatMessage withSeal(SealState seal) => _copy(seal: seal);

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

  ChatMessage _copy({List<ReactionCount>? reactions, SealState? seal}) =>
      ChatMessage(
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
        sealed: sealed,
        seal: seal ?? this.seal,
        payload: payload,
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

  /// The same message on its way again, or failed with [problem]; [payload] once a photo is
  /// sealed and uploaded, so sending again does not upload it twice.
  ChatMessage settling({
    bool pending = false,
    bool failed = false,
    TogetherProblem? problem,
    String? mediaId,
    Payload? payload,
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
    payload: payload ?? this.payload,
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
    this.encrypted = false,
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
    encrypted: json['encrypted'] == true,
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

  /// A direct conversation with an end-to-end encrypted message in it, as the server says.
  final bool encrypted;

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
    encrypted: encrypted,
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
/// with its thread, sending (kept once however often it is sent), and everything live. In a
/// direct conversation where both people have a device key, every message is sealed on this
/// phone and opened here ([e2ee]); without it, everything works as before.
class Messages extends ChangeNotifier {
  Messages({required this.account, required this.socket, this.e2ee}) {
    _events = socket.events.listen(_event);
    e2ee?.addListener(_e2eeChanged);
  }

  final TogetherAccount account;
  final TogetherSocket socket;

  /// End-to-end encryption; null where there is none (tests of other things).
  final E2ee? e2ee;
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

  /// How often a sealed message is sealed again after the server said the devices changed.
  static const sealTries = 3;

  String? get _me => account.user?.id;

  Conversation? byId(String? id) =>
      conversations.where((c) => c.id == id).firstOrNull;

  Conversation? get open => byId(openId);

  // End-to-end encryption

  /// A direct conversation as encryption sees it; null for a group.
  DirectChat? chatOf(Conversation? conversation) {
    final me = _me;
    if (conversation == null || conversation.group || me == null) return null;
    final others = conversation.others(me);
    if (others.length != 1) return null;
    return (
      id: conversation.id,
      me: me,
      other: others.single.id,
      encrypted: conversation.encrypted,
    );
  }

  /// The lock a conversation shows; [ConversationLock.none] for a group or without encryption.
  ConversationLock lockOf(Conversation? conversation) {
    final chat = chatOf(conversation);
    final e = e2ee;
    if (chat == null || e == null) return ConversationLock.none;
    return e.lockOf(chat);
  }

  E2eeAvailability? _availability;

  void _e2eeChanged() {
    final now = e2ee?.availability;
    if (now != _availability) {
      _availability = now;
      _openAgain().catchError((_) {});
    }
    notifyListeners();
  }

  /// Encryption came on (or turned out to be off): what waited to be opened is opened now.
  Future<void> _openAgain() async {
    final id = openId;
    final chat = chatOf(open);
    if (chat != null) {
      e2ee?.watched = chat;
      await e2ee?.prepare(chat).catchError((_) {});
    }
    if (id != null && openId == id) {
      final before = thread;
      final opened = await _revealAll(before);
      if (openId == id && identical(thread, before)) thread = opened;
    }
    conversations = await _revealLast(conversations);
    notifyListeners();
  }

  /// A sealed message opened on this phone; any other message as it is. Not opened yet while
  /// encryption is still being set up.
  Future<ChatMessage> _reveal(ChatMessage message) async {
    final sealed = message.sealed;
    if (sealed == null || message.seal != SealState.opening) return message;
    final e = e2ee;
    if (e == null || e.availability == E2eeAvailability.off) {
      return message.withSeal(SealState.failed);
    }
    if (!e.on) return message;
    final author = message.authorId;
    if (author == null) return message.withSeal(SealState.failed);
    e.markEncrypted(message.conversationId);
    final opened = await e.open(
      conversationId: message.conversationId,
      messageId: message.id,
      authorId: author,
      sealed: sealed,
    );
    final payload = opened.payload;
    if (payload != null) return message.opened(payload);
    return message.withSeal(
      opened.error == E2eeErrorCode.noKey ? SealState.noKey : SealState.failed,
    );
  }

  Future<List<ChatMessage>> _revealAll(List<ChatMessage> messages) async {
    if (!messages.any((m) => m.seal == SealState.opening)) return messages;
    return [for (final m in messages) await _reveal(m)];
  }

  /// The conversations with their last messages opened, the authors' devices fetched at once.
  Future<List<Conversation>> _revealLast(List<Conversation> list) async {
    final waiting = [
      for (final c in list)
        if (c.lastMessage?.seal == SealState.opening) c,
    ];
    final e = e2ee;
    // The list as it is now: it may have changed while this waited.
    if (waiting.isEmpty || e == null) return conversations;
    if (e.on) {
      final unknown = {
        for (final c in waiting)
          if (c.lastMessage!.authorId case final author?)
            if (e.devicesOf(author) == null) author,
      };
      if (unknown.isNotEmpty) await e.fetch(unknown).catchError((_) {});
    }
    final opened = <String, ChatMessage>{
      for (final c in waiting) c.id: await _reveal(c.lastMessage!),
    };
    return [
      for (final c in conversations)
        if (opened[c.id] case final last?
            when c.lastMessage?.id == last.id &&
                c.lastMessage?.seal == SealState.opening)
          c.copyWith(lastMessage: last)
        else
          c,
    ];
  }

  /// Gateway events and answers handled in the order they came, a sealed one once it is open.
  Future<void> _queue = Future.value();

  void _inOrder(ChatMessage message, void Function(ChatMessage) then) {
    if (message.seal != SealState.opening) {
      _queue = _queue.then((_) => then(message));
      return;
    }
    _queue = _queue
        .then((_) async => then(await _reveal(message)))
        .catchError((Object _) {});
  }

  /// Opening a direct conversation: both people's devices, checked against what it last saw.
  Future<void> _prepare(Conversation conversation) async {
    final chat = chatOf(conversation);
    final e = e2ee;
    if (chat == null || e == null) return;
    e.watched = chat;
    if (!e.on) return;
    try {
      await e.prepare(chat);
    } on Object {
      // Fetched again before anything is sent.
    }
  }

  // The list and the thread

  Future<void> refresh() async {
    final list = await account.call('GET', 'me/conversations');
    // The server's order already: pinned first, then the newest.
    conversations = [
      for (final json in (list['conversations'] as List? ?? const []))
        Conversation.fromJson(json as Map<String, dynamic>),
    ];
    loaded = true;
    conversations = await _revealLast(conversations);
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
    final conversation = byId(id);
    try {
      final page = await account.call(
        'GET',
        'conversations/$id/messages?limit=50',
      );
      if (openId != id) return;
      final messages = _page(page);
      if (conversation != null &&
          (conversation.encrypted || messages.any((m) => m.sealed != null))) {
        e2ee?.markEncrypted(id);
      }
      if (conversation != null) await _prepare(conversation);
      final opened = await _revealAll(messages);
      if (openId != id) return;
      // Anything that came live while this was opening stays.
      final known = {for (final m in opened) m.id};
      thread = [...opened, ...thread.where((m) => !known.contains(m.id))]
        ..sort(_order);
      more = page['more'] == true;
    } finally {
      if (openId == id) {
        loadingThread = false;
        notifyListeners();
      }
    }
    final now = byId(id);
    if (now != null) await _read(now);
  }

  /// Nothing shown any more: new messages count as unread again.
  void hide() {
    openId = null;
    thread = const [];
    more = false;
    e2ee?.watched = null;
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
    final List<ChatMessage> page;
    final bool left;
    try {
      final json = await account.call(
        'GET',
        'conversations/$id/messages?limit=50&before=${thread.first.seq}',
      );
      left = json['more'] == true;
      page = await _revealAll(_page(json));
    } finally {
      _older = false;
    }
    if (openId != id) return;
    final known = thread.map((m) => m.id).toSet();
    thread = [...page.where((m) => !known.contains(m.id)), ...thread];
    more = left;
    notifyListeners();
  }

  // Sending

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
  /// message. Sealed, it is drawn again without its metadata and encrypted before it goes up.
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

  /// Sealed or plain, as the conversation is: sealed when both people have a device; never
  /// plain where this phone saw it encrypted.
  Future<void> _deliver(ChatMessage message) async {
    var sending = message;
    try {
      final chat = chatOf(byId(message.conversationId));
      final e = e2ee;
      if (chat != null && e != null) {
        final sealedBefore = chat.encrypted || e.seenEncrypted(chat.id);
        if (!e.on && sealedBefore) await e.start();
        if (e.on) {
          var lock = e.lockOf(chat);
          if (lock.state == ChatLock.checking) {
            await e.prepare(chat);
            lock = e.lockOf(chat);
          }
          if (lock.state == ChatLock.encrypted) {
            sending = await _deliverSealed(message, chat);
            return;
          }
          if (lock.state == ChatLock.noDevice) throw _noDevice;
        } else if (sealedBefore) {
          throw _noDevice;
        }
      }
      try {
        sending = await _deliverPlain(message);
      } on TogetherProblem catch (problem) {
        if (problem.code != 'e2ee_required' || chat == null || e == null) {
          rethrow;
        }
        // Encrypted after all (on another device, or by the other person).
        e.markEncrypted(chat.id);
        if (!e.on) throw _noDevice;
        await e.prepare(chat);
        if (e.lockOf(chat).state != ChatLock.encrypted) throw _noDevice;
        sending = await _deliverSealed(sending, chat);
      }
    } on Object catch (error) {
      final now = thread.where((m) => m.id == message.id).firstOrNull;
      _replace(
        message.settling(
          failed: true,
          problem: error is TogetherProblem ? error : null,
          mediaId: now?.mediaId ?? sending.mediaId,
          payload: now?.payload ?? sending.payload,
        ),
      );
    }
  }

  static const _noDevice = TogetherProblem(409, 'e2ee_no_device', '');

  /// The message as it was before encryption: text, or the photo uploaded as plain media.
  /// Returns the message with its media ID once uploaded.
  Future<ChatMessage> _deliverPlain(ChatMessage message) async {
    var mediaId = message.mediaId;
    final local = message.attachments.firstOrNull?.local;
    if (mediaId == null && local != null) {
      mediaId = (await account.uploadImage(local)).id;
      message = message.settling(pending: true, mediaId: mediaId);
      _replace(message);
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
    return message;
  }

  /// The message sealed on this phone: a photo drawn again without its metadata, encrypted and
  /// uploaded first (once), then the text and the photo's keys sealed for every device of both.
  Future<ChatMessage> _deliverSealed(
    ChatMessage message,
    DirectChat chat,
  ) async {
    var payload = message.payload ?? Payload(text: message.text);
    final local = message.attachments.firstOrNull?.local;
    if (local != null && payload.attachment == null) {
      final clean = await cleanPhoto(local);
      if (clean == null) {
        throw const TogetherProblem(400, 'bad_image', 'Not a picture');
      }
      final file = await sealFile(clean.bytes, FilePart.file);
      final media = await uploadSealedMedia(
        account,
        MediaKind.image,
        file.ciphertext,
      );
      payload = Payload(
        text: message.text,
        attachment: SealedAttachment(
          mediaId: media.id,
          kind: MediaKind.image.name,
          type: clean.type,
          size: clean.bytes.length,
          key: file.key,
          nonce: file.nonce,
          width: clean.width,
          height: clean.height,
        ),
      );
      message = message.settling(
        pending: true,
        mediaId: media.id,
        payload: payload,
      );
      _replace(message);
    }
    final mediaId = payload.attachment?.mediaId;
    final json = await _sealedCall(
      chat,
      message.id,
      payload,
      (sealed) => account.call(
        'POST',
        'conversations/${message.conversationId}/messages',
        {
          'clientId': message.id,
          'sealed': sealed.toJson(),
          if (message.replyTo != null) 'replyTo': message.replyTo,
          if (mediaId != null)
            'attachments': [
              {'mediaId': mediaId},
            ],
        },
      ),
    );
    _arrived(await _reveal(ChatMessage.fromJson(json)));
    return message;
  }

  /// Seals [payload] for the devices both people have now and sends it; when the server says
  /// they changed (409 e2ee_devices), fetches them again, shows the change and seals again, a few
  /// times at most.
  Future<Map<String, dynamic>> _sealedCall(
    DirectChat chat,
    String messageId,
    Payload payload,
    Future<Map<String, dynamic>> Function(Sealed sealed) send,
  ) async {
    final e = e2ee!;
    for (var attempt = 1; ; attempt++) {
      if (e.lockOf(chat).state != ChatLock.encrypted) throw _noDevice;
      final sealed = await e.seal(chat, messageId, payload);
      try {
        return await send(sealed);
      } on TogetherProblem catch (problem) {
        if (problem.code != 'e2ee_devices' || attempt >= sealTries) rethrow;
        await e.fetch([chat.me, chat.other]);
        e.observe(chat);
      }
    }
  }

  /// New words for one's own message (or its caption); the server's copy replaces it. A
  /// [TogetherProblem] when it may not be edited any more (403, or 409 edit_limit). A sealed
  /// message is sealed again with the new words.
  Future<void> edit(ChatMessage message, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || message.seq == 0) return;
    if (message.sealed != null) {
      final chat = chatOf(byId(message.conversationId));
      final e = e2ee;
      if (chat == null || e == null || !e.on) throw _noDevice;
      if (e.lockOf(chat).state == ChatLock.checking) await e.prepare(chat);
      final json = await _sealedCall(
        chat,
        message.id,
        Payload(text: trimmed, attachment: message.payload?.attachment),
        (sealed) => account.call(
          'PATCH',
          'conversations/${message.conversationId}/messages/${message.seq}',
          {'sealed': sealed.toJson()},
        ),
      );
      _changed(await _reveal(ChatMessage.fromJson(json)));
      return;
    }
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

  /// Reports someone's message to the moderators for [reason] (the API's reasons). A sealed one
  /// goes with its content key, so they can read it and check its author's signature.
  Future<void> report(ChatMessage message, String reason) async {
    String? contentKey;
    final sealed = message.sealed;
    if (sealed != null) {
      final author = message.authorId;
      contentKey = author == null
          ? null
          : await e2ee?.contentKeyOf(
              conversationId: message.conversationId,
              messageId: message.id,
              authorId: author,
              sealed: sealed,
            );
      if (contentKey == null) {
        throw const TogetherProblem(400, 'e2ee_no_key', 'No key here');
      }
    }
    await account.call('POST', 'reports', {
      'targetKind': 'message',
      'targetId': message.id,
      'reason': reason,
      'contentKey': ?contentKey,
    });
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
    var next = Conversation.fromJson(json);
    final before = byId(id)?.lastMessage;
    if (before != null && next.lastMessage?.id == before.id) {
      // Opened here already.
      next = next.copyWith(lastMessage: before);
    }
    conversations = pinnedFirst([
      for (final c in conversations)
        if (c.id == id) next else c,
    ]);
    notifyListeners();
    if (next.lastMessage?.seal == SealState.opening) {
      conversations = await _revealLast(conversations);
      notifyListeners();
    }
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
        if (message.seal == SealState.plain) {
          _arrived(message);
          _delivered(message);
        } else {
          _delivered(message);
          e2ee?.markEncrypted(message.conversationId);
          _inOrder(message, _arrived);
        }
      case 'message.updated':
        final message = ChatMessage.fromJson(data);
        if (message.seal == SealState.plain) {
          _changed(message);
        } else {
          _inOrder(message, _changed);
        }
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
    (await _revealAll(_page(page))).forEach(_arrived);
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

  bool _disposed = false;

  /// Answers and openings still on their way after the hub went are dropped.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _events.cancel();
    e2ee?.removeListener(_e2eeChanged);
    super.dispose();
  }
}
