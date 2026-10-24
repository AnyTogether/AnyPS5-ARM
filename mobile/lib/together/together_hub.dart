import 'package:flutter/widgets.dart';

import 'friends.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// AnyTogether's live side on the phone: the gateway socket, open while someone is signed in
/// and brought back as soon as the app is in the foreground again, and the friends list it
/// keeps up to date.
class TogetherHub extends ChangeNotifier {
  TogetherHub({required this.account, TogetherSocket? socket})
    : socket = socket ?? TogetherSocket(account: account) {
    friends = Friends(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    account.addListener(_accountChanged);
    _lifecycle = AppLifecycleListener(onResume: this.socket.wake);
    _accountChanged();
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final Friends friends;
  late final AppLifecycleListener _lifecycle;
  String? _user;

  /// Who is signed in, by id.
  String? get me => account.user?.id;

  /// What waits for an answer: friend requests.
  int get badge => friends.incoming.length;

  void _accountChanged() {
    final user = account.user?.id;
    if (user == _user) return;
    _user = user;
    socket.stop();
    friends.clear();
    if (user != null) socket.start();
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    _lifecycle.dispose();
    friends.dispose();
    socket.dispose();
    super.dispose();
  }
}
