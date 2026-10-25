import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../strings.dart';
import '../together/discover.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import 'find_players_view.dart';
import 'share_watch_screen.dart';
import 'together_widgets.dart';

/// Live now: share plays their hosts opened to everyone, watched here the way a friend's is;
/// then parties listed in public, asked into or walked into.
class LiveNowPane extends StatefulWidget {
  const LiveNowPane({
    super.key,
    required this.hub,
    this.gameName,
    this.onProfile,
    this.onParty,
  });

  final TogetherHub hub;
  final String? Function(String titleId)? gameName;
  final ValueChanged<String>? onProfile;

  /// Goes to the party, once the reader joined one.
  final VoidCallback? onParty;

  @override
  State<LiveNowPane> createState() => _LiveNowPaneState();
}

class _LiveNowPaneState extends State<LiveNowPane> {
  Object? _error;

  Discover get _discover => widget.hub.discover;

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await _discover.loadLive();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    try {
      await step();
    } on Object catch (error) {
      if (!mounted) return;
      final words = error is TogetherProblem && error.code == 'full'
          ? texts.partyFull
          : togetherFailure(texts, error);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(words)));
    }
  }

  String _game(String titleId, String name) =>
      widget.gameName?.call(titleId) ?? name;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.hub.parties, widget.hub.sharePlays]),
      builder: (context, _) {
        final discover = _discover;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 16, 16),
            children: [
              SectionLabel(texts.liveNow),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  texts.liveLead,
                  style: const TextStyle(color: Colors.white38, fontSize: 12.5),
                ),
              ),
              if (!discover.liveLoaded && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              if (_error != null && !discover.liveLoaded)
                DiscoverFailure(error: _error!, retry: _load),
              if (discover.liveLoaded && discover.liveShares.isEmpty)
                DiscoverEmpty(texts.noLive),
              for (final share in discover.liveShares) _share(texts, share),
              SectionLabel(texts.publicParties),
              if (discover.liveLoaded && discover.publicParties.isEmpty)
                DiscoverEmpty(texts.noPublicParties),
              for (final party in discover.publicParties) _party(texts, party),
            ],
          ),
        );
      },
    );
  }

  Widget _share(Strings texts, PublicShare share) {
    final host = share.host;
    final invited = widget.hub.sharePlays.invites.any(
      (invite) => invite.sharePlayId == share.id,
    );
    final watchingIt = widget.hub.sharePlays.watching?.id == share.id;
    final mayWatch =
        invited || watchingIt || (share.join == PublicJoin.open && !share.full);
    return DiscoverCard(
      key: ValueKey('share ${share.id}'),
      leading: host == null
          ? const SizedBox.square(
              dimension: 38,
              child: Icon(Icons.live_tv_rounded, color: togetherAccent),
            )
          : GestureDetector(
              onTap: widget.onProfile == null
                  ? null
                  : () => widget.onProfile!(host.handle),
              child: Avatar(person: host, size: 38),
            ),
      title: _game(share.game.titleId, share.name(texts.language)),
      pill: DiscoverPill(texts.liveFlair, color: togetherError),
      lines: [
        [
          if (host != null) texts.hostedBy(host.displayName),
          texts.watching(share.viewers, share.maxViewers),
          if (share.language case final language?) texts.languageName(language),
        ].join(' · '),
      ],
      trailing: mayWatch
          ? FilledButton.tonalIcon(
              onPressed: () => openShareWatch(
                context,
                hub: widget.hub,
                sharePlayId: share.id,
              ),
              icon: const Icon(Icons.live_tv_rounded, size: 18),
              label: Text(texts.shareWatch),
            )
          : share.full
          ? Text(texts.full, style: const TextStyle(color: Colors.white38))
          : share.requested
          ? Text(
              texts.askedState,
              style: const TextStyle(color: togetherAccent, fontSize: 13),
            )
          : FilledButton.tonal(
              onPressed: () => _try(() => _discover.askShare(share.id)),
              child: Text(texts.askToJoin),
            ),
    );
  }

  Widget _party(Strings texts, PublicParty party) {
    final host = party.host;
    final parties = widget.hub.parties;
    final inIt = parties.party?.id == party.id;
    final invited = parties.invites.any((invite) => invite.partyId == party.id);
    final asked = party.requested || parties.asked.contains(party.id);
    final game = party.game;
    Future<void> join() async {
      await parties.join(party.id);
      widget.onParty?.call();
    }

    return DiscoverCard(
      key: ValueKey('party ${party.id}'),
      leading: host == null
          ? const SizedBox.square(
              dimension: 38,
              child: Icon(Icons.celebration_rounded, color: togetherAccent),
            )
          : GestureDetector(
              onTap: widget.onProfile == null
                  ? null
                  : () => widget.onProfile!(host.handle),
              child: Avatar(person: host, size: 38),
            ),
      title: game == null
          ? texts.noGameListed
          : _game(game.titleId, game.name(texts.language)),
      pill: DiscoverPill(
        party.join == PublicJoin.open
            ? texts.joinOpenFlair
            : texts.joinRequestFlair,
        color: party.join == PublicJoin.open ? togetherPlaying : togetherAway,
      ),
      lines: [
        [
          if (host != null) texts.hostedBy(host.displayName),
          texts.partyCount(party.size, party.max),
          if (party.language case final language?) texts.languageName(language),
        ].join(' · '),
      ],
      trailing: inIt
          ? Text(
              texts.inThisParty,
              style: const TextStyle(color: togetherPlaying, fontSize: 13),
            )
          : party.full
          ? Text(texts.full, style: const TextStyle(color: Colors.white38))
          : invited
          ? FilledButton(
              onPressed: () => _try(join),
              child: Text(texts.partyJoin),
            )
          : party.join == PublicJoin.open
          ? OutlinedButton(
              onPressed: () => _try(join),
              child: Text(texts.partyJoin),
            )
          : asked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texts.askedState,
                  style: const TextStyle(color: togetherAccent, fontSize: 13),
                ),
                TextButton(
                  onPressed: () =>
                      _try(() => _discover.cancelPartyAsk(party.id)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.white60,
                  ),
                  child: Text(texts.takeBack),
                ),
              ],
            )
          : FilledButton.tonal(
              onPressed: () => _try(() => _discover.askParty(party.id)),
              child: Text(texts.askToJoin),
            ),
    );
  }
}
