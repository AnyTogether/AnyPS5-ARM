import 'package:flutter/widgets.dart';

import 'calls.dart';
import 'feed.dart';
import 'friends.dart';
import 'messages.dart';
import 'parties.dart';
import 'together_account.dart';
import 'together_socket.dart';
import 'typing.dart';
import 'voice.dart';
import 'voice_mesh.dart';

/// AnyTogether's live side on the phone: the gateway socket, open while someone is signed in
/// and brought back as soon as the app is in the foreground again, and what it keeps up to date:
/// the friends, the messages, the party and its voice.
class TogetherHub extends ChangeNotifier {
  TogetherHub({
    required this.account,
    TogetherSocket? socket,
    VoiceEngine Function()? voiceEngine,
  }) : socket = socket ?? TogetherSocket(account: account) {
    friends = Friends(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    messages = Messages(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    parties = Parties(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    feed = Feed(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    voice = Voice(
      account: account,
      socket: this.socket,
      parties: parties,
      engine: voiceEngine,
    );
    calls = Calls(
      account: account,
      socket: this.socket,
      partyVoice: voice,
      engine: voiceEngine,
    );
    typing = Typing(account: account, socket: this.socket);
    account.addListener(_accountChanged);
    _lifecycle = AppLifecycleListener(onResume: this.socket.wake);
    _accountChanged();
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final Friends friends;
  late final Messages messages;
  late final Parties parties;
  late final Feed feed;

  /// Calls with a friend, ringing over any screen; and who is typing where.
  late final Calls calls;
  late final Typing typing;
  late final Voice voice;
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
    voice.leave(tell: false);
    calls.clear();
    typing.clear();
    socket.stop();
    friends.clear();
    messages.clear();
    parties.clear();
    feed.clear();
    if (user != null) socket.start();
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    _lifecycle.dispose();
    friends.dispose();
    messages.dispose();
    calls.dispose();
    typing.dispose();
    voice.dispose();
    parties.dispose();
    feed.dispose();
    socket.dispose();
    super.dispose();
  }
}
