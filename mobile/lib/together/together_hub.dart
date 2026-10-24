import 'package:flutter/widgets.dart';

import 'together_account.dart';
import 'together_socket.dart';

/// AnyTogether's live side on the phone: the gateway socket, open while someone is signed in,
/// and brought back as soon as the app is in the foreground again.
class TogetherHub extends ChangeNotifier {
  TogetherHub({required this.account, TogetherSocket? socket})
    : socket = socket ?? TogetherSocket(account: account) {
    account.addListener(_accountChanged);
    _lifecycle = AppLifecycleListener(onResume: this.socket.wake);
    _accountChanged();
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final AppLifecycleListener _lifecycle;
  String? _user;

  void _accountChanged() {
    final user = account.user?.id;
    if (user == _user) return;
    _user = user;
    if (user == null) {
      socket.stop();
    } else {
      socket.stop();
      socket.start();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    _lifecycle.dispose();
    socket.dispose();
    super.dispose();
  }
}
