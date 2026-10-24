import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/together_hub.dart';
import '../together/together_socket.dart';
import 'friends_view.dart';
import 'messages_view.dart';
import 'party_view.dart';
import 'together_widgets.dart';

enum TogetherTab { friends, messages, party }

/// AnyTogether's own screen over whatever the phone shows: a rail of what there is on the left,
/// the part picked on the right, the way a phone held sideways has room for both.
Future<void> openTogether(
  BuildContext context, {
  required TogetherHub hub,
  TogetherTab tab = TogetherTab.friends,
  String? Function(String titleId)? gameName,
}) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) =>
        TogetherScreen(hub: hub, tab: tab, gameName: gameName),
    transitionsBuilder: (_, animation, _, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: eased,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(eased),
          child: child,
        ),
      );
    },
  ),
);

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({
    super.key,
    required this.hub,
    this.tab = TogetherTab.friends,
    this.gameName,
  });

  final TogetherHub hub;
  final TogetherTab tab;

  /// A game's name from the Mac's library, for a friend playing it.
  final String? Function(String titleId)? gameName;

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  late TogetherTab _tab = widget.tab;

  @override
  void initState() {
    super.initState();
    widget.hub.friends.refresh().catchError((_) {});
  }

  void _show(TogetherTab tab) => setState(() => _tab = tab);

  /// Writes to a friend: their conversation, made the first time, in Messages.
  void _message(String userId) {
    _show(TogetherTab.messages);
    widget.hub.messages.withFriend(userId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Scaffold(
      backgroundColor: togetherInk,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.hub,
          builder: (context, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 196, child: _rail(texts)),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: togetherPanel,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: switch (_tab) {
                        TogetherTab.friends => FriendsPane(
                          hub: widget.hub,
                          gameName: widget.gameName,
                          onMessage: _message,
                        ),
                        TogetherTab.messages => MessagesPane(hub: widget.hub),
                        TogetherTab.party => PartyPane(hub: widget.hub),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(Strings texts) {
    final hub = widget.hub;
    final handle = hub.account.user?.handle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: texts.back,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white70,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texts.together,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (handle != null)
                      Text(
                        '@$handle',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RailItem(
            icon: Icons.people_alt_rounded,
            label: texts.friends,
            count: hub.friends.incoming.length,
            selected: _tab == TogetherTab.friends,
            onTap: () => _show(TogetherTab.friends),
          ),
          _RailItem(
            icon: Icons.chat_bubble_rounded,
            label: texts.messages,
            count: hub.messages.unread,
            selected: _tab == TogetherTab.messages,
            onTap: () => _show(TogetherTab.messages),
          ),
          _RailItem(
            icon: Icons.celebration_rounded,
            label: texts.party,
            count: hub.parties.invites.length,
            live: hub.parties.party != null,
            selected: _tab == TogetherTab.party,
            onTap: () => _show(TogetherTab.party),
          ),
          const Spacer(),
          _LiveDot(socket: hub.socket),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.live = false,
  });

  final IconData icon;
  final String label;
  final int count;

  /// A green dot: the phone is in it (the party).
  final bool live;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: selected ? const Color(0x1F8AB4FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? togetherAccent : Colors.white60,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (live && count == 0)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(
                    color: togetherPlaying,
                    shape: BoxShape.circle,
                  ),
                ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: togetherAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      color: togetherInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Whether the phone hears AnyTogether live right now.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.socket});

  final TogetherSocket socket;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: socket,
    builder: (context, _) {
      final texts = Texts.of(context);
      final live = socket.status == SocketStatus.ready;
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live ? togetherPlaying : const Color(0x40FFFFFF),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              live ? texts.togetherLive : texts.togetherConnecting,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}
