import 'dart:async';

import 'package:flutter/foundation.dart';

import 'join_codes.dart';
import 'people.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// At most eight in a party: its voice is a mesh, each phone talking to every other.
const maxPartySize = 8;

/// How a public party or share play lets people in: they ask first, or anyone walks in.
enum PublicJoin { request, open }

PublicJoin publicJoinFrom(Object? value) =>
    value == 'open' ? PublicJoin.open : PublicJoin.request;

/// A party in the public list, as its leader set it: how people get in, and the game and
/// language it is about (null: any).
class PartyListing {
  const PartyListing({required this.join, this.titleId, this.language});

  static PartyListing? fromJson(Object? json) => json is Map<String, dynamic>
      ? PartyListing(
          join: publicJoinFrom(json['join']),
          titleId: json['titleId'] as String?,
          language: json['language'] as String?,
        )
      : null;

  final PublicJoin join;
  final String? titleId;
  final String? language;

  Map<String, dynamic> toJson() => {
    'join': join.name,
    'titleId': titleId,
    'language': language,
  };
}

/// The party someone is in: who leads it, who is in it and who is invited, whether friends may
/// walk in, its public listing and who asked to join, and its voice call while one runs.
class Party {
  const Party({
    required this.id,
    required this.leaderId,
    required this.open,
    required this.members,
    required this.invited,
    required this.callId,
    required this.inCall,
    this.muted = const {},
    this.listing,
    this.requests = const [],
    this.deafened = const {},
    this.joinCode,
    this.discord,
  });

  factory Party.fromJson(Map<String, dynamic> json) {
    final call = json['call'];
    return Party(
      id: json['id'] as String,
      leaderId: json['leaderId'] as String? ?? '',
      open: json['privacy'] == 'friends',
      members: [
        for (final member in (json['members'] as List? ?? const []))
          Person.fromJson(member as Map<String, dynamic>),
      ],
      invited: [
        for (final person in (json['invited'] as List? ?? const []))
          Person.fromJson(person as Map<String, dynamic>),
      ],
      callId: call is Map<String, dynamic> ? call['id'] as String? : null,
      inCall: call is Map<String, dynamic>
          ? {for (final id in (call['in'] as List? ?? const [])) id as String}
          : const {},
      muted: call is Map<String, dynamic>
          ? {
              for (final id in (call['muted'] as List? ?? const []))
                id as String,
            }
          : const {},
      deafened: call is Map<String, dynamic>
          ? {
              for (final id in (call['deafened'] as List? ?? const []))
                id as String,
            }
          : const {},
      joinCode: JoinCode.fromJson(json['joinCode']),
      discord: json['discord'] as String?,
      listing: PartyListing.fromJson(json['public']),
      requests: [
        for (final person in (json['requests'] as List? ?? const []))
          Person.fromJson(person as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String leaderId;
  final bool open;
  final List<Person> members;
  final List<Person> invited;

  /// The party's voice call, and who is talking in it.
  final String? callId;
  final Set<String> inCall;

  /// Who in the call muted themselves; everyone sees it.
  final Set<String> muted;

  /// In the public list, and how; null when it is not.
  final PartyListing? listing;

  /// People who asked to join (members see them, the leader answers).
  final List<Person> requests;

  /// Who in the call hears nobody (and is muted too).
  final Set<String> deafened;

  /// The code the leader handed out, while it works (members see it).
  final JoinCode? joinCode;

  /// The party's Discord server or channel, set by the leader (members see it).
  final String? discord;

  bool get full => members.length >= maxPartySize;

  bool has(String userId) => members.any((person) => person.id == userId);

  Party copyWith({
    String? leaderId,
    bool? open,
    List<Person>? members,
    List<Person>? invited,
    String? Function()? callId,
    Set<String>? inCall,
    List<Person>? requests,
  }) => Party(
    id: id,
    leaderId: leaderId ?? this.leaderId,
    open: open ?? this.open,
    members: members ?? this.members,
    invited: invited ?? this.invited,
    callId: callId == null ? this.callId : callId(),
    inCall: inCall ?? this.inCall,
    muted: muted,
    listing: listing,
    requests: requests ?? this.requests,
    deafened: deafened,
    joinCode: joinCode,
    discord: discord,
  );
}

/// An invite to someone's party.
class PartyInvite {
  const PartyInvite({required this.partyId, required this.from, this.size});

  factory PartyInvite.fromJson(Map<String, dynamic> json) => PartyInvite(
    partyId: json['partyId'] as String,
    from: json['from'] is Map<String, dynamic>
        ? Person.fromJson(json['from'] as Map<String, dynamic>)
        : null,
    size: (json['size'] as num?)?.toInt(),
  );

  final String partyId;
  final Person? from;
  final int? size;
}

/// Parties on the phone: starting one, inviting friends, joining (by invite, or a friend's open
/// party), leaving; the party as everyone in it sees it, live.
class Parties extends ChangeNotifier {
  Parties({required this.account, required this.socket}) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;
  late final StreamSubscription<TogetherEvent> _events;

  Party? party;
  List<PartyInvite> invites = const [];

  /// Public parties this phone asked to join, waiting for their leader.
  Set<String> asked = const {};
  bool loaded = false;

  /// Set when the leader took this phone out of the party, until the next party.
  bool kicked = false;

  String? get _me => account.user?.id;

  Future<void> refresh() async {
    final json = await account.call('GET', 'me/party');
    party = json['party'] is Map<String, dynamic>
        ? Party.fromJson(json['party'] as Map<String, dynamic>)
        : null;
    invites = [
      for (final invite in (json['invites'] as List? ?? const []))
        PartyInvite.fromJson(invite as Map<String, dynamic>),
    ];
    asked = {
      for (final request in (json['requests'] as List? ?? const []))
        if (request is Map && request['partyId'] is String)
          request['partyId'] as String,
    };
    loaded = true;
    notifyListeners();
  }

  /// A new party with only this phone's account in it; whoever is in another leaves it first.
  Future<void> create({bool open = false}) async {
    _keep(
      await account.call('POST', 'parties', {
        'privacy': open ? 'friends' : 'invite',
      }),
    );
  }

  Future<void> invite(List<String> userIds) async {
    final current = party;
    if (current == null || userIds.isEmpty) return;
    _keep(
      await account.call('POST', 'parties/${current.id}/invites', {
        'userIds': userIds,
      }),
    );
  }

  Future<void> join(String partyId) async {
    _keep(await account.call('POST', 'parties/$partyId/join'));
    invites = invites.where((invite) => invite.partyId != partyId).toList();
    notifyListeners();
  }

  Future<void> decline(String partyId) async {
    invites = invites.where((invite) => invite.partyId != partyId).toList();
    notifyListeners();
    await account.call('POST', 'parties/$partyId/decline');
  }

  Future<void> leave() async {
    final current = party;
    if (current == null) return;
    party = null;
    notifyListeners();
    await account.call('POST', 'parties/${current.id}/leave');
  }

  /// Leader only: whether the leader's friends may join without an invite.
  Future<void> setOpen(bool open) async {
    final current = party;
    if (current == null) return;
    _keep(
      await account.call('PATCH', 'parties/${current.id}', {
        'privacy': open ? 'friends' : 'invite',
      }),
    );
  }

  /// Leader only: lists the party in public (anyone may ask, or walk in), or takes it off the
  /// list with null.
  Future<void> setPublic(PartyListing? listing) async {
    final current = party;
    if (current == null) return;
    _keep(
      await account.call('PATCH', 'parties/${current.id}', {
        'public': listing?.toJson(),
      }),
    );
  }

  /// Leader only: a join code in place of the one before (24 hours unless [hours] says).
  Future<JoinCode?> makeCode({int? hours}) async {
    final current = party;
    if (current == null) return null;
    final code = JoinCode.fromJson(
      await account.call('POST', 'parties/${current.id}/code', {
        'hours': ?hours,
      }),
    );
    if (party?.id == current.id && code != null) {
      party = _with(party!, joinCode: () => code);
      notifyListeners();
    }
    return code;
  }

  /// Leader only: the join code stops working.
  Future<void> stopCode() async {
    final current = party;
    if (current == null) return;
    await account.call('DELETE', 'parties/${current.id}/code');
    if (party?.id == current.id) {
      party = _with(party!, joinCode: () => null);
      notifyListeners();
    }
  }

  /// Leader only: the party's Discord invite or channel link, or none with null.
  Future<void> setDiscord(String? link) async {
    final current = party;
    if (current == null) return;
    _keep(
      await account.call('PATCH', 'parties/${current.id}', {'discord': link}),
    );
  }

  Party _with(Party p, {JoinCode? Function()? joinCode}) => Party(
    id: p.id,
    leaderId: p.leaderId,
    open: p.open,
    members: p.members,
    invited: p.invited,
    callId: p.callId,
    inCall: p.inCall,
    muted: p.muted,
    listing: p.listing,
    requests: p.requests,
    deafened: p.deafened,
    joinCode: joinCode == null ? p.joinCode : joinCode(),
    discord: p.discord,
  );

  /// Leader only: lets someone who asked in (an invite they join with), or says no.
  Future<void> answerRequest(String userId, {required bool accept}) async {
    final current = party;
    if (current == null) return;
    _keep(
      await account.call(
        'POST',
        'parties/${current.id}/requests/$userId/${accept ? 'accept' : 'decline'}',
      ),
    );
  }

  /// Leader only: someone out of the party.
  Future<void> kick(String userId) async {
    final current = party;
    if (current == null) return;
    await account.call('POST', 'parties/${current.id}/kick', {
      'userId': userId,
    });
  }

  void _keep(Map<String, dynamic> json) {
    party = Party.fromJson(json);
    kicked = false;
    notifyListeners();
  }

  void clear() {
    party = null;
    invites = const [];
    asked = const {};
    loaded = false;
    kicked = false;
    notifyListeners();
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    final current = party;
    final ours = current != null && data['partyId'] == current.id;
    if (ours) {
      _ours(event.type, data, current);
      return;
    }
    switch (event.type) {
      case 'live.ready':
        refresh().catchError((_) {});
      case 'party.request_answered':
        asked = {...asked}..remove(data['partyId']);
        notifyListeners();
      case 'party.invite':
        final invite = PartyInvite.fromJson(data);
        invites = [
          ...invites.where((known) => known.partyId != invite.partyId),
          invite,
        ];
        notifyListeners();
      case 'party.updated':
        final updated = Party.fromJson(data);
        if (current?.id == updated.id ||
            (current == null && updated.has(_me ?? ''))) {
          party = updated;
          notifyListeners();
        }
    }
  }

  /// What happened in the party this phone is in.
  void _ours(String type, Map<String, dynamic> data, Party current) {
    switch (type) {
      case 'party.member_joined':
        final member = Person.fromJson(data['member'] as Map<String, dynamic>);
        if (current.has(member.id)) return;
        party = current.copyWith(
          members: [...current.members, member],
          invited: current.invited.where((p) => p.id != member.id).toList(),
        );
        notifyListeners();
      case 'party.member_left':
        final gone = data['userId'] as String?;
        if (gone == _me) {
          party = null;
          kicked = data['reason'] == 'kicked';
        } else {
          party = current.copyWith(
            leaderId: data['leaderId'] as String?,
            members: current.members.where((p) => p.id != gone).toList(),
            inCall: {...current.inCall}..remove(gone),
          );
        }
        notifyListeners();
      case 'party.ended':
        party = null;
        notifyListeners();
      case 'party.request':
        final from = data['from'];
        if (from is! Map<String, dynamic>) return;
        final person = Person.fromJson(from);
        party = current.copyWith(
          requests: [
            ...current.requests.where((p) => p.id != person.id),
            person,
          ],
        );
        notifyListeners();
      case 'party.request_cancelled':
        party = current.copyWith(
          requests: current.requests
              .where((p) => p.id != data['userId'])
              .toList(),
        );
        notifyListeners();
      case 'call.joined':
        party = current.copyWith(
          callId: () => data['callId'] as String?,
          inCall: {...current.inCall, data['userId'] as String},
        );
        notifyListeners();
      case 'call.left':
        party = current.copyWith(
          inCall: {...current.inCall}..remove(data['userId']),
        );
        notifyListeners();
      case 'call.ended':
        party = current.copyWith(callId: () => null, inCall: const {});
        notifyListeners();
    }
  }

  @override
  void dispose() {
    _events.cancel();
    super.dispose();
  }
}
