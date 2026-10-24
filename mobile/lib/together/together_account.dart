import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where AnyTogether is; `--dart-define=ANYTOGETHER_URL=…` points the app at another server.
final togetherBase = Uri.parse(
  const String.fromEnvironment(
    'ANYTOGETHER_URL',
    defaultValue: 'https://anytogether.kodla.agency',
  ),
);

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
  const TogetherProblem(this.status, this.code, this.title);

  final int status;
  final String code;
  final String title;

  @override
  String toString() => title;
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
  }) : base = base ?? togetherBase {
    _load();
  }

  final SharedPreferences preferences;
  final Uri base;
  final String clientName;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  static const _key = 'together.session';

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

  Future<Map<String, dynamic>> _authorized(String method, String path) async {
    try {
      return await _send(method, path, null, token: await _accessToken());
    } on TogetherProblem catch (problem) {
      if (problem.status != 401 || _refresh == null) rethrow;
      _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
      return _send(method, path, null, token: await _accessToken());
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    String? token,
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
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await utf8.decodeStream(response);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (json is Map<String, dynamic> && json['code'] is String) {
        throw TogetherProblem(
          response.statusCode,
          json['code'] as String,
          json['title'] as String? ?? '',
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
