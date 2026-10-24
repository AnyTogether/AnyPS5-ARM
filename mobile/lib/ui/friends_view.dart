import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/people.dart';
import '../together/together_hub.dart';
import 'together_widgets.dart';

/// Friends: add someone by handle at the top, the requests waiting for an answer, then everyone
/// with what they are doing, the ones playing first.
class FriendsPane extends StatefulWidget {
  const FriendsPane({
    super.key,
    required this.hub,
    this.gameName,
    this.onMessage,
    this.onProfile,
  });

  final TogetherHub hub;
  final String? Function(String titleId)? gameName;

  /// Writes to a friend, by id.
  final ValueChanged<String>? onMessage;

  /// Opens someone's profile, by handle.
  final ValueChanged<String>? onProfile;

  @override
  State<FriendsPane> createState() => _FriendsPaneState();
}

class _FriendsPaneState extends State<FriendsPane> {
  final _handle = TextEditingController();
  bool _adding = false;
  (String, bool)? _notice;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final texts = Texts.of(context);
    final handle = _handle.text.trim().replaceFirst(RegExp('^@'), '');
    if (handle.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _notice = null;
    });
    try {
      final friends = await widget.hub.friends.add(handle);
      _handle.clear();
      _notice = (
        friends ? texts.friendsAdded(handle) : texts.friendsRequested(handle),
        false,
      );
    } on Object catch (error) {
      _notice = (togetherFailure(texts, error), true);
    }
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    try {
      await step();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notice = (togetherFailure(texts, error), true));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: widget.hub.friends,
      builder: (context, _) {
        final friends = widget.hub.friends;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
          children: [
            Row(
              children: [
                Text(
                  texts.friends,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _handle,
                    autocorrect: false,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '@',
                      prefixStyle: const TextStyle(color: Colors.white38),
                      hintText: texts.friendsHandle,
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0x14FFFFFF),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _adding ? null : _add,
                  child: Text(texts.friendsAdd),
                ),
              ],
            ),
            if (_notice case (final text, final error))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  text,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: error ? togetherError : togetherAccent,
                    fontSize: 13,
                  ),
                ),
              ),
            if (friends.incoming.isNotEmpty) ...[
              SectionLabel(texts.friendsRequests),
              for (final person in friends.incoming)
                _PersonRow(
                  person: person,
                  subtitle: '@${person.handle}',
                  onTap: widget.onProfile == null
                      ? null
                      : () => widget.onProfile!(person.handle),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _try(
                          () => friends.answer(person.id, accept: false),
                        ),
                        child: Text(
                          texts.decline,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () =>
                            _try(() => friends.answer(person.id, accept: true)),
                        child: Text(texts.accept),
                      ),
                    ],
                  ),
                ),
            ],
            SectionLabel(texts.friends),
            if (friends.loaded && friends.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  texts.friendsNone,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            for (final friend in friends.friends)
              _PersonRow(
                person: friend.person,
                onTap: widget.onProfile == null
                    ? null
                    : () => widget.onProfile!(friend.person.handle),
                presence: friend.presence.state,
                subtitle: presenceText(texts, friend.presence, widget.gameName),
                subtitleColor: friend.presence.state == PresenceState.offline
                    ? Colors.white38
                    : presenceColor(friend.presence.state),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onMessage case final message?)
                      IconButton(
                        tooltip: texts.messagesWrite,
                        onPressed: () => message(friend.person.id),
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 20,
                          color: togetherAccent,
                        ),
                      ),
                    PopupMenuButton<void>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white38,
                      ),
                      color: const Color(0xFF1A1D27),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          onTap: () =>
                              _try(() => friends.remove(friend.person.id)),
                          child: Text(texts.friendsRemove),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (friends.outgoing.isNotEmpty) ...[
              SectionLabel(texts.friendsSent),
              for (final person in friends.outgoing)
                _PersonRow(
                  person: person,
                  subtitle: '@${person.handle}',
                  trailing: Text(
                    texts.friendsWaiting,
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.subtitle,
    this.subtitleColor = Colors.white54,
    this.presence,
    this.trailing,
    this.onTap,
  });

  final Person person;
  final VoidCallback? onTap;
  final String subtitle;
  final Color subtitleColor;
  final PresenceState? presence;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              children: [
                Avatar(person: person, presence: presence),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtitleColor, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
