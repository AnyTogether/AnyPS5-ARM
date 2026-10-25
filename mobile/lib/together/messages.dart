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
  );

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
  );
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
  });

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
  );

  final String id;
  final bool group;
  final String? title;
  final List<Person> members;
  final int lastSeq;
  final int readSeq;
  final ChatMessage? lastMessage;
  final DateTime updatedAt;

  int get unread => max(0, lastSeq - readSeq);

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
  }) => Conversation(
    id: id,
    group: group,
    title: title,
    members: members,
    lastSeq: lastSeq ?? this.lastSeq,
    readSeq: readSeq ?? this.readSeq,
    lastMessage: lastMessage ?? this.lastMessage,
    updatedAt: updatedAt ?? this.updatedAt,
  );
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

  String? get _me => account.user?.id;

  Conversation? byId(String? id) =>
      conversations.where((c) => c.id == id).firstOrNull;

  Conversation? get open => byId(openId);

  Future<void> refresh() async {
    final list = await account.call('GET', 'me/conversations');
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

  /// Sends a text to the open conversation; it shows at once and settles when the server has
  /// it.
  Future<void> send(String text) async {
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
    final next = conversation.copyWith(
      lastSeq: max(conversation.lastSeq, message.seq),
      readSeq: mine ? max(conversation.readSeq, message.seq) : null,
      lastMessage: message.seq >= conversation.lastSeq ? message : null,
      updatedAt: message.createdAt,
    );
    if (!mine && message.seq > conversation.lastSeq) unread++;
    conversations = [
      next,
      ...conversations.where((c) => c.id != message.conversationId),
    ];
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
    if (before.readSeq >= upTo) return;
    unread = max(0, unread - before.unread);
    conversations = [
      for (final c in conversations)
        if (c.id == before.id) c.copyWith(readSeq: upTo) else c,
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
        _arrived(ChatMessage.fromJson(data));
      case 'message.updated' || 'message.deleted':
        _changed(ChatMessage.fromJson(data));
      case 'conversation.read' when data['userId'] == _me:
        // Read on another device.
        final id = data['conversationId'];
        final upTo = (data['upToSeq'] as num? ?? 0).toInt();
        conversations = [
          for (final c in conversations)
            if (c.id == id && c.readSeq < upTo)
              c.copyWith(readSeq: upTo)
            else
              c,
        ];
        _countUnread().catchError((_) {});
      case 'conversation.updated':
        if (data['removed'] == true && data['conversationId'] == openId) {
          hide();
        }
        refresh().catchError((_) {});
    }
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
