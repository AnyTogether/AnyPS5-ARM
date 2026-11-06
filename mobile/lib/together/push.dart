import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';
import 'people.dart';
import 'together_account.dart';

/// This phone's push token: an APNs device token (with the app's bundle ID and whether the build
/// uses Apple's development push service) or an FCM registration token.
class PushToken {
  const PushToken({required this.token, this.app, this.sandbox = false});

  final String token;
  final String? app;
  final bool sandbox;
}

enum PushPermission { granted, denied, undetermined }

/// What a tap on a push opens: a notification, or a friend's call (answered or declined from the
/// notification's own buttons, or just opened).
sealed class PushOpen {
  const PushOpen();
}

class NoticeOpened extends PushOpen {
  const NoticeOpened(this.notice, this.kind);

  /// null for a kind this app does not know: the list opens then.
  final Notice? notice;
  final String kind;
}

enum CallAction { open, answer, decline }

class CallOpened extends PushOpen {
  const CallOpened(this.callId, this.from, this.action);

  final String callId;
  final Person from;
  final CallAction action;
}

/// What a push carries, back as a tap; null when it is not one of ours.
PushOpen? pushOpenOf(Map<Object?, Object?> payload) {
  final kind = payload['kind'];
  final action = switch (payload['action']) {
    'answer' => CallAction.answer,
    'decline' => CallAction.decline,
    _ => CallAction.open,
  };
  if (kind == 'call' || kind == 'missed_call') {
    final callId = payload['callId'];
    final from = _json(payload['caller']);
    if (callId is! String || from == null) return null;
    final person = Person.fromJson(from);
    return kind == 'call'
        ? CallOpened(callId, person, action)
        : NoticeOpened(
            Notice(
              id: callId,
              kind: NoticeKind.missedCall,
              actor: person,
              subjectId: callId,
              data: {'callId': callId},
              // Nothing to mark read: the bell's own one is read when the list opens.
              read: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            'missed_call',
          );
  }
  if (kind is! String) return null;
  final notice = _json(payload['notice']);
  return NoticeOpened(notice == null ? null : Notice.fromJson(notice), kind);
}

Map<String, dynamic>? _json(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is! String) return null;
  try {
    final parsed = jsonDecode(value);
    return parsed is Map<String, dynamic> ? parsed : null;
  } on FormatException {
    return null;
  }
}

/// The phone's side of push: the token, the permission, and the taps. The app's own code on
/// iPhone (APNs) and Android (Firebase Cloud Messaging) answers it.
abstract class PushChannel {
  /// apns or fcm.
  String get platform;

  /// null when this build or this phone cannot be pushed to (no Firebase project in the build,
  /// no push entitlement, no Google Play services).
  Future<PushToken?> token();
  Future<PushPermission> permission();

  /// Asks the person (the system's own question); true when allowed.
  Future<bool> ask();

  /// The tap that started the app, once.
  Future<Map<Object?, Object?>?> launchedWith();

  /// Taps while the app runs, and renewed tokens.
  Stream<Map<Object?, Object?>> get taps;
  Stream<String> get renewed;

  /// Takes a call's ringing notification away (the app shows the call itself).
  Future<void> clearCall(String callId);

  /// The app icon's count: what is unread now.
  Future<void> badge(int count);
}

/// The app's own code on the phone, over org.anyps5.remote/push.
class PlatformPushChannel implements PushChannel {
  bool _handling = false;

  /// Hears the app's own code from the first use on (not when made: a test has no binding).
  void _hear() {
    if (_handling) return;
    _handling = true;
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      switch (call.method) {
        case 'opened' when arguments is Map:
          _taps.add(arguments);
        case 'token' when arguments is String:
          _renewed.add(arguments);
      }
    });
  }

  static const _channel = MethodChannel('org.anyps5.remote/push');
  final _taps = StreamController<Map<Object?, Object?>>.broadcast();
  final _renewed = StreamController<String>.broadcast();

  @override
  String get platform => Platform.isIOS ? 'apns' : 'fcm';

  @override
  Future<PushToken?> token() async {
    _hear();
    final answer = await _channel.invokeMapMethod<String, Object?>('token');
    final token = answer?['token'];
    if (token is! String || token.isEmpty) return null;
    return PushToken(
      token: token,
      app: answer?['app'] as String?,
      sandbox: answer?['sandbox'] == true,
    );
  }

  @override
  Future<PushPermission> permission() async =>
      switch (await _channel.invokeMethod<String>('permission')) {
        'granted' => PushPermission.granted,
        'denied' => PushPermission.denied,
        _ => PushPermission.undetermined,
      };

  @override
  Future<bool> ask() async =>
      await _channel.invokeMethod<bool>('ask') ?? false;

  @override
  Future<Map<Object?, Object?>?> launchedWith() async {
    _hear();
    return _channel.invokeMethod<Map<Object?, Object?>>('launchedWith');
  }

  @override
  Stream<Map<Object?, Object?>> get taps => _taps.stream;

  @override
  Stream<String> get renewed => _renewed.stream;

  @override
  Future<void> clearCall(String callId) =>
      _channel.invokeMethod<void>('clearCall', {'callId': callId});

  @override
  Future<void> badge(int count) =>
      _channel.invokeMethod<void>('badge', {'count': count});
}

/// Push on this phone: messages, invites and calls while the app is closed or the phone is
/// locked. It works when the server pushes to this platform (and, on an iPhone, to this app)
/// and the build can get a token. The person is asked once they reach out to someone (a message,
/// a friend request, a party, a call), never at the first start; "Not now" waits a week, and
/// after three the app stops offering. Turned off here, this phone's token is taken back.
class PhonePush extends ChangeNotifier {
  PhonePush({
    required this.account,
    required this.notifications,
    PushChannel? channel,
    this.language,
    DateTime Function()? clock,
  }) : _channel = channel ?? PlatformPushChannel(),
       _clock = clock ?? DateTime.now {
    notifications.addListener(_unreadChanged);
  }

  final TogetherAccount account;
  final Notifications notifications;
  final PushChannel _channel;
  final DateTime Function() _clock;

  /// The language pushes come in (the phone's): en or tr.
  final String Function()? language;

  SharedPreferences get _preferences => account.preferences;

  static const _offKey = 'push.off';
  static const _laterKey = 'push.later';
  static const _laterCountKey = 'push.laterCount';
  static const waitAfterLater = Duration(days: 7);
  static const offersAtMost = 3;

  /// The server pushes to this phone and the build can.
  bool available = false;
  PushPermission permission = PushPermission.undetermined;

  /// This phone's token is with the server: pushes come.
  bool registered = false;

  /// The question about turning push on is showing.
  bool offering = false;

  PushToken? _token;
  StreamSubscription<Map<Object?, Object?>>? _taps;
  StreamSubscription<String>? _renewals;
  final _opens = StreamController<PushOpen>.broadcast();
  bool _started = false;

  /// Taps on pushes, the one that started the app among them.
  Stream<PushOpen> get opens => _opens.stream;

  /// Turned off on this phone by the person.
  bool get turnedOff => _preferences.getBool(_offKey) ?? false;

  /// After sign-in, and whenever the app starts signed in: is push possible here, and is it on.
  Future<void> start() async {
    if (account.user == null) return;
    _listen();
    try {
      _token = await _channel.token();
    } on Object {
      _token = null;
    }
    if (_token == null) return _set(available: false);
    final Map<String, dynamic> settings;
    try {
      settings = await account.call('GET', 'me/notifications/settings');
    } on Object {
      return;
    }
    final native = settings['native'];
    final can = native is Map &&
        (_channel.platform == 'apns'
            ? (native['apns'] as List? ?? const []).contains(_token!.app)
            : native['fcm'] == true);
    if (!can) return _set(available: false);
    try {
      permission = await _channel.permission();
    } on Object {
      permission = PushPermission.undetermined;
    }
    available = true;
    if (permission == PushPermission.granted && !turnedOff) {
      await _register();
    } else {
      notifyListeners();
    }
  }

  void _set({required bool available}) {
    this.available = available;
    offering = false;
    notifyListeners();
  }

  void _listen() {
    if (_started) return;
    _started = true;
    _taps = _channel.taps.listen((payload) {
      final open = pushOpenOf(payload);
      if (open != null) _opens.add(open);
    });
    _renewals = _channel.renewed.listen((token) {
      final known = _token;
      _token = PushToken(
        token: token,
        app: known?.app,
        sandbox: known?.sandbox ?? false,
      );
      if (registered) _register().catchError((_) {});
    });
    _channel
        .launchedWith()
        .then((payload) {
          final open = payload == null ? null : pushOpenOf(payload);
          if (open != null) _opens.add(open);
        })
        .catchError((_) {});
  }

  Future<void> _register() async {
    final token = _token;
    if (token == null || account.user == null) return;
    await account.call('POST', 'me/push/device', {
      'platform': _channel.platform,
      'token': token.token,
      if (token.app != null) 'app': token.app,
      if (_channel.platform == 'apns') 'sandbox': token.sandbox,
      'lang': language?.call() == 'tr' ? 'tr' : 'en',
    });
    registered = true;
    offering = false;
    notifyListeners();
  }

  /// The person reached out to someone: a good moment to offer push, if it is off and was not
  /// put off lately.
  void reachedOut() {
    if (!available || registered || offering || turnedOff) return;
    if (permission == PushPermission.denied) return;
    final count = _preferences.getInt(_laterCountKey) ?? 0;
    if (count >= offersAtMost) return;
    final later = _preferences.getInt(_laterKey);
    if (later != null &&
        _clock().difference(DateTime.fromMillisecondsSinceEpoch(later)) <
            waitAfterLater) {
      return;
    }
    offering = true;
    notifyListeners();
  }

  /// Yes: the system asks, and the token goes to the server when allowed. False when the
  /// phone said no (then only its Settings can allow it).
  Future<bool> turnOn() async {
    offering = false;
    await _preferences.remove(_offKey);
    notifyListeners();
    if (permission != PushPermission.granted) {
      var allowed = false;
      try {
        allowed = await _channel.ask();
      } on Object {
        allowed = false;
      }
      permission = allowed ? PushPermission.granted : PushPermission.denied;
      notifyListeners();
      if (!allowed) return false;
    }
    await _register();
    return true;
  }

  /// Not now: asked again in a week, at most three times.
  Future<void> notNow() async {
    offering = false;
    notifyListeners();
    await _preferences.setInt(_laterKey, _clock().millisecondsSinceEpoch);
    await _preferences.setInt(
      _laterCountKey,
      (_preferences.getInt(_laterCountKey) ?? 0) + 1,
    );
  }

  /// Off on this phone: the server forgets its token.
  Future<void> turnOff() async {
    await _preferences.setBool(_offKey, true);
    final token = _token;
    registered = false;
    notifyListeners();
    if (token != null) {
      await account.call('DELETE', 'me/push/device', {'token': token.token});
    }
  }

  int? _badge;

  /// The app icon's count follows the bell while push is on.
  void _unreadChanged() {
    if (!registered || notifications.unread == _badge) return;
    _badge = notifications.unread;
    _channel.badge(notifications.unread).catchError((_) {});
  }

  /// The app shows the call itself now.
  void clearCall(String callId) =>
      _channel.clearCall(callId).catchError((_) {});

  /// Signed out: the server ended this phone's push with the session.
  void clear() {
    registered = false;
    available = false;
    offering = false;
    notifyListeners();
  }

  @override
  void dispose() {
    notifications.removeListener(_unreadChanged);
    _taps?.cancel();
    _renewals?.cancel();
    _opens.close();
    super.dispose();
  }
}
