import 'package:flutter/widgets.dart';

import 'friends.dart';
import 'messages.dart';
import 'parties.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// AnyTogether's live side on the phone: the gateway socket, open while someone is signed in
/// and brought back as soon as the app is in the foreground again, and what it keeps up to date:
/// the friends, the messages and the party.
class TogetherHub extends ChangeNotifier {
  TogetherHub({required this.account, TogetherSocket? socket})
    : socket = socket ?? TogetherSocket(account: account) {
    friends = Friends(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    messages = Messages(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    parties = Parties(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    account.addListener(_accountChanged);
    _lifecycle = AppLifecycleListener(onResume: this.socket.wake);
    _accountChanged();
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final Friends friends;
  late final Messages messages;
  late final Parties parties;
  late final AppLifecycleListener _lifecycle;
  String? _user;

  /// Who is signed in, by id.
  String? get me => account.user?.id;

  /// What waits for an answer: friend requests, unread messages, party invites.
  int get badge =>
      friends.incoming.length + messages.unread + parties.invites.length;

  void _accountChanged() {
    final user = account.user?.id;
    if (user == _user) return;
    _user = user;
    socket.stop();
    friends.clear();
    messages.clear();
    parties.clear();
    if (user != null) socket.start();
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    _lifecycle.dispose();
    friends.dispose();
    messages.dispose();
    parties.dispose();
    socket.dispose();
    super.dispose();
  }
}
