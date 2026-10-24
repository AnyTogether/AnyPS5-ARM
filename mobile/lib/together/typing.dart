import 'dart:async';

import 'package:flutter/foundation.dart';

import 'together_account.dart';
import 'together_socket.dart';

/// Who is typing where: "I am typing" goes to the gateway at most every two seconds per
/// conversation (as it allows), and someone else's shows for a few seconds after their last one,
/// or until their message arrives. Nothing of it is kept.
class Typing extends ChangeNotifier {
  Typing({
    required this.account,
    required this.socket,
    this.shownFor = const Duration(seconds: 5),
    this.every = const Duration(seconds: 2),
  }) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  final Duration shownFor;
  final Duration every;
  late final StreamSubscription<TogetherEvent> _events;

  /// By conversation, who is typing and until when.
  final _typing = <String, Map<String, DateTime>>{};
  final _said = <String, DateTime>{};
  Timer? _prune;

  /// Who else is typing in a conversation, by user id, in the order they started.
  List<String> who(String conversationId) {
    final now = DateTime.now();
    return [
      for (final entry in (_typing[conversationId] ?? const {}).entries)
        if (entry.value.isAfter(now)) entry.key,
    ];
  }

  /// Something was typed in a conversation: told to the others unless told just now.
  void typed(String conversationId) {
    final now = DateTime.now();
    final last = _said[conversationId];
    if (last != null && now.difference(last) < every) return;
    if (socket.send({'op': 'typing', 'conversation': conversationId})) {
      _said[conversationId] = now;
    }
  }

  void clear() {
    _typing.clear();
    _said.clear();
    _prune?.cancel();
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    final conversation = data['conversationId'];
    if (conversation is! String) return;
    switch (event.type) {
      case 'typing':
        final user = data['userId'];
        if (user is! String || user == account.user?.id) return;
        (_typing[conversation] ??= {})[user] = DateTime.now().add(shownFor);
        _schedule();
        notifyListeners();
      case 'message.created':
        // Their message is here: they are done typing it.
        final removed = _typing[conversation]?.remove(data['authorId']);
        if (removed != null) notifyListeners();
    }
  }

  /// Wakes up when the first indicator runs out, to take it away.
  void _schedule() {
    _prune?.cancel();
    final ends = _typing.values.expand((m) => m.values).toList()..sort();
    if (ends.isEmpty) return;
    final wait = ends.first.difference(DateTime.now());
    _prune = Timer(wait.isNegative ? Duration.zero : wait, () {
      final now = DateTime.now();
      for (final map in _typing.values) {
        map.removeWhere((_, until) => !until.isAfter(now));
      }
      _typing.removeWhere((_, map) => map.isEmpty);
      _schedule();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _events.cancel();
    _prune?.cancel();
    super.dispose();
  }
}
