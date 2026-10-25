import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/feed.dart';
import '../together/people.dart';
import '../together/together_hub.dart';
import 'activity_tile.dart';
import 'together_widgets.dart';

/// The activity feed: what friends played, earned and reached, newest first, each with its
/// reactions; older items a page at a time; new ones slide in as they happen.
class FeedPane extends StatefulWidget {
  const FeedPane({super.key, required this.hub, this.onProfile});

  final TogetherHub hub;

  /// Opens someone's profile, by handle.
  final ValueChanged<String>? onProfile;

  @override
  State<FeedPane> createState() => _FeedPaneState();
}

class _FeedPaneState extends State<FeedPane> {
  late final Feed _feed = widget.hub.feed;
  Object? _error;
  bool _older = false;

  @override
  void initState() {
    super.initState();
    // Marking it seen tells the screen around it, which may be building this very frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feed.watch(true);
    });
    _load();
  }

  @override
  void dispose() {
    _feed.watch(false);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await _feed.refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _more() async {
    setState(() => _older = true);
    try {
      await _feed.older();
    } on Object {
      // The button stays for another try.
    }
    if (mounted) setState(() => _older = false);
  }

  void _react(String id, Reaction? reaction) {
    final texts = Texts.of(context);
    _feed.react(id, reaction).catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(togetherFailure(texts, error))));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: _feed,
      builder: (context, _) {
        final items = _feed.items;
        final empty = _feed.loaded && items.isEmpty;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
            children: [
              Text(
                texts.feed,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                texts.feedLead,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (!_feed.loaded && _error == null && items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_error != null && items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          togetherFailure(texts, _error!),
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                      TextButton(onPressed: _load, child: Text(texts.retry)),
                    ],
                  ),
                ),
              if (empty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    widget.hub.friends.loaded &&
                            widget.hub.friends.friends.isEmpty
                        ? texts.feedEmptyNoFriends
                        : texts.feedEmpty,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              for (final item in items)
                ActivityTile(
                  key: ValueKey(item.id),
                  item: item,
                  onReact: (reaction) => _react(item.id, reaction),
                  onPerson: widget.onProfile == null
                      ? null
                      : (Person person) => widget.onProfile!(person.handle),
                ),
              if (_feed.next != null)
                Center(
                  child: TextButton(
                    onPressed: _older ? null : _more,
                    child: Text(texts.loadMore),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
