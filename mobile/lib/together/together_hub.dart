import 'package:flutter/widgets.dart';

import 'calls.dart';
import 'discover.dart';
import 'feed.dart';
import 'friends.dart';
import 'messages.dart';
import 'notifications.dart';
import 'parties.dart';
import 'share_play.dart';
import 'share_play_webrtc.dart';
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
    ShareEngine Function()? shareEngine,
    ShareSound Function()? shareSound,
  }) : socket = socket ?? TogetherSocket(account: account) {
    friends = Friends(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    messages = Messages(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    parties = Parties(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    feed = Feed(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    notifications = Notifications(account: account, socket: this.socket)
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
    sharePlays = SharePlays(
      account: account,
      socket: this.socket,
      engine: shareEngine ?? WebRtcShareEngine.new,
      sound: shareSound ?? PlatformShareSound.new,
    )..addListener(notifyListeners);
    discover = Discover(
      account: account,
      socket: this.socket,
      parties: parties,
      sharePlays: sharePlays,
    )..addListener(notifyListeners);
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

  /// The bell: what happened while away, and its unread count.
  late final Notifications notifications;

  /// Calls with a friend, ringing over any screen; and who is typing where.
  late final Calls calls;
  late final Typing typing;
  late final Voice voice;

  /// Watching friends' share plays.
  late final SharePlays sharePlays;

  /// Finding players beyond friends: the board, public parties and share plays, discovery.
  late final Discover discover;
  late final AppLifecycleListener _lifecycle;
  String? _user;

  /// Who is signed in, by id.
  String? get me => account.user?.id;

  /// What waits for an answer: friend requests, unread messages, party and share play invites,
  /// people asking into the party this phone leads, and "I'm in"s on its open posts.
  int get badge =>
      friends.incoming.length +
      messages.unread +
      parties.invites.length +
      sharePlays.invites.length +
      (parties.party?.leaderId == me && me != null
          ? parties.party!.requests.length
          : 0) +
      discover.waiting;

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
    notifications.clear();
    sharePlays.clear();
    discover.clear();
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
    sharePlays.dispose();
    discover.dispose();
    parties.dispose();
    feed.dispose();
    notifications.dispose();
    socket.dispose();
    super.dispose();
  }
}
