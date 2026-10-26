import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../safety_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/people.dart';
import '../together/together_hub.dart';
import 'ask_first.dart';
import 'share_watch_screen.dart';
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
    this.onCall,
  });

  final TogetherHub hub;
  final String? Function(String titleId)? gameName;

  /// Writes to a friend, by id.
  final ValueChanged<String>? onMessage;

  /// Opens someone's profile, by handle.
  final ValueChanged<String>? onProfile;

  /// Calls a friend.
  final ValueChanged<Person>? onCall;

  @override
  State<FriendsPane> createState() => _FriendsPaneState();
}

class _FriendsPaneState extends State<FriendsPane> {
  final _handle = TextEditingController();
  bool _adding = false;
  (String, bool)? _notice;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    if (!widget.hub.friends.loaded) _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      await widget.hub.friends.refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

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
      listenable: Listenable.merge([widget.hub.friends, widget.hub.sharePlays]),
      builder: (context, _) {
        final friends = widget.hub.friends;
        final shares = widget.hub.sharePlays;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final title = Text(
                  texts.friends,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                );
                final field = TextField(
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
                );
                final add = FilledButton.tonal(
                  onPressed: _adding ? null : _add,
                  child: Text(texts.friendsAdd),
                );
                // A small phone puts adding by handle under the title, the field taking the row.
                if (box.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 8),
                          add,
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Flexible(child: title),
                    const SizedBox(width: 12),
                    const Spacer(),
                    SizedBox(width: 220, child: field),
                    const SizedBox(width: 8),
                    add,
                  ],
                );
              },
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
            if (shares.invites.isNotEmpty) ...[
              SectionLabel(texts.shareTitle),
              for (final invite in shares.invites)
                _PersonRow(
                  person:
                      invite.from ??
                      const Person(id: '', handle: '?', displayName: '?'),
                  subtitle: texts.shareInvited(
                    invite.from?.displayName ?? '',
                    widget.gameName?.call(invite.titleId) ?? invite.name,
                  ),
                  subtitleColor: togetherPlaying,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _try(() => shares.decline(invite)),
                        child: Text(
                          texts.decline,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: () => openShareWatch(
                          context,
                          hub: widget.hub,
                          sharePlayId: invite.sharePlayId,
                        ),
                        icon: const Icon(Icons.live_tv_rounded, size: 18),
                        label: Text(texts.shareWatch),
                      ),
                    ],
                  ),
                ),
            ],
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
            if (!friends.loaded)
              LoadingOrFailed(error: _loadError, retry: _load),
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
                subtitle: friend.presence.share == null
                    ? presenceText(texts, friend.presence, widget.gameName)
                    : '${texts.shareSharing(widget.gameName?.call(friend.presence.share!.titleId) ?? friend.presence.share!.title ?? friend.presence.share!.titleId)}'
                          ' · ${texts.shareViewers(friend.presence.share!.viewers, friend.presence.share!.maxViewers)}',
                subtitleColor: friend.presence.state == PresenceState.offline
                    ? Colors.white38
                    : presenceColor(friend.presence.state),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (friend.presence.game case final game?
                        when game.joinable)
                      JoinablePill(game: game),
                    if (widget.onCall case final call?)
                      IconButton(
                        tooltip: texts.callFriend(friend.person.displayName),
                        onPressed: widget.hub.calls.inCall
                            ? null
                            : () => call(friend.person),
                        icon: const Icon(
                          Icons.call_outlined,
                          size: 20,
                          color: togetherAccent,
                        ),
                      ),
                    if (friend.presence.share case final share?
                        when share.open ||
                            shares.invites.any(
                              (i) => i.sharePlayId == share.sharePlayId,
                            ))
                      FilledButton.tonalIcon(
                        onPressed: () => openShareWatch(
                          context,
                          hub: widget.hub,
                          sharePlayId: share.sharePlayId,
                        ),
                        icon: const Icon(Icons.live_tv_rounded, size: 18),
                        label: Text(texts.shareWatch),
                      ),
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
                    PopupMenuButton<bool>(
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white38,
                      ),
                      color: const Color(0xFF1A1D27),
                      // Asked once the menu is gone: removing a friend cannot be taken back.
                      onSelected: (_) async {
                        final sure = await askFirst(
                          context,
                          question: texts.askRemoveFriend(
                            friend.person.displayName,
                          ),
                          action: texts.friendsRemove,
                        );
                        if (sure && mounted) {
                          await _try(() => friends.remove(friend.person.id));
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: true,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final who = Row(
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
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      final buttons = trailing;
      // On a small phone the buttons go under the name instead of pushing it off the row.
      final narrow = box.maxWidth < 440;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: buttons == null
            ? who
            : narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  who,
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: buttons,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: who),
                  buttons,
                ],
              ),
      );
    },
  );
}

/// A friend's game session with room: joined from the Mac's launcher, which a tap says.
class JoinablePill extends StatelessWidget {
  const JoinablePill({super.key, required this.game});

  final GamePresence game;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Tooltip(
      message: texts.joinableHint,
      child: Material(
        color: const Color(0x1F4CD964),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () =>
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(texts.joinableHint))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sports_esports_rounded,
                  size: 15,
                  color: togetherPlaying,
                ),
                const SizedBox(width: 5),
                Text(
                  texts.joinableCount(game.players, game.capacity),
                  style: const TextStyle(
                    color: togetherPlaying,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
