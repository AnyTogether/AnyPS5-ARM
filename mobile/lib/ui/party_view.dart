import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/parties.dart';
import '../together/people.dart';
import '../together/together_account.dart';
import '../together/together_hub.dart';
import 'together_widgets.dart';

/// The party: without one, a way to start one and the invites and friends' open parties to
/// join; in one, everyone in it on the left, inviting friends and leaving on the right.
class PartyPane extends StatefulWidget {
  const PartyPane({super.key, required this.hub});

  final TogetherHub hub;

  @override
  State<PartyPane> createState() => _PartyPaneState();
}

class _PartyPaneState extends State<PartyPane> {
  String? _error;
  bool _busy = false;

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
      listenable: Listenable.merge([widget.hub.parties, widget.hub.friends]),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (_error != null) _errorText,
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 0, 18, 18),
            children: [
              if (parties.invites.isNotEmpty) ...[
                SectionLabel(texts.partyInvites),
                for (final invite in parties.invites)
                  _Row(
                    person: invite.from,
                    title: invite.from?.displayName ?? texts.party,
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
                          onPressed: () =>
                              _try(() => parties.decline(invite.partyId)),
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
                    title: friend.person.displayName,
                    subtitle: '@${friend.person.handle}',
                    trailing: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _try(
                              () => parties.join(friend.presence.partyId!),
                            ),
                      child: Text(texts.partyJoin),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _inParty(Strings texts, Party party) {
    final me = widget.hub.me;
    final leader = party.leaderId == me;
    final parties = widget.hub.parties;
    final invitable = widget.hub.friends.friends
        .where(
          (f) =>
              !party.has(f.person.id) &&
              !party.invited.any((p) => p.id == f.person.id),
        )
        .toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 14, 18),
            children: [
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
                      inVoice: party.inCall.contains(member.id),
                      onKick: leader && member.id != me
                          ? () => _try(() => parties.kick(member.id))
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
                        label: Text(person.displayName),
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
              if (_error != null) _errorText,
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
        SizedBox(
          width: 262,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 14, 14),
            children: [
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
                  title: friend.person.displayName,
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
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _try(parties.leave),
                style: OutlinedButton.styleFrom(
                  foregroundColor: togetherError,
                  side: const BorderSide(color: Color(0x66FF8A80)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(texts.partyLeave),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Someone in the party: their picture, a headset while in voice, a crown for the leader.
class _Member extends StatelessWidget {
  const _Member({
    required this.person,
    required this.leader,
    required this.inVoice,
    this.onKick,
  });

  final Person person;
  final bool leader;
  final bool inVoice;
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
              Avatar(person: person, size: 60),
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
                    child: const Icon(
                      Icons.headset_mic_rounded,
                      size: 15,
                      color: togetherPlaying,
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
            person.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            leader ? texts.partyLeader : '@${person.handle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ],
      ),
    );
    final kick = onKick;
    if (kick == null) return card;
    return PopupMenuButton<void>(
      color: const Color(0xFF1A1D27),
      tooltip: person.displayName,
      itemBuilder: (context) => [
        PopupMenuItem(onTap: kick, child: Text(texts.partyKick)),
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
