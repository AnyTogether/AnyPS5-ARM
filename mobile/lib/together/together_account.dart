import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage.dart';

/// AnyTogether's own server. AnyTogether can be hosted by anyone: the phone may be pointed at
/// another one, and `--dart-define=ANYTOGETHER_URL=…` overrides both.
final standardServer = Uri.parse('https://anytogether.net');
const forcedServer = String.fromEnvironment('ANYTOGETHER_URL');

/// A server address as typed: https with a host, or http to this phone or the home network
/// (localhost, 10.x, 172.16–31.x, 192.168.x, a .local name); no user, query or fragment; without
/// the trailing slash. null when it is not one.
Uri? serverAddress(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https') return uri;
  return scheme == 'http' && _homeNetwork(uri.host.toLowerCase()) ? uri : null;
}

bool _homeNetwork(String host) {
  if (host == 'localhost' || host == '::1' || host.endsWith('.local')) {
    return true;
  }
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final [a!, b!, _, _] = parts;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

/// Who is signed in to AnyTogether.
class TogetherUser {
  const TogetherUser({
    required this.id,
    required this.handle,
    required this.displayName,
  });

  factory TogetherUser.fromJson(Map<String, dynamic> json) => TogetherUser(
    id: json['id'] as String,
    handle: json['handle'] as String,
    displayName: json['displayName'] as String,
  );

  final String id;
  final String handle;
  final String displayName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'displayName': displayName,
  };
}

/// An error AnyTogether answered with: RFC 9457 problem details with a stable code.
class TogetherProblem implements Exception {
  const TogetherProblem(this.status, this.code, this.title, [this.extra]);

  final int status;
  final String code;
  final String title;

  /// The problem's extension members: the private `section`, the blocked link's `domain`.
  final Map<String, dynamic>? extra;

  @override
  String toString() => title;
}

/// AnyTogether no longer answers this version of the app (client_too_old): the oldest it still
/// answers, this one's, and where to get a newer one.
class ClientTooOld {
  const ClientTooOld({required this.minimum, this.current, this.downloadUrl});

  final String minimum;
  final String? current;
  final Uri? downloadUrl;

  static ClientTooOld? fromProblem(Map<String, dynamic> json) {
    final minimum = json['minimum'];
    if (json['code'] != 'client_too_old' || minimum is! String) return null;
    final url = json['downloadUrl'];
    return ClientTooOld(
      minimum: minimum,
      current: json['current'] as String?,
      downloadUrl: url is String ? Uri.tryParse(url) : null,
    );
  }
}

/// Waiting for an approval was given up on the phone.
class TogetherCancelled implements Exception {
  const TogetherCancelled();
}

/// A sign-in the Mac approves.
class Handoff {
  const Handoff(this.id, this.secret);

  final String id;
  final String secret;
}

sealed class TogetherStep {
  const TogetherStep();
}

class Idle extends TogetherStep {
  const Idle();
}

class Busy extends TogetherStep {
  const Busy();
}

class CodeSent extends TogetherStep {
  const CodeSent(this.email);

  final String email;
}

/// Waiting for the Mac, signed in to AnyTogether, to approve this phone.
class WaitingForMac extends TogetherStep {
  const WaitingForMac(this.handoff);

  final Handoff handoff;
}

/// The phone's AnyTogether account: signing in with an email code or with the Mac's account,
/// keeping the session in the app's preferences, approving the Mac's own sign-in.
class TogetherAccount extends ChangeNotifier {
  TogetherAccount({
    required this.preferences,
    Uri? base,
    required this.clientName,
  }) : base = base ?? _chosen(preferences),
       serverFixed = base != null || forcedServer.isNotEmpty {
    _load();
  }

  final SharedPreferences preferences;

  /// The server in use: ANYTOGETHER_URL, then the one picked on the phone, then AnyTogether's.
  Uri base;

  /// Set at build time (or by a test): the phone cannot pick another server.
  final bool serverFixed;
  final String clientName;

  /// Set when AnyTogether answers client_too_old to any call: the app shows Update required.
  final tooOld = ValueNotifier<ClientTooOld?>(null);
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  static const _key = 'together.session';
  static const _serverKey = 'together.server';

  static Uri _chosen(SharedPreferences preferences) {
    if (forcedServer.isNotEmpty) return Uri.parse(forcedServer);
    return serverAddress(preferences.getString(_serverKey) ?? '') ??
        standardServer;
  }

  /// Uses another AnyTogether server, signing out of this one first; AnyTogether's own is kept
  /// as no choice at all.
  Future<void> useServer(Uri server) async {
    if (serverFixed || server == base) return;
    if (user != null) await signOut();
    base = server;
    storage = null;
    if (server == standardServer) {
      await preferences.remove(_serverKey);
    } else {
      await preferences.setString(_serverKey, server.toString());
    }
    notifyListeners();
  }

  TogetherUser? user;
  TogetherStep step = const Idle();
  String? _access;
  DateTime _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  String? _refresh;
  Future<String>? _refreshing;
  int _waiting = 0;

  void _load() {
    final saved = preferences.getString(_key);
    if (saved == null) return;
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      _access = json['accessToken'] as String;
      _accessExpiry = DateTime.parse(json['accessExpiry'] as String);
      _refresh = json['refreshToken'] as String;
      user = TogetherUser.fromJson(json['user'] as Map<String, dynamic>);
    } on Object {
      preferences.remove(_key);
    }
  }

  void _setStep(TogetherStep next) {
    step = next;
    notifyListeners();
  }

  // Signing in

  Future<void> startEmail(String email) async {
    _setStep(const Busy());
    try {
      await _send('POST', 'auth/email/start', {'email': email});
      _setStep(CodeSent(email));
    } on Object {
      _setStep(const Idle());
      rethrow;
    }
  }

  Future<TogetherUser> verifyEmail(String code) async {
    final sent = step;
    if (sent is! CodeSent) {
      throw const TogetherProblem(400, 'code_invalid', 'No code was sent');
    }
    return _keep(
      await _send('POST', 'auth/email/verify', {
        'email': sent.email,
        'code': code,
      }),
    );
  }

  /// Starts a hand-off for the Mac to approve; the caller tells the Mac its id.
  Future<Handoff> startHandoff(String deviceName) async {
    final json = await _send('POST', 'auth/handoff/start', {
      'deviceName': deviceName,
    });
    final handoff = Handoff(
      json['handoffId'] as String,
      json['secret'] as String,
    );
    _setStep(WaitingForMac(handoff));
    return handoff;
  }

  /// Asks until the hand-off is approved, turned down with [cancel], or out of time.
  Future<TogetherUser> waitForApproval(
    Handoff handoff, {
    Duration every = const Duration(seconds: 2),
    Duration within = const Duration(minutes: 5),
  }) async {
    final mine = ++_waiting;
    final deadline = DateTime.now().add(within);
    var wait = every;
    while (DateTime.now().isBefore(deadline)) {
      if (_waiting != mine) throw const TogetherCancelled();
      try {
        final json = await _send('POST', 'auth/token', {
          'grantType': 'handoff',
          'handoffId': handoff.id,
          'secret': handoff.secret,
        });
        if (_waiting != mine) throw const TogetherCancelled();
        return _keep(json);
      } on TogetherProblem catch (problem) {
        if (problem.code != 'authorization_pending' &&
            problem.code != 'slow_down') {
          _setStep(const Idle());
          rethrow;
        }
        if (problem.code == 'slow_down') wait += const Duration(seconds: 5);
        await Future<void>.delayed(wait);
      }
    }
    _setStep(const Idle());
    throw const TogetherProblem(
      400,
      'expired_token',
      'The sign-in was not approved in time',
    );
  }

  /// Stops waiting for an approval and goes back to the start.
  void cancel() {
    _waiting++;
    _setStep(const Idle());
  }

  /// Signs in the Mac that started this hand-off as us.
  Future<void> approveHandoff(String id) =>
      _authorized('POST', 'auth/handoff/$id/approve');

  Future<void> signOut() async {
    try {
      await _authorized('POST', 'auth/logout');
    } on Object {
      // Signed out here whatever the server says.
    }
    _forget();
  }

  void _forget() {
    preferences.remove(_key);
    user = null;
    _access = null;
    _refresh = null;
    step = const Idle();
    notifyListeners();
  }

  TogetherUser _keep(Map<String, dynamic> json) {
    _access = json['accessToken'] as String;
    _accessExpiry = DateTime.now().add(
      Duration(seconds: json['expiresIn'] as int),
    );
    _refresh = json['refreshToken'] as String;
    user = TogetherUser.fromJson(json['user'] as Map<String, dynamic>);
    preferences.setString(
      _key,
      jsonEncode({
        'accessToken': _access,
        'accessExpiry': _accessExpiry.toIso8601String(),
        'refreshToken': _refresh,
        'user': user!.toJson(),
      }),
    );
    step = const Idle();
    notifyListeners();
    return user!;
  }

  // Calls

  /// A signed-in call to AnyTogether's API, JSON both ways.
  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) => _authorized(method, path, body);

  /// A signed-in upload of raw bytes (a picture), JSON back; PUT unless [method] says.
  Future<Map<String, dynamic>> upload(
    String path,
    List<int> bytes,
    String contentType, {
    String method = 'PUT',
  }) async {
    Future<Map<String, dynamic>> send() async => _send(
      method,
      path,
      null,
      token: await _accessToken(),
      bytes: bytes,
      contentType: contentType,
    );
    try {
      return await send();
    } on TogetherProblem catch (problem) {
      if (problem.status != 401 || _refresh == null) rethrow;
      _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
      return send();
    }
  }

  // Cloud storage

  /// Whether this server keeps files, once asked; null before. Reset with the server.
  StorageInfo? storage;
  Future<StorageInfo>? _storageAsking;

  /// Whether the server keeps files (photos in messages, cloud saves): asked once without a
  /// token, kept after. A server that cannot be asked counts as off for now and is asked again;
  /// nobody signed in has none of it, so nothing is asked then.
  Future<bool> storageEnabled() async {
    final known = storage;
    if (known != null) return known.enabled;
    if (user == null) return false;
    final base = this.base;
    try {
      final info = await (_storageAsking ??= _send(
        'GET',
        'storage',
        null,
      ).then(StorageInfo.fromJson));
      if (base == this.base) {
        storage = info;
        notifyListeners();
      }
      return info.enabled;
    } on Object {
      return false;
    } finally {
      _storageAsking = null;
    }
  }

  /// How much of the account's quota saves and media use.
  Future<StorageUsage> storageUsage() async {
    final json = await call('GET', 'me/storage');
    if (json['enabled'] == false) {
      throw const TogetherProblem(503, 'storage_disabled', 'Storage is off');
    }
    return StorageUsage.fromJson(
      json['usage'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// A picture kept as media, to send in a message: what the server made of it.
  Future<Attachment> uploadImage(List<int> bytes) async {
    final json = await upload(
      'me/media?kind=image',
      bytes,
      imageContentType(bytes),
      method: 'POST',
    );
    return Attachment.fromJson(json['media'] as Map<String, dynamic>);
  }

  /// The profile's name or handle changed: the account shows the new one, and keeps it.
  void renamed({String? handle, String? displayName}) {
    final current = user;
    if (current == null) return;
    user = TogetherUser(
      id: current.id,
      handle: handle ?? current.handle,
      displayName: displayName ?? current.displayName,
    );
    final saved = preferences.getString(_key);
    if (saved != null) {
      try {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        json['user'] = user!.toJson();
        preferences.setString(_key, jsonEncode(json));
      } on Object {
        // Kept for this run; the next sign-in saves it again.
      }
    }
    notifyListeners();
  }

  /// The access token for the realtime gateway; [renew] refreshes it first, after the gateway
  /// turned it down.
  Future<String> accessToken({bool renew = false}) {
    if (renew) _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
    return _accessToken();
  }

  /// The session was signed out on another device or the website: forgotten here too.
  void signedOutElsewhere() => _forget();

  /// The access token, refreshed first when it is about to expire; one refresh at a time.
  Future<String> _accessToken() async {
    final access = _access;
    if (access == null || _refresh == null) {
      throw const TogetherProblem(401, 'unauthorized', 'Not signed in');
    }
    if (_accessExpiry.difference(DateTime.now()) >
        const Duration(seconds: 30)) {
      return access;
    }
    return _refreshing ??= _refreshNow().whenComplete(() => _refreshing = null);
  }

  Future<String> _refreshNow() async {
    try {
      final json = await _send('POST', 'auth/token', {
        'grantType': 'refresh_token',
        'refreshToken': _refresh,
      });
      _keep(json);
      return _access!;
    } on TogetherProblem catch (problem) {
      if (problem.status == 400 || problem.status == 401) _forget();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _authorized(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      return await _send(method, path, body, token: await _accessToken());
    } on TogetherProblem catch (problem) {
      if (problem.status != 401 || _refresh == null) rethrow;
      _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
      return _send(method, path, body, token: await _accessToken());
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? token,
    List<int>? bytes,
    String? contentType,
  }) async {
    final request = await _http.openUrl(
      method,
      Uri.parse(
        '${base.toString().replaceAll(RegExp(r'/$'), '')}/api/v1/$path',
      ),
    );
    request.headers
      ..set('AnyTogether-Client', clientName)
      ..set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (bytes != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType!);
      request.contentLength = bytes.length;
      request.add(bytes);
    } else if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    // A file going up gets time to get there.
    final response = await request.close().timeout(
      Duration(seconds: bytes != null ? 120 : 20),
    );
    final text = await utf8.decodeStream(response);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (json is Map<String, dynamic> && json['code'] is String) {
        final old = ClientTooOld.fromProblem(json);
        if (old != null) tooOld.value = old;
        throw TogetherProblem(
          response.statusCode,
          json['code'] as String,
          json['title'] as String? ?? '',
          json,
        );
      }
      throw TogetherProblem(
        response.statusCode,
        'internal',
        'AnyTogether answered ${response.statusCode}',
      );
    }
    return json is Map<String, dynamic> ? json : const {};
  }
}
