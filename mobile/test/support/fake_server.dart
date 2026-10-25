import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/together/together_account.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AnyTogether on one local port: the API, scripted by method and path, and the realtime
/// gateway at /rt, which keeps every frame it was sent and pushes what a test asks for.
class FakeServer {
  late HttpServer http;
  final requests = <(String method, String path, Map<String, dynamic>? body)>[];
  final sockets = <WebSocket>[];

  /// Raw bodies that were not JSON (pictures, files), with their content type.
  final uploads =
      <(String method, String path, List<int> bytes, String? contentType)>[];
  final frames = <Map<String, dynamic>>[];
  final _connected = StreamController<WebSocket>.broadcast();
  int _ids = 0;

  /// What the API answers; a 404 problem unless a test says otherwise.
  (int, Object?) Function(
    String method,
    String path,
    Map<String, dynamic>? body,
  )
  answer = (_, _, _) =>
      (404, {'code': 'not_found', 'status': 404, 'title': 'no'});

  /// Whether a hello gets its ready frame; off, the socket waits.
  bool readyOnHello = true;
  num heartbeat = 25;

  Uri get base => Uri.parse('http://127.0.0.1:${http.port}');

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      if (request.uri.path == '/rt' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((message) {
          final frame = jsonDecode(message as String) as Map<String, dynamic>;
          frames.add(frame);
          if (frame['op'] == 'hello' && readyOnHello) {
            socket.add(
              jsonEncode({
                'op': 'ready',
                'session': 'device-1',
                'heartbeat': heartbeat,
              }),
            );
          }
        });
        _connected.add(socket);
        return;
      }
      final bytes = await request.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      final path = request.uri.hasQuery
          ? '${request.uri.path}?${request.uri.query}'
          : request.uri.path;
      // JSON as JSON; anything else (a picture going up) is kept as its bytes.
      Map<String, dynamic>? body;
      if (bytes.isNotEmpty) {
        if (request.headers.contentType?.mimeType == 'application/json') {
          body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        } else {
          uploads.add((
            request.method,
            path,
            bytes,
            request.headers.contentType?.mimeType,
          ));
        }
      }
      requests.add((request.method, path, body));
      final (status, json) = answer(request.method, path, body);
      request.response.statusCode = status;
      if (status != 204) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(json));
      }
      await request.response.close();
    });
  }

  Future<void> stop() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await _connected.close();
    await http.close(force: true);
  }

  /// The next socket to connect.
  Future<WebSocket> connected() => _connected.stream.first;

  /// Frames with this op, in the order they came.
  List<Map<String, dynamic>> sent(String op) =>
      frames.where((frame) => frame['op'] == op).toList();

  /// An event on the latest socket, with an API-style (UUIDv7) id unless given one.
  String push(String type, Object? data, {String? id}) {
    final eventId =
        id ?? '0190a000-0000-7000-8000-${(++_ids).toString().padLeft(12, '0')}';
    sockets.last.add(
      jsonEncode({'op': 'event', 'id': eventId, 'type': type, 'data': data}),
    );
    return eventId;
  }

  /// A signed-in account, kept as the app keeps it, against this server.
  Future<TogetherAccount> account({
    String access = 'access-1',
    Duration expiresIn = const Duration(minutes: 15),
  }) async {
    SharedPreferences.setMockInitialValues({
      'together.session': jsonEncode({
        'accessToken': access,
        'accessExpiry': DateTime.now().add(expiresIn).toIso8601String(),
        'refreshToken': 'refresh-1',
        'user': {'id': 'me', 'handle': 'utku', 'displayName': 'Utku'},
      }),
    });
    return TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      base: base,
      clientName: 'remote-ios/test',
    );
  }
}

/// Waits until [done] holds, checking every few milliseconds, for at most [within].
Future<void> until(
  bool Function() done, {
  Duration within = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(within);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', within);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A person as the API's name cards show them.
Map<String, dynamic> card(String id, {String? handle, String? name}) => {
  'userId': id,
  'handle': handle ?? id,
  'displayName': name ?? id.toUpperCase(),
  'avatar': null,
};
