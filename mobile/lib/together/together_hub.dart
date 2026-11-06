import 'package:flutter/widgets.dart';

import 'calls.dart';
import 'discover.dart';
import 'e2ee_devices.dart';
import 'e2ee_keys.dart';
import 'feed.dart';
import 'friends.dart';
import 'messages.dart';
import 'notifications.dart';
import 'parties.dart';
import 'party_chat.dart';
import 'push.dart';
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
    PushChannel? pushChannel,
    DeviceKeyStore? e2eeKeys,
    String deviceName = 'AnyPS5 Remote',
  }) : socket = socket ?? TogetherSocket(account: account) {
    e2ee = E2ee(
      account: account,
      socket: this.socket,
      keys: e2eeKeys ?? SecureDeviceKeyStore(),
      deviceName: deviceName,
    );
    friends = Friends(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    messages = Messages(account: account, socket: this.socket, e2ee: e2ee)
      ..addListener(notifyListeners);
    parties = Parties(account: account, socket: this.socket)
      ..addListener(notifyListeners);
    partyChat = PartyChat(
      account: account,
      socket: this.socket,
      parties: parties,
    );
    messages.aside = partyChat.owns;
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
    push = PhonePush(
      account: account,
      notifications: notifications,
      channel: pushChannel,
      language: () => account.preferences.getString('language') ?? 'en',
    );
    // Reaching out to someone is when push is offered: they may answer while the app is closed.
    messages.onReachOut = push.reachedOut;
    friends.onReachOut = push.reachedOut;
    parties.addListener(_partyMaybeJoined);
    calls.addListener(_callMaybeStarted);
    account.addListener(_accountChanged);
    _lifecycle = AppLifecycleListener(
      onResume: this.socket.wake,
      onHide: _away,
    );
    _accountChanged();
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final Friends friends;

  /// End-to-end encryption of direct messages: this phone's keys and the people's devices.
  late final E2ee e2ee;
  late final Messages messages;
  late final Parties parties;

  /// The text chat beside the party's voice; kept out of [messages] and its count.
  late final PartyChat partyChat;
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

  /// Messages, invites and calls while the app is closed.
  late final PhonePush push;
  bool _wasInParty = false;
  bool _wasInCall = false;

  /// The app went to the background: its socket closes so pushes come at once, unless voice or a
  /// call needs it.
  void _away() {
    if (voice.active || calls.inCall || calls.incoming.isNotEmpty) return;
    socket.rest();
  }

  void _partyMaybeJoined() {
    final now = parties.party != null;
    if (now && !_wasInParty) push.reachedOut();
    _wasInParty = now;
  }

  void _callMaybeStarted() {
    final now = calls.active != null;
    if (now && !_wasInCall) push.reachedOut();
    _wasInCall = now;
  }

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
    e2ee.clear();
    friends.clear();
    messages.clear();
    parties.clear();
    partyChat.clear();
    feed.clear();
    notifications.clear();
    sharePlays.clear();
    discover.clear();
    push.clear();
    // End-to-end encryption registers once the socket is live (E2ee listens for it).
    if (user != null) {
      socket.start();
      push.start().catchError((_) {});
    }
    notifyListeners();
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    parties.removeListener(_partyMaybeJoined);
    calls.removeListener(_callMaybeStarted);
    push.dispose();
    _lifecycle.dispose();
    friends.dispose();
    messages.dispose();
    e2ee.dispose();
    calls.dispose();
    typing.dispose();
    voice.dispose();
    sharePlays.dispose();
    discover.dispose();
    partyChat.dispose();
    parties.dispose();
    feed.dispose();
    notifications.dispose();
    socket.dispose();
    super.dispose();
  }
}
