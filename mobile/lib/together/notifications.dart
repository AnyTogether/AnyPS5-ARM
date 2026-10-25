import 'dart:async';

import 'package:flutter/foundation.dart';

import 'people.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// What a notification can be about; each but [warning] can be turned off.
enum NoticeKind {
  friendRequest('friend_request'),
  friendAccepted('friend_accepted'),
  message('message'),
  partyInvite('party_invite'),
  gameInvite('game_invite'),
  missedCall('missed_call'),
  lfgRequest('lfg_request'),
  lfgAccepted('lfg_accepted'),
  warning('warning');

  const NoticeKind(this.wire);

  /// As the API names it.
  final String wire;

  static NoticeKind? from(Object? value) =>
      values.where((kind) => kind.wire == value).firstOrNull;
}

/// The kinds that can be turned off, in the order the settings show them.
const optionalNoticeKinds = [
  NoticeKind.friendRequest,
  NoticeKind.friendAccepted,
  NoticeKind.message,
  NoticeKind.partyInvite,
  NoticeKind.gameInvite,
  NoticeKind.missedCall,
  NoticeKind.lfgRequest,
  NoticeKind.lfgAccepted,
];

/// One notification under the bell.
class Notice {
  const Notice({
    required this.id,
    required this.kind,
    required this.actor,
    required this.subjectId,
    required this.data,
    required this.read,
    required this.createdAt,
    required this.updatedAt,
  });

  /// null for a kind this app does not know yet.
  static Notice? fromJson(Map<String, dynamic> json) {
    final kind = NoticeKind.from(json['kind']);
    final id = json['id'];
    if (kind == null || id is! String) return null;
    final created =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return Notice(
      id: id,
      kind: kind,
      actor: json['actor'] is Map<String, dynamic>
          ? Person.fromJson(json['actor'] as Map<String, dynamic>)
          : null,
      subjectId: json['subjectId'] as String?,
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : const {},
      read: json['read'] == true,
      createdAt: created,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? created,
    );
  }

  final String id;
  final NoticeKind kind;

  /// Who did it; null for a warning.
  final Person? actor;

  /// A conversation, party, game session or call ID; null for friends.
  final String? subjectId;

  /// message: conversationId, title, group, count, text; party_invite: partyId, size;
  /// game_invite: sessionId, titleId; missed_call: callId; warning: reason; lfg_request:
  /// postId, titleId, gameNames, purpose, count; lfg_accepted: postId, titleId, gameNames,
  /// purpose, invite {kind, id}.
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  /// Later than [createdAt] when more gathered into it (another message).
  final DateTime updatedAt;

  /// How many messages gathered into a message notification.
  int get count => (data['count'] as num? ?? 1).toInt();

  Notice markedRead() => Notice(
    id: id,
    kind: kind,
    actor: actor,
    subjectId: subjectId,
    data: data,
    read: true,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// What the bell tells about (each kind on or off), the mail digest, and whether a digest can
/// be mailed at all (an account with no email gets none).
class NoticeSettings {
  const NoticeSettings({
    required this.kinds,
    required this.digest,
    required this.canMail,
  });

  factory NoticeSettings.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'] is Map
        ? json['settings'] as Map
        : const {};
    return NoticeSettings(
      kinds: {
        for (final kind in optionalNoticeKinds)
          kind: settings[kind.wire] is bool
              ? settings[kind.wire] as bool
              : true,
      },
      digest: settings['digest'] == true,
      canMail: json['canMail'] == true,
    );
  }

  final Map<NoticeKind, bool> kinds;
  final bool digest;
  final bool canMail;
}

/// The notification center on the phone: the list under the bell, newest first a page at a
/// time, the unread count, marking read (here and, through the gateway, on every other device),
/// and what to be told about. No push: a phone notification while the app is closed needs Apple
/// and Firebase set up for this app, which it does not have yet.
class Notifications extends ChangeNotifier {
  Notifications({required this.account, required this.socket}) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final StreamSubscription<TogetherEvent> _events;

  static const pageSize = 30;

  List<Notice> items = const [];
  int unread = 0;
  bool more = false;
  bool loaded = false;
  bool _older = false;

  Future<void> refresh() async {
    final json = await account.call('GET', 'me/notifications?limit=$pageSize');
    items = _page(json);
    unread = (json['unread'] as num? ?? 0).toInt();
    more = json['more'] == true;
    loaded = true;
    notifyListeners();
  }

  Future<void> older() async {
    final last = items.lastOrNull;
    if (!more || last == null || _older) return;
    _older = true;
    try {
      final json = await account.call(
        'GET',
        'me/notifications?limit=$pageSize&before=${last.id}',
      );
      final known = items.map((n) => n.id).toSet();
      items = [...items, ..._page(json).where((n) => !known.contains(n.id))];
      unread = (json['unread'] as num? ?? unread).toInt();
      more = json['more'] == true;
      notifyListeners();
    } finally {
      _older = false;
    }
  }

  /// Only the count, for the bell before the list was opened.
  Future<void> count() async {
    final json = await account.call('GET', 'me/notifications/unread');
    unread = (json['unread'] as num? ?? 0).toInt();
    notifyListeners();
  }

  /// Read, here at once and on the server.
  Future<void> read(Notice notice) async {
    if (notice.read) return;
    _markRead({notice.id});
    unread = unread > 0 ? unread - 1 : 0;
    notifyListeners();
    final json = await account.call(
      'POST',
      'me/notifications/${notice.id}/read',
    );
    unread = (json['unread'] as num? ?? unread).toInt();
    notifyListeners();
  }

  Future<void> readAll() async {
    _markRead(null);
    unread = 0;
    notifyListeners();
    final json = await account.call('POST', 'me/notifications/read-all');
    unread = (json['unread'] as num? ?? 0).toInt();
    notifyListeners();
  }

  Future<NoticeSettings> settings() async => NoticeSettings.fromJson(
    await account.call('GET', 'me/notifications/settings'),
  );

  /// Turns one kind (by its API name, or "digest") on or off; the settings as saved come back.
  Future<NoticeSettings> setting(String key, bool on) async =>
      NoticeSettings.fromJson(
        await account.call('PATCH', 'me/notifications/settings', {key: on}),
      );

  void _markRead(Set<String>? ids) => items = [
    for (final n in items)
      if (!n.read && (ids == null || ids.contains(n.id))) n.markedRead() else n,
  ];

  void clear() {
    items = const [];
    unread = 0;
    more = false;
    loaded = false;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    switch (event.type) {
      case 'live.ready':
        (loaded ? refresh() : count()).catchError((_) {});
      case 'notification':
        final json = data['notification'];
        final notice = json is Map<String, dynamic>
            ? Notice.fromJson(json)
            : null;
        if (notice != null) {
          // A new one goes on top; one that gathered another message moves up.
          items = [notice, ...items.where((n) => n.id != notice.id)];
        }
        unread = (data['unread'] as num? ?? unread).toInt();
        notifyListeners();
      case 'notification.read':
        final ids = data['ids'];
        _markRead(ids is List ? {for (final id in ids) '$id'} : null);
        unread = (data['unread'] as num? ?? unread).toInt();
        notifyListeners();
    }
  }

  static List<Notice> _page(Map<String, dynamic> json) => [
    for (final n in (json['notifications'] as List? ?? const []))
      ?Notice.fromJson(n as Map<String, dynamic>),
  ];

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
