import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A hub signed in as "me" (@utku) for the screens, against a server that is not there and
/// with its socket stopped: the tests set what the lists hold themselves.
Future<TogetherHub> quietHub() async {
  SharedPreferences.setMockInitialValues({
    'together.session': '{"accessToken":"a","accessExpiry":"2999-01-01T00:00:00.000","refreshToken":"r","user":{"id":"me","handle":"utku","displayName":"Utku"}}',
  });
  final hub = TogetherHub(
    account: TogetherAccount(
      preferences: await SharedPreferences.getInstance(),
      clientName: 'test',
      base: Uri.parse('http://127.0.0.1:9'),
    ),
  );
  hub.socket.stop();
  return hub;
}
