import 'dart:async';

import 'package:flutter/foundation.dart';

import 'people.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// The friends list on the phone: who they are and what they are doing, requests both ways,
/// and adding someone by handle. Presence and requests change live from the gateway.
class Friends extends ChangeNotifier {
  Friends({required this.account, required this.socket}) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final StreamSubscription<TogetherEvent> _events;

  List<Friend> friends = const [];
  List<Person> incoming = const [];
  List<Person> outgoing = const [];
  bool loaded = false;

  Future<void> refresh() async {
    final list = await account.call('GET', 'me/friends');
    final requests = await account.call('GET', 'me/friends/requests');
    friends = _sorted([
      for (final json in (list['friends'] as List? ?? const []))
        Friend(
          Person.fromJson(json as Map<String, dynamic>),
          Presence.fromJson(json['presence'] as Map<String, dynamic>?),
        ),
    ]);
    incoming = _people(requests['incoming']);
    outgoing = _people(requests['outgoing']);
    loaded = true;
    notifyListeners();
  }

  /// Asks someone by handle; true when it made friends at once (they had asked first).
  Future<bool> add(String handle) async {
    final answer = await account.call('POST', 'me/friends/requests', {
      'handle': handle.trim().replaceFirst(RegExp('^@'), ''),
    });
    await refresh();
    return answer['state'] == 'accepted';
  }

  Future<void> answer(String userId, {required bool accept}) async {
    await account.call(
      'POST',
      'me/friends/requests/$userId/${accept ? 'accept' : 'decline'}',
    );
    incoming = incoming.where((person) => person.id != userId).toList();
    notifyListeners();
    if (accept) await refresh();
  }

  Future<void> remove(String userId) async {
    await account.call('DELETE', 'me/friends/$userId');
    friends = friends.where((friend) => friend.person.id != userId).toList();
    notifyListeners();
  }

  /// The friend with this id, if they are one.
  Friend? byId(String userId) =>
      friends.where((friend) => friend.person.id == userId).firstOrNull;

  /// Signed out: nothing kept.
  void clear() {
    friends = const [];
    incoming = const [];
    outgoing = const [];
    loaded = false;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    switch (event.type) {
      case 'live.ready' || 'friend.request' || 'friend.accepted':
        refresh().catchError((_) {});
      case 'friend.removed':
        final gone = event.json['userId'];
        friends = friends.where((friend) => friend.person.id != gone).toList();
        notifyListeners();
      case 'presence.updated':
        final userId = event.json['userId'];
        final known = friends.indexWhere(
          (friend) => friend.person.id == userId,
        );
        if (known < 0) return;
        final next = [...friends];
        next[known] = Friend(next[known].person, Presence.fromJson(event.json));
        friends = _sorted(next);
        notifyListeners();
    }
  }

  static List<Person> _people(Object? list) => [
    for (final json in (list as List? ?? const []))
      Person.fromJson(json as Map<String, dynamic>),
  ];

  /// Playing first, then online, away, offline; each by name, as the API sorts them.
  static List<Friend> _sorted(List<Friend> list) => list
    ..sort(
      (a, b) => a.presence.state.index.compareTo(b.presence.state.index) != 0
          ? a.presence.state.index.compareTo(b.presence.state.index)
          : a.person.displayName.toLowerCase().compareTo(
              b.person.displayName.toLowerCase(),
            ),
    );

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
