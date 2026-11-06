import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'e2ee.dart';
import 'e2ee.dart' as protocol show open, seal;
import 'e2ee_keys.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// Whether this server and this phone do end-to-end encryption: [unknown] until asked (or
/// while the server cannot be reached), [off] on a server without the routes (everything works
/// as before), [on] once this phone's keys are registered.
enum E2eeAvailability { unknown, off, on }

/// One person's devices as the server lists them, each checked: [active] ones get every new
/// message, [removed] ones only verify their old messages.
class UserDevices {
  const UserDevices({this.active = const [], this.removed = const []});

  static const none = UserDevices();

  final List<PublicDevice> active;
  final List<PublicDevice> removed;

  Iterable<PublicDevice> get all => [...active, ...removed];

  List<String> get ids => [for (final d in active) d.id]..sort();
}

/// What a direct conversation's lock shows. [none]: a group, or no encryption on this server;
/// [checking]: the devices are being fetched; [encrypted]: every message is sealed; [plain]: the
/// other person has no device and the conversation never was encrypted, so it works as before;
/// [noDevice]: it is encrypted but the other person has no device now, so nothing can be sent.
enum ChatLock { none, checking, encrypted, plain, noDevice }

/// Whose devices changed since this conversation last saw them.
enum DevicesNotice { theirs, mine }

class ConversationLock {
  const ConversationLock(
    this.state, {
    this.compared = false,
    this.notice,
    this.other,
  });

  static const none = ConversationLock(ChatLock.none);

  final ChatLock state;

  /// The two people said they compared the safety number (and it has not changed since).
  final bool compared;
  final DevicesNotice? notice;

  /// The other person's user ID.
  final String? other;
}

/// What opening a sealed message gave: its payload, or why not.
class Opened {
  const Opened.payload(Payload this.payload) : error = null;

  const Opened.error(E2eeErrorCode this.error) : payload = null;

  final Payload? payload;
  final E2eeErrorCode? error;
}

/// A direct conversation as end-to-end encryption needs it: its ID, the two people, and whether
/// the server says it has a sealed message in it.
typedef DirectChat = ({String id, String me, String other, bool encrypted});

/// This phone's end-to-end encryption (docs/e2ee.md, "What every client does"): its own keys,
/// made once and kept in the keystore, registered with the server; the people's devices, fetched
/// and checked; what each conversation last saw of them; and opening and sealing messages.
class E2ee extends ChangeNotifier {
  E2ee({
    required this.account,
    required this.socket,
    required this.keys,
    this.deviceName = 'AnyPS5 Remote',
  }) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final String deviceName;

  /// Where this phone's keys are kept.
  final DeviceKeyStore keys;
  late final StreamSubscription<TogetherEvent> _events;

  E2eeAvailability availability = E2eeAvailability.unknown;

  /// This phone's keys for the signed-in person, once registered.
  DeviceSecrets? device;

  bool get on => availability == E2eeAvailability.on && device != null;

  final _devices = <String, UserDevices>{};
  final _verified = <String>{};
  final _opened = <String, Opened>{};
  Future<void>? _starting;
  String? _user;

  /// The conversation on screen: told when a device list it uses changes.
  DirectChat? watched;

  String? get _me => account.user?.id;

  /// Signed in: this phone's keys made (once) and registered. A server without the routes
  /// means no encryption; one that cannot be reached is asked again next time.
  Future<void> start() {
    final user = _me;
    if (user == null) return Future.value();
    if (_user != user) {
      clear();
      _user = user;
    }
    if (availability != E2eeAvailability.unknown) return Future.value();
    return _starting ??= _register(user).whenComplete(() => _starting = null);
  }

  Future<void> _register(String user) async {
    Map<String, dynamic>? current;
    try {
      final json = await account.call('GET', 'me/e2ee/device');
      current = json['device'] is Map<String, dynamic>
          ? json['device'] as Map<String, dynamic>
          : json;
    } on TogetherProblem catch (problem) {
      if (problem.status != 404) return;
    } on Object {
      return;
    }
    final DeviceSecrets secrets;
    try {
      final slot = keySlot(account.base, user);
      final kept = await keys.read(slot);
      if (kept != null) {
        secrets = kept;
      } else {
        secrets = await DeviceSecrets.generate();
        await keys.write(slot, secrets);
        if ((await keys.read(slot))?.deviceId != secrets.deviceId) return;
      }
    } on Object catch (error) {
      // No keystore: no keys kept anywhere else, so no encryption here.
      debugPrint(
        '[anyps5-remote] no keystore for end-to-end encryption: $error',
      );
      _set(E2eeAvailability.off);
      return;
    }
    if (_me != user) return;
    final mine = await publicDevice(secrets, user, name: deviceName);
    if (current?['id'] != mine.id || current?['boxKey'] != mine.boxKey) {
      try {
        await account.call('PUT', 'me/e2ee/device', mine.registration());
      } on TogetherProblem catch (problem) {
        if (problem.status == 404 && current == null) {
          _set(E2eeAvailability.off);
        }
        return;
      } on Object {
        return;
      }
    }
    if (_me != user) return;
    device = secrets;
    _devices.remove(user);
    _set(E2eeAvailability.on);
  }

  void _set(E2eeAvailability next) {
    availability = next;
    notifyListeners();
  }

  /// This phone's keys and the people's devices as a test (or a preview) has them, without
  /// asking a server.
  @visibleForTesting
  void use(DeviceSecrets keys, Map<String, UserDevices> devices) {
    device = keys;
    _devices
      ..clear()
      ..addAll(devices);
    _set(E2eeAvailability.on);
  }

  /// The devices last fetched for [userId]; null before.
  UserDevices? devicesOf(String userId) => _devices[userId];

  /// Fetches the devices of [userIds] (20 at a time, as the server answers) and keeps those that
  /// check out. Someone the server leaves out has none.
  Future<void> fetch(Iterable<String> userIds) async {
    if (!on) return;
    final ids = userIds.toSet().toList();
    for (var at = 0; at < ids.length; at += 20) {
      final part = ids.sublist(at, (at + 20).clamp(0, ids.length));
      final json = await account.call(
        'GET',
        'e2ee/devices?users=${part.map(Uri.encodeQueryComponent).join(',')}',
      );
      final answered = <String>{};
      for (final entry in (json['users'] as List? ?? const [])) {
        if (entry is! Map<String, dynamic>) continue;
        final userId = entry['userId'];
        if (userId is! String || !part.contains(userId)) continue;
        answered.add(userId);
        _devices[userId] = UserDevices(
          active: await _checked(userId, entry['devices']),
          removed: await _checked(userId, entry['removed']),
        );
      }
      for (final userId in part) {
        if (!answered.contains(userId)) _devices[userId] = UserDevices.none;
      }
    }
    notifyListeners();
  }

  /// The devices that are what they say: their ID is their signing key's and their signature
  /// holds for this user. Any other is left out.
  Future<List<PublicDevice>> _checked(String userId, Object? list) async {
    final good = <PublicDevice>[];
    for (final json in (list is List ? list : const [])) {
      if (json is! Map<String, dynamic>) continue;
      final PublicDevice device;
      try {
        device = PublicDevice.fromJson(json);
      } on E2eeError {
        continue;
      }
      final key = '$userId|${device.id}|${device.boxKey}|${device.sig}';
      if (_verified.contains(key) || await verifyDevice(userId, device)) {
        _verified.add(key);
        good.add(device);
      }
    }
    return good;
  }

  // What a conversation last saw

  String get _memoryKey => 'together.e2ee.conversations.$_me';

  Map<String, dynamic> _memory() {
    try {
      final saved = account.preferences.getString(_memoryKey);
      return saved == null
          ? <String, dynamic>{}
          : jsonDecode(saved) as Map<String, dynamic>;
    } on Object {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic>? _record(String conversationId) {
    final record = _memory()[conversationId];
    return record is Map<String, dynamic> ? record : null;
  }

  void _remember(String conversationId, Map<String, dynamic> record) {
    final memory = _memory()..[conversationId] = record;
    account.preferences.setString(_memoryKey, jsonEncode(memory));
  }

  /// This phone saw the conversation encrypted: plain text never goes there again.
  bool seenEncrypted(String conversationId) =>
      _record(conversationId)?['encrypted'] == true;

  void markEncrypted(String conversationId) {
    final record = _record(conversationId) ?? <String, dynamic>{};
    if (record['encrypted'] == true) return;
    _remember(conversationId, {...record, 'encrypted': true});
    notifyListeners();
  }

  /// The lock of a direct conversation as it is known now.
  ConversationLock lockOf(DirectChat chat) {
    if (!on) return ConversationLock.none;
    final theirs = _devices[chat.other];
    final mine = _devices[chat.me];
    final record = _record(chat.id);
    final notice = switch (record?['notice']) {
      'theirs' => DevicesNotice.theirs,
      'mine' => DevicesNotice.mine,
      _ => null,
    };
    if (theirs == null || mine == null) {
      return ConversationLock(ChatLock.checking, other: chat.other);
    }
    final encrypted = chat.encrypted || record?['encrypted'] == true;
    final state = theirs.active.isNotEmpty
        ? ChatLock.encrypted
        : encrypted
        ? ChatLock.noDevice
        : ChatLock.plain;
    return ConversationLock(
      state,
      compared: record?['compared'] == true,
      notice: notice,
      other: chat.other,
    );
  }

  /// Fetches both people's devices and compares them with what this conversation last saw:
  /// the first time it only remembers them; after that a change shows a notice and drops the
  /// "compared" mark.
  Future<void> prepare(DirectChat chat) async {
    if (!on) return;
    if (chat.encrypted) markEncrypted(chat.id);
    await fetch([chat.me, chat.other]);
    observe(chat);
  }

  void observe(DirectChat chat) {
    final theirs = _devices[chat.other]?.ids;
    final mine = _devices[chat.me]?.ids;
    if (theirs == null || mine == null) return;
    final record = _record(chat.id);
    final before = {
      'theirs': (record?['theirs'] as List?)?.cast<String>(),
      'mine': (record?['mine'] as List?)?.cast<String>(),
    };
    bool changed(List<String>? was, List<String> now) =>
        was != null && was.isNotEmpty && !listEquals(was, now);
    final theirsChanged = changed(before['theirs'], theirs);
    final mineChanged = changed(before['mine'], mine);
    final next = <String, dynamic>{...?record, 'theirs': theirs, 'mine': mine};
    if (theirsChanged || mineChanged) {
      next['notice'] = theirsChanged ? 'theirs' : 'mine';
      next['compared'] = false;
    }
    if (jsonEncode(record) != jsonEncode(next)) {
      _remember(chat.id, next);
      notifyListeners();
    }
  }

  void dismissNotice(String conversationId) {
    final record = _record(conversationId);
    if (record == null || record['notice'] == null) return;
    _remember(conversationId, {...record}..remove('notice'));
    notifyListeners();
  }

  /// The two people compared the safety number: marked until it changes.
  void markCompared(String conversationId, {bool compared = true}) {
    final record = {...?_record(conversationId), 'compared': compared};
    if (compared) record.remove('notice');
    _remember(conversationId, record);
    notifyListeners();
  }

  /// The 60 digits both people see; null while either has no device.
  Future<String?> safetyNumberOf(DirectChat chat) async {
    final mine = _devices[chat.me];
    final theirs = _devices[chat.other];
    if (mine == null || theirs == null) return null;
    return safetyNumber(
      (userId: chat.me, signKeys: [for (final d in mine.active) d.signKey]),
      (
        userId: chat.other,
        signKeys: [for (final d in theirs.active) d.signKey],
      ),
    );
  }

  // Messages

  static String _openKey(String messageId, Sealed sealed) =>
      '$messageId|${sealed.sig}';

  /// Opens a sealed message on this phone and checks its author's signature; asked once per
  /// version of it. A device the author added since the list was fetched is fetched first.
  Future<Opened> open({
    required String conversationId,
    required String messageId,
    required String authorId,
    required Sealed sealed,
  }) async {
    final me = device;
    if (me == null) return const Opened.error(E2eeErrorCode.noKey);
    final key = _openKey(messageId, sealed);
    final known = _opened[key];
    if (known != null) return known;
    if (!sealed.keys.containsKey(me.deviceId)) {
      return _opened[key] = const Opened.error(E2eeErrorCode.noKey);
    }
    var authors = _devices[authorId];
    if (authors == null || !authors.all.any((d) => d.id == sealed.device)) {
      try {
        await fetch([authorId]);
      } on Object {
        return const Opened.error(E2eeErrorCode.badMessage);
      }
      authors = _devices[authorId];
    }
    try {
      final payload = await protocol.open(
        sealed,
        conversationId: conversationId,
        messageId: messageId,
        authorId: authorId,
        me: me,
        authorDevices: authors?.all.toList() ?? const [],
      );
      return _opened[key] = Opened.payload(payload);
    } on E2eeError catch (error) {
      return _opened[key] = Opened.error(error.code);
    }
  }

  /// Seals [payload] for every active device of both people of [chat]. The payload is kept, so
  /// the server's copy of it opens without asking again.
  Future<Sealed> seal(
    DirectChat chat,
    String messageId,
    Payload payload,
  ) async {
    final me = device;
    final mine = _devices[chat.me];
    final theirs = _devices[chat.other];
    if (me == null || mine == null || theirs == null || theirs.active.isEmpty) {
      throw const E2eeError(E2eeErrorCode.badDevice);
    }
    final result = await protocol.seal(
      conversationId: chat.id,
      messageId: messageId,
      senderUserId: chat.me,
      sender: me,
      recipients: [...mine.active, ...theirs.active],
      payload: payload,
    );
    _opened[_openKey(messageId, result.sealed)] = Opened.payload(payload);
    return result.sealed;
  }

  /// The content key of a sealed message, as a report sends it.
  Future<String?> contentKeyOf({
    required String conversationId,
    required String messageId,
    required String authorId,
    required Sealed sealed,
  }) async {
    final me = device;
    if (me == null) return null;
    try {
      return toBase64(
        await unwrapKey(
          sealed,
          MessageContext(
            conversationId: conversationId,
            messageId: messageId,
            senderUserId: authorId,
            senderDeviceId: sealed.device,
          ),
          me,
        ),
      );
    } on E2eeError {
      return null;
    }
  }

  void clear() {
    availability = E2eeAvailability.unknown;
    device = null;
    _devices.clear();
    _opened.clear();
    _user = null;
    watched = null;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    switch (event.type) {
      case 'live.ready':
        if (availability == E2eeAvailability.unknown) {
          start().catchError((_) {});
        }
      case 'e2ee.devices':
        final userId = event.json['userId'];
        if (userId is! String || !on) return;
        final chat = watched;
        if (!_devices.containsKey(userId) &&
            chat?.me != userId &&
            chat?.other != userId) {
          return;
        }
        fetch([userId])
            .then((_) {
              final now = watched;
              if (now != null && (now.me == userId || now.other == userId)) {
                observe(now);
              }
            })
            .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
