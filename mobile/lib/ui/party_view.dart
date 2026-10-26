import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../join_strings.dart';
import '../safety_strings.dart';
import '../strings.dart';
import '../together/join_codes.dart';
import '../together/parties.dart';
import '../together/people.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import '../together/voice.dart';
import 'ask_first.dart';
import 'find_players_view.dart';
import 'join_code_view.dart';
import 'together_widgets.dart';

/// The party: without one, a way to start one and the invites and friends' open parties to
/// join; in one, everyone in it on the left, inviting friends and leaving on the right.
class PartyPane extends StatefulWidget {
  const PartyPane({super.key, required this.hub, this.gameName});

  final TogetherHub hub;
  final String? Function(String titleId)? gameName;

  @override
  State<PartyPane> createState() => _PartyPaneState();
}

class _PartyPaneState extends State<PartyPane> {
  String? _error;
  bool _busy = false;
  late final _codes = JoinCodes(widget.hub.account);

  @override
  void initState() {
    super.initState();
    widget.hub.parties.refresh().catchError((_) {});
    if (!widget.hub.friends.loaded) {
      widget.hub.friends.refresh().catchError((_) {});
    }
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } on Object catch (error) {
      _error = error is TogetherProblem && error.code == 'full'
          ? texts.partyFull
          : togetherFailure(texts, error);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.hub.parties,
        widget.hub.friends,
        widget.hub.voice,
      ]),
      builder: (context, _) {
        final party = widget.hub.parties.party;
        return party == null ? _noParty(texts) : _inParty(texts, party);
      },
    );
  }

  Widget get _errorText => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      _error!,
      style: const TextStyle(color: togetherError, fontSize: 13),
    ),
  );

  static const _title = TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  Widget _noParty(Strings texts) {
    final parties = widget.hub.parties;
    final open = widget.hub.friends.friends
        .where((f) => f.presence.partyId != null && f.presence.partyOpen)
        .toList();
    final start = <Widget>[
      Text(texts.party, style: _title),
      const SizedBox(height: 6),
      Text(
        texts.partyIntro,
        style: const TextStyle(color: Colors.white60, fontSize: 14),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _busy ? null : () => _try(parties.create),
        icon: const Icon(Icons.celebration_rounded, size: 18),
        label: Text(texts.partyStart),
      ),
      if (parties.kicked)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            texts.partyKicked,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      if (_error != null) _errorText,
    ];
    final join = <Widget>[
      if (parties.invites.isNotEmpty) ...[
        SectionLabel(texts.partyInvites),
        for (final invite in parties.invites)
          _Row(
            person: invite.from,
            title: invite.from?.shownName ?? texts.party,
            subtitle: invite.size == null
                ? null
                : texts.partyInviteFrom(
                    '@${invite.from?.handle ?? ''}',
                    invite.size!,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _try(() => parties.decline(invite.partyId)),
                  child: Text(
                    texts.decline,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _try(() => parties.join(invite.partyId)),
                  child: Text(texts.partyJoin),
                ),
              ],
            ),
          ),
      ],
      if (open.isNotEmpty) ...[
        SectionLabel(texts.partyFriendsParties),
        for (final friend in open)
          _Row(
            person: friend.person,
            title: friend.person.shownName,
            subtitle: friend.person.handleLine,
            trailing: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _try(() => parties.join(friend.presence.partyId!)),
              child: Text(texts.partyJoin),
            ),
          ),
      ],
      JoinWithCode(codes: _codes, gameName: widget.gameName),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // A small phone: starting a party, then the invites and codes under it.
        if (box.maxWidth < 600) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
            children: [...start, ...join],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: start,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(4, 0, 18, 18),
                children: join,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _voiceCard(Strings texts, Party party, Voice voice) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: voice.active ? const Color(0x144CD964) : const Color(0x0DFFFFFF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: voice.active ? const Color(0x554CD964) : const Color(0x14FFFFFF),
      ),
    ),
    child: _voiceCardBody(texts, party, voice, _try),
  );

  Widget _inParty(Strings texts, Party party) {
    final me = widget.hub.me;
    final leader = party.leaderId == me;
    final parties = widget.hub.parties;
    final voice = widget.hub.voice;
    final invitable = widget.hub.friends.friends
        .where(
          (f) =>
              !party.has(f.person.id) &&
              !party.invited.any((p) => p.id == f.person.id),
        )
        .toList();
    final main = <Widget>[
      Row(
        children: [
          Text(texts.party, style: _title),
          const SizedBox(width: 10),
          Text(
            '${party.members.length}/$maxPartySize',
            style: const TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final member in party.members)
            _Member(
              person: member,
              leader: member.id == party.leaderId,
              inVoice:
                  party.inCall.contains(member.id) ||
                  (member.id == me && voice.active),
              muted: member.id == me
                  ? voice.active && (voice.muted || voice.deafened)
                  : party.muted.contains(member.id),
              deafened: member.id == me
                  ? voice.active && voice.deafened
                  : party.deafened.contains(member.id),
              ring:
                  (member.id == me
                      ? voice.speaking
                      : voice.speakingOf(member.id))
                  ? togetherPlaying
                  : null,
              onKick: leader && member.id != me
                  ? () async {
                      final sure = await askFirst(
                        context,
                        question: texts.askKick(member.shownName),
                        action: texts.partyKick,
                      );
                      if (sure && mounted) {
                        await _try(() => parties.kick(member.id));
                      }
                    }
                  : null,
            ),
        ],
      ),
      if (party.invited.isNotEmpty) ...[
        SectionLabel(texts.partyInvited),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final person in party.invited)
              Chip(
                avatar: Avatar(person: person, size: 22),
                label: Text(person.shownName),
                backgroundColor: const Color(0x14FFFFFF),
                side: BorderSide.none,
                labelStyle: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ],
      if (party.requests.isNotEmpty) ...[
        SectionLabel(texts.askingToJoin),
        for (final person in party.requests)
          _Row(
            person: person,
            title: person.shownName,
            subtitle: person.handleLine,
            trailing: leader
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _try(
                          () => parties.answerRequest(person.id, accept: false),
                        ),
                        child: Text(
                          texts.decline,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      FilledButton(
                        onPressed: party.full
                            ? null
                            : () => _try(
                                () => parties.answerRequest(
                                  person.id,
                                  accept: true,
                                ),
                              ),
                        child: Text(texts.accept),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
      ],
      if (_error != null) _errorText,
    ];
    final side = <Widget>[
      SectionLabel(texts.voice),
      _voiceCard(texts, party, voice),
      SectionLabel(texts.partyInviteFriends),
      if (invitable.isEmpty)
        Text(
          texts.partyNoFriends,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      for (final friend in invitable)
        _Row(
          person: friend.person,
          presence: friend.presence.state,
          title: friend.person.shownName,
          trailing: TextButton(
            onPressed: party.full
                ? null
                : () => _try(() => parties.invite([friend.person.id])),
            child: Text(texts.partyInvite),
          ),
        ),
      if (leader) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            texts.partyOpen,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: Text(
            texts.partyOpenDetail,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          value: party.open,
          onChanged: (open) => _try(() => parties.setOpen(open)),
        ),
        _publicListing(texts, party),
      ],
      PartyCode(parties: parties, party: party, leader: leader, run: _try),
      PartyDiscord(parties: parties, party: party, leader: leader, run: _try),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () async {
          final sure = await askFirst(
            context,
            question: texts.askLeaveParty,
            action: texts.partyLeave,
          );
          if (sure && mounted) await _try(parties.leave);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: togetherError,
          side: const BorderSide(color: Color(0x66FF8A80)),
        ),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(texts.partyLeave),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        // A small phone has no room for the party beside the voice and invite column: one
        // list, the column under the members.
        if (box.maxWidth < 600) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
            children: [...main, const SizedBox(height: 6), ...side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 16, 14, 18),
                children: main,
              ),
            ),
            const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
            SizedBox(
              width: 262,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 14, 14),
                children: side,
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on _PartyPaneState {
  /// Leader only: the party in the public list or not, how people get in, and its language.
  Widget _publicListing(Strings texts, Party party) {
    final listing = party.listing;
    final parties = widget.hub.parties;
    void list(PublicJoin? join, {String? Function()? language}) => _try(
      () => parties.setPublic(
        join == null
            ? null
            : PartyListing(
                join: join,
                titleId: listing?.titleId,
                language: language == null ? listing?.language : language(),
              ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          texts.partyPublic,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        const SizedBox(height: 6),
        ChoiceRow(
          children: [
            ChoicePill(
              label: texts.publicOff,
              selected: listing == null,
              onTap: listing == null ? null : () => list(null),
            ),
            for (final (join, label) in [
              (PublicJoin.request, texts.joinModeRequest),
              (PublicJoin.open, texts.joinModeOpen),
            ])
              ChoicePill(
                label: label,
                selected: listing?.join == join,
                onTap: listing?.join == join ? null : () => list(join),
              ),
          ],
        ),
        if (listing != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                texts.listLanguage,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<int>(
                color: const Color(0xFF1A1D27),
                tooltip: texts.listLanguage,
                onSelected: (index) => list(
                  listing.join,
                  language: () =>
                      index == 0 ? null : offeredLanguages[index - 1],
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 0, child: Text(texts.noLanguage)),
                  for (final (index, code) in offeredLanguages.indexed)
                    PopupMenuItem(
                      value: index + 1,
                      child: Text(texts.languageName(code)),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        listing.language == null
                            ? texts.noLanguage
                            : texts.languageName(listing.language!),
                        style: const TextStyle(
                          color: togetherAccent,
                          fontSize: 13.5,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: togetherAccent,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          texts.partyPublicHint,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

/// Joining the voice, or, in it: who is heard, mute and leave.
Widget _voiceCardBody(
  Strings texts,
  Party party,
  Voice voice,
  Future<void> Function(Future<void> Function()) run,
) {
  if (!voice.active) {
    final others = party.inCall.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: voice.joining ? null : () => run(voice.join),
          icon: voice.joining
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.headset_mic_rounded, size: 18),
          label: Text(texts.voiceJoin),
        ),
        const SizedBox(height: 6),
        Text(
          switch (voice.problem) {
            VoiceProblem.microphone => texts.voiceMicDenied,
            VoiceProblem.failed => texts.voiceFailed,
            null => others > 0 ? texts.voiceInCall(others) : texts.voicePad,
          },
          style: TextStyle(
            color: voice.problem == null ? Colors.white54 : togetherError,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
  final peers = voice.peers;
  final silent = voice.muted || voice.deafened;
  final connected = peers.where((p) => p.state == 'connected').length;
  final connecting = peers.length - connected;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        peers.isEmpty
            ? texts.voiceAlone
            : connecting > 0
            ? texts.voiceConnecting(connecting)
            : texts.voiceConnected(connected),
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => voice.setMuted(!silent),
              style: silent
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0x33FF8A80),
                      foregroundColor: togetherError,
                    )
                  : null,
              icon: Icon(
                silent ? Icons.mic_off_rounded : Icons.mic_rounded,
                size: 18,
              ),
              label: Text(silent ? texts.voiceUnmute : texts.voiceMute),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: voice.deafened ? texts.undeafen : texts.deafen,
            isSelected: voice.deafened,
            onPressed: () => voice.setDeafened(!voice.deafened),
            style: voice.deafened
                ? IconButton.styleFrom(
                    backgroundColor: const Color(0x33FF8A80),
                    foregroundColor: togetherError,
                  )
                : null,
            icon: Icon(
              voice.deafened
                  ? Icons.headset_off_rounded
                  : Icons.headset_rounded,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: texts.voiceLeave,
            onPressed: () => run(voice.leave),
            color: togetherError,
            icon: const Icon(Icons.call_end_rounded, size: 18),
          ),
        ],
      ),
    ],
  );
}

/// Someone in the party: their picture with a ring while they speak, a headset while in voice
/// (crossed out when muted), a crown for the leader.
class _Member extends StatelessWidget {
  const _Member({
    required this.person,
    required this.leader,
    required this.inVoice,
    this.ring,
    this.muted = false,
    this.deafened = false,
    this.onKick,
  });

  final Person person;
  final bool leader;
  final bool inVoice;

  /// Green while they speak.
  final Color? ring;
  final bool muted;
  final bool deafened;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final card = SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Avatar(person: person, size: 60, ring: ring),
              if (inVoice)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: togetherPanel,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      deafened
                          ? Icons.headset_off_rounded
                          : muted
                          ? Icons.mic_off_rounded
                          : Icons.headset_mic_rounded,
                      size: 15,
                      color: muted || deafened
                          ? togetherError
                          : togetherPlaying,
                      semanticLabel: deafened ? texts.deafened : null,
                    ),
                  ),
                ),
              if (leader)
                const Positioned(
                  left: -4,
                  top: -6,
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    size: 18,
                    color: togetherAway,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            person.shownName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            leader ? texts.partyLeader : person.handleLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ],
      ),
    );
    final kick = onKick;
    if (kick == null) return card;
    // Chosen once the menu is gone, so the question it asks has the screen to itself.
    return PopupMenuButton<bool>(
      color: const Color(0xFF1A1D27),
      tooltip: person.shownName,
      onSelected: (_) => kick(),
      itemBuilder: (context) => [
        PopupMenuItem(value: true, child: Text(texts.partyKick)),
      ],
      child: card,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.person,
    required this.title,
    this.subtitle,
    this.presence,
    required this.trailing,
  });

  final Person? person;
  final String title;
  final String? subtitle;
  final PresenceState? presence;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        if (person != null)
          Avatar(person: person!, size: 34, presence: presence)
        else
          const SizedBox.square(
            dimension: 34,
            child: Icon(Icons.celebration_rounded, color: togetherAccent),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}
