import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An account signed in as "me" (@utku) whose API calls never leave the test: each is kept,
/// and answered by [answer] at once (a 404 problem when it has nothing).
class ScriptedAccount extends TogetherAccount {
  ScriptedAccount({required super.preferences})
    : super(clientName: 'test', base: Uri.parse('http://127.0.0.1:9'));

  final calls = <(String method, String path, Map<String, dynamic>? body)>[];

  Map<String, dynamic>? Function(
    String method,
    String path,
    Map<String, dynamic>? body,
  )
  answer = (_, _, _) => null;

  /// The paths called with [method], in order.
  List<String> paths(String method) => [
    for (final call in calls)
      if (call.$1 == method) call.$2,
  ];

  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add((method, path, body));
    final json = answer(method, path, body);
    if (json == null) {
      throw const TogetherProblem(404, 'not_found', 'Not there');
    }
    return json;
  }
}

/// A hub over a [ScriptedAccount], its socket stopped: the screens with lists a test sets and
/// calls it can read back.
Future<(TogetherHub, ScriptedAccount)> scriptedHub() async {
  SharedPreferences.setMockInitialValues({
    'together.session': '{"accessToken":"a","accessExpiry":"2999-01-01T00:00:00.000","refreshToken":"r","user":{"id":"me","handle":"utku","displayName":"Utku"}}',
  });
  final account = ScriptedAccount(
    preferences: await SharedPreferences.getInstance(),
  );
  final hub = TogetherHub(account: account);
  hub.socket.stop();
  return (hub, account);
}
