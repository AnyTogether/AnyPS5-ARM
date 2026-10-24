import 'dart:async';

import 'package:flutter/foundation.dart';

import 'activity.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// The activity feed on the phone: what friends played, earned and reached, newest first, a
/// page at a time; items that arrive or change live replace the one with the same id; the
/// reader's reactions show at once and settle with what the server counted.
class Feed extends ChangeNotifier {
  Feed({required this.account, required this.socket}) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final StreamSubscription<TogetherEvent> _events;

  static const pageSize = 30;

  List<Activity> items = const [];

  /// Where the next (older) page starts; null at the end.
  String? next;
  bool loaded = false;
  bool _older = false;

  /// Items that came live while the feed was not looked at.
  int unseen = 0;
  bool _watching = false;

  Future<void> refresh() async {
    final page = FeedPage.fromJson(
      await account.call('GET', 'me/feed?limit=$pageSize'),
    );
    items = page.items;
    next = page.next;
    loaded = true;
    notifyListeners();
  }

  Future<void> older() async {
    final from = next;
    if (from == null || _older) return;
    _older = true;
    try {
      final page = FeedPage.fromJson(
        await account.call('GET', 'me/feed?limit=$pageSize&before=$from'),
      );
      final known = items.map((item) => item.id).toSet();
      items = [...items, ...page.items.where((i) => !known.contains(i.id))];
      next = page.next;
      notifyListeners();
    } finally {
      _older = false;
    }
  }

  /// The feed is on screen: what comes live is seen.
  void watch(bool on) {
    _watching = on;
    if (on && unseen > 0) {
      unseen = 0;
      notifyListeners();
    }
  }

  /// Picks a reaction for an item, or takes it back with null; shown at once, put back when the
  /// server says no.
  Future<void> react(String id, Reaction? reaction) async {
    final before = items.where((item) => item.id == id).firstOrNull;
    if (before == null || before.reactions.mine == reaction) return;
    _set(before.withReactions(before.reactions.picked(reaction)));
    try {
      final counted = reaction == null
          ? await account.call('DELETE', 'activities/$id/reaction')
          : await account.call('PUT', 'activities/$id/reaction', {
              'reaction': reaction.name,
            });
      final now = items.where((item) => item.id == id).firstOrNull;
      if (now != null) _set(now.withReactions(Reactions.fromJson(counted)));
    } on Object {
      final now = items.where((item) => item.id == id).firstOrNull;
      if (now != null) _set(now.withReactions(before.reactions));
      rethrow;
    }
  }

  void _set(Activity item) {
    items = [
      for (final i in items)
        if (i.id == item.id) item else i,
    ];
    notifyListeners();
  }

  /// A new item goes on top, a changed one (more trophies folded in) replaces its old self.
  void _arrived(Activity item) {
    final at = items.indexWhere((i) => i.id == item.id);
    if (at >= 0) {
      items = [...items]..[at] = item;
    } else {
      items = [item, ...items]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!_watching) unseen++;
    }
    notifyListeners();
  }

  void clear() {
    items = const [];
    next = null;
    loaded = false;
    unseen = 0;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    switch (event.type) {
      case 'live.ready' when loaded:
        refresh().catchError((_) {});
      case 'feed.item':
        if (Activity.fromJson(event.json) case final item?) _arrived(item);
    }
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
