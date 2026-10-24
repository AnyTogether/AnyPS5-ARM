import 'dart:async';

import 'package:flutter/foundation.dart';

export 'parties.dart' show PublicJoin;

import 'activity.dart';
import 'parties.dart';
import 'people.dart';
import 'profiles.dart';
import 'share_play.dart';
import 'together_account.dart';
import 'together_socket.dart';

/// What a looking-for-group post is for: co-op over share play, the game's own online, a party
/// to talk in, help with a trophy.
enum LfgPurpose { coop, online, party, trophies }

LfgPurpose? lfgPurposeFrom(Object? value) =>
    LfgPurpose.values.where((purpose) => purpose.name == value).firstOrNull;

enum LfgStatus { open, full, closed, expired, removed }

/// Where an "I'm in" stands: waiting for the poster, let in, or not this time.
enum LfgAnswer { pending, accepted, declined }

LfgAnswer _answerFrom(Object? value) => switch (value) {
  'accepted' => LfgAnswer.accepted,
  'declined' => LfgAnswer.declined,
  _ => LfgAnswer.pending,
};

/// Where a player the poster let in was invited: the poster's party, or the share play they
/// host.
class LfgInvite {
  const LfgInvite({required this.share, required this.id});

  static LfgInvite? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['id'] is! String) return null;
    return LfgInvite(
      share: json['kind'] == 'share_play',
      id: json['id'] as String,
    );
  }

  final bool share;
  final String id;
}

/// Someone who said "I'm in" to the poster's post.
class LfgRequest {
  const LfgRequest({
    required this.person,
    required this.status,
    this.invite,
    this.createdAt,
  });

  factory LfgRequest.fromJson(Map<String, dynamic> json) => LfgRequest(
    person: Person.fromJson(json['user'] as Map<String, dynamic>),
    status: _answerFrom(json['status']),
    invite: LfgInvite.fromJson(json['invite']),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  final Person person;
  final LfgAnswer status;
  final LfgInvite? invite;
  final DateTime? createdAt;
}

/// The reader's own "I'm in" on someone's post.
class LfgMyRequest {
  const LfgMyRequest(this.status, [this.invite]);

  static LfgMyRequest? fromJson(Object? json) => json is Map<String, dynamic>
      ? LfgMyRequest(
          _answerFrom(json['status']),
          LfgInvite.fromJson(json['invite']),
        )
      : null;

  final LfgAnswer status;
  final LfgInvite? invite;
}

/// A post on the looking-for-group board.
class LfgPost {
  const LfgPost({
    required this.id,
    required this.author,
    required this.game,
    required this.purpose,
    required this.languages,
    required this.slots,
    required this.filled,
    required this.expiresAt,
    required this.status,
    this.startsAt,
    this.region,
    this.note,
    this.mine = false,
    this.myRequest,
    this.requests = const [],
  });

  factory LfgPost.fromJson(Map<String, dynamic> json) {
    final game = json['game'];
    final titleId = json['titleId'] as String? ?? '';
    return LfgPost(
      id: json['id'] as String,
      author: Person.fromJson(json['author'] as Map<String, dynamic>),
      game: GameRef(
        titleId: titleId,
        names: game is Map ? namesFrom(game['names']) : const {},
        iconUrl: game is Map ? game['iconUrl'] as String? : null,
      ),
      purpose: lfgPurposeFrom(json['purpose']) ?? LfgPurpose.online,
      startsAt: DateTime.tryParse(json['startsAt'] as String? ?? ''),
      languages: [
        for (final language in (json['languages'] as List? ?? const []))
          '$language',
      ],
      region: json['region'] as String?,
      slots: (json['slots'] as num? ?? 1).toInt(),
      filled: (json['filled'] as num? ?? 0).toInt(),
      note: json['note'] as String?,
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.now(),
      status:
          LfgStatus.values.where((s) => s.name == json['status']).firstOrNull ??
          LfgStatus.open,
      mine: json['mine'] == true,
      myRequest: LfgMyRequest.fromJson(json['myRequest']),
      requests: [
        for (final request in (json['requests'] as List? ?? const []))
          LfgRequest.fromJson(request as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final Person author;
  final GameRef game;
  final LfgPurpose purpose;

  /// null: now.
  final DateTime? startsAt;
  final List<String> languages;
  final String? region;
  final int slots;

  /// Players let in so far.
  final int filled;
  final String? note;
  final DateTime expiresAt;
  final LfgStatus status;
  final bool mine;
  final LfgMyRequest? myRequest;

  /// Who wants in; only the poster sees them.
  final List<LfgRequest> requests;

  int get left => slots > filled ? slots - filled : 0;

  /// "I'm in"s the poster has not answered.
  int get waiting =>
      requests.where((request) => request.status == LfgAnswer.pending).length;

  LfgPost copyWith({LfgStatus? status, LfgMyRequest? Function()? myRequest}) =>
      LfgPost(
        id: id,
        author: author,
        game: game,
        purpose: purpose,
        startsAt: startsAt,
        languages: languages,
        region: region,
        slots: slots,
        filled: filled,
        note: note,
        expiresAt: expiresAt,
        status: status ?? this.status,
        mine: mine,
        myRequest: myRequest == null ? this.myRequest : myRequest(),
        requests: requests,
      );
}

/// A game with open posts, for the board's game filter.
class LfgGame {
  const LfgGame(this.game, this.posts);

  factory LfgGame.fromJson(Map<String, dynamic> json) =>
      LfgGame(GameRef.fromJson(json), (json['posts'] as num? ?? 0).toInt());

  final GameRef game;
  final int posts;
}

/// What the board shows: one game or all, what for, which language, and only what starts
/// within half an hour.
class LfgFilter {
  const LfgFilter({
    this.titleId,
    this.purpose,
    this.language,
    this.now = false,
  });

  final String? titleId;
  final LfgPurpose? purpose;
  final String? language;
  final bool now;

  /// The API path with this filter.
  String query({String? before}) {
    final params = [
      if (titleId != null) 'titleId=$titleId',
      if (purpose != null) 'purpose=${purpose!.name}',
      if (language != null) 'language=$language',
      if (now) 'now=1',
      if (before != null) 'before=$before',
    ];
    return params.isEmpty ? 'lfg' : 'lfg?${params.join('&')}';
  }

  /// The gateway topic of the posts this filter shows: one game's, or the whole board.
  String get topic => titleId == null ? 'lfg' : 'lfg:$titleId';

  LfgFilter copyWith({
    String? Function()? titleId,
    LfgPurpose? Function()? purpose,
    String? Function()? language,
    bool? now,
  }) => LfgFilter(
    titleId: titleId == null ? this.titleId : titleId(),
    purpose: purpose == null ? this.purpose : purpose(),
    language: language == null ? this.language : language(),
    now: now ?? this.now,
  );
}

/// What would make the API turn a new post down.
enum LfgDraftIssue { game, languages, slots, note }

/// A title ID as the API takes it: four capitals and five digits.
final titleIdPattern = RegExp(r'^[A-Z]{4}[0-9]{5}$');

/// A post being written: which game and what for, when, in which languages, how many players,
/// a note, and how long it stays up.
class LfgDraft {
  const LfgDraft({
    required this.titleId,
    required this.purpose,
    required this.languages,
    required this.slots,
    this.startIn,
    this.hours = 3,
    this.note = '',
  });

  /// A post lives at most a day, says at most this much, and lists up to three languages.
  static const maxHours = 24;
  static const maxNote = 140;
  static const maxLanguages = 3;

  /// Co-op goes over share play, which hands out pads 2 to 4; everyone else joins a party of
  /// eight.
  static int maxSlots(LfgPurpose purpose) =>
      purpose == LfgPurpose.coop ? 3 : maxPartySize - 1;

  final String titleId;
  final LfgPurpose purpose;
  final List<String> languages;
  final int slots;

  /// From now; null for now.
  final Duration? startIn;

  /// How long it stays up after it starts.
  final int hours;
  final String note;

  LfgDraftIssue? get issue {
    if (!titleIdPattern.hasMatch(titleId)) return LfgDraftIssue.game;
    if (languages.isEmpty || languages.length > maxLanguages) {
      return LfgDraftIssue.languages;
    }
    if (slots < 1 || slots > maxSlots(purpose)) return LfgDraftIssue.slots;
    if (note.trim().length > maxNote) return LfgDraftIssue.note;
    return null;
  }

  /// The same draft for another purpose, the players cut down to what it has room for.
  LfgDraft withPurpose(LfgPurpose next) => LfgDraft(
    titleId: titleId,
    purpose: next,
    languages: languages,
    slots: slots.clamp(1, maxSlots(next)),
    startIn: startIn,
    hours: hours,
    note: note,
  );

  Map<String, dynamic> toJson(DateTime now) {
    final start = now.add(startIn ?? Duration.zero);
    final latest = now.add(const Duration(hours: maxHours));
    var ends = start.add(Duration(hours: hours));
    if (ends.isAfter(latest)) ends = latest;
    final trimmed = note.trim();
    return {
      'titleId': titleId,
      'purpose': purpose.name,
      if (startIn != null) 'startsAt': start.toUtc().toIso8601String(),
      'languages': languages,
      'slots': slots,
      if (trimmed.isNotEmpty) 'note': trimmed,
      'expiresAt': ends.toUtc().toIso8601String(),
    };
  }
}

GameRef? _gameOf(Map<String, dynamic> json) {
  final titleId = json['titleId'];
  if (titleId is! String) return null;
  final game = json['game'];
  return GameRef(
    titleId: titleId,
    names: game is Map ? namesFrom(game['names']) : const {},
    iconUrl: game is Map ? game['iconUrl'] as String? : null,
  );
}

/// A party its leader listed in public.
class PublicParty {
  const PublicParty({
    required this.id,
    required this.join,
    required this.size,
    required this.max,
    this.host,
    this.game,
    this.language,
    this.requested = false,
  });

  factory PublicParty.fromJson(Map<String, dynamic> json) => PublicParty(
    id: json['id'] as String,
    host: json['host'] is Map<String, dynamic>
        ? Person.fromJson(json['host'] as Map<String, dynamic>)
        : null,
    game: _gameOf(json),
    language: json['language'] as String?,
    join: publicJoinFrom(json['join']),
    size: (json['size'] as num? ?? 0).toInt(),
    max: (json['max'] as num? ?? maxPartySize).toInt(),
    requested: json['requested'] == true,
  );

  final String id;
  final Person? host;

  /// What it is about; null for any game.
  final GameRef? game;
  final String? language;
  final PublicJoin join;
  final int size;
  final int max;

  /// The reader asked to join and waits.
  final bool requested;

  bool get full => size >= max;

  PublicParty asked(bool requested) => PublicParty(
    id: id,
    host: host,
    game: game,
    language: language,
    join: join,
    size: size,
    max: max,
    requested: requested,
  );
}

/// A share play its host listed in public, under Live now while it is live.
class PublicShare {
  const PublicShare({
    required this.id,
    required this.game,
    required this.join,
    required this.viewers,
    required this.maxViewers,
    this.host,
    this.title,
    this.language,
    this.live = false,
    this.requested = false,
  });

  factory PublicShare.fromJson(Map<String, dynamic> json) => PublicShare(
    id: json['id'] as String,
    host: json['host'] is Map<String, dynamic>
        ? Person.fromJson(json['host'] as Map<String, dynamic>)
        : null,
    game:
        _gameOf(json) ?? const GameRef(titleId: '', names: <String, String>{}),
    title: json['title'] as String?,
    language: json['language'] as String?,
    join: publicJoinFrom(json['join']),
    live: json['live'] == true,
    viewers: (json['viewers'] as num? ?? 0).toInt(),
    maxViewers: (json['maxViewers'] as num? ?? 0).toInt(),
    requested: json['requested'] == true,
  );

  final String id;
  final Person? host;
  final GameRef game;

  /// The game's name as the host's launcher shows it.
  final String? title;
  final String? language;
  final PublicJoin join;
  final bool live;
  final int viewers;
  final int maxViewers;
  final bool requested;

  bool get full => maxViewers > 0 && viewers >= maxViewers;

  /// The catalogue's name, then the launcher's, then the title ID.
  String name(String language) =>
      localName(game.names, language) ?? title ?? game.titleId;

  PublicShare asked(bool requested) => PublicShare(
    id: id,
    host: host,
    game: game,
    title: title,
    language: language,
    join: join,
    live: live,
    viewers: viewers,
    maxViewers: maxViewers,
    requested: requested,
  );
}

/// Whether the account shows in discovery, what its owner chose (null: it follows whether the
/// library is public), and the languages they play in.
class DiscoverySettings {
  const DiscoverySettings({
    required this.discoverable,
    this.chosen,
    this.languages = const [],
  });

  factory DiscoverySettings.fromJson(Map<String, dynamic> json) =>
      DiscoverySettings(
        discoverable: json['discoverable'] == true,
        chosen: json['chosen'] as bool?,
        languages: [
          for (final language in (json['languages'] as List? ?? const []))
            '$language',
        ],
      );

  /// Languages one may list.
  static const maxLanguages = 5;

  final bool discoverable;
  final bool? chosen;
  final List<String> languages;
}

/// Why someone is suggested.
sealed class SuggestionReason {
  const SuggestionReason();

  static SuggestionReason? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return switch (json['kind']) {
      'game' when json['titleId'] is String => GameReason(
        GameRef.fromJson(json),
      ),
      'friends' => FriendsReason((json['count'] as num? ?? 0).toInt()),
      'language' when json['language'] is String => LanguageReason(
        json['language'] as String,
      ),
      _ => null,
    };
  }
}

/// You both play this.
class GameReason extends SuggestionReason {
  const GameReason(this.game);
  final GameRef game;
}

/// Friends in common.
class FriendsReason extends SuggestionReason {
  const FriendsReason(this.count);
  final int count;
}

/// They speak a language you play in.
class LanguageReason extends SuggestionReason {
  const LanguageReason(this.language);
  final String language;
}

/// Someone the reader may know or want to play with, and why.
class Suggestion {
  const Suggestion({
    required this.person,
    required this.friendship,
    this.presence,
    this.reasons = const [],
  });

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
    person: Person.fromJson(json['user'] as Map<String, dynamic>),
    friendship: switch (json['friendship']) {
      'friends' => Friendship.friends,
      'pending_out' => Friendship.pendingOut,
      'pending_in' => Friendship.pendingIn,
      _ => Friendship.none,
    },
    presence: json['presence'] is Map<String, dynamic>
        ? Presence.fromJson(json['presence'] as Map<String, dynamic>)
        : null,
    reasons: [
      for (final reason in (json['reasons'] as List? ?? const []))
        ?SuggestionReason.fromJson(reason),
    ],
  );

  final Person person;
  final Friendship friendship;
  final Presence? presence;
  final List<SuggestionReason> reasons;

  Suggestion asking() => Suggestion(
    person: person,
    friendship: Friendship.pendingOut,
    presence: presence,
    reasons: reasons,
  );
}

/// The part of Find players on screen, which decides what the gateway is asked to tell.
enum DiscoverView { board, mine, live, people }

/// Meeting people beyond one's friends on the phone: the looking-for-group board and one's own
/// posts, public share plays and parties (Live now), and discovery (the setting and people one
/// may know). The board and the public lists read themselves again when the gateway says they
/// changed, while they are on screen; answers to one's own "I'm in" and asks come live.
class Discover extends ChangeNotifier {
  Discover({
    required this.account,
    required this.socket,
    this.parties,
    this.sharePlays,
  }) {
    _events = socket.events.listen(_event);
  }

  final TogetherAccount account;
  final TogetherSocket socket;

  /// Told to read themselves again when a poster's yes invited this phone quietly.
  final Parties? parties;
  final SharePlays? sharePlays;
  late final StreamSubscription<TogetherEvent> _events;

  // The board

  LfgFilter filter = const LfgFilter();
  List<LfgPost> board = const [];
  bool boardMore = false;
  bool boardLoaded = false;
  List<LfgGame> boardGames = const [];
  int _boardGeneration = 0;
  bool _older = false;

  // Mine

  List<LfgPost> mine = const [];

  /// Posts the reader said "I'm in" to.
  List<LfgPost> asked = const [];
  bool mineLoaded = false;

  // Live now

  List<PublicShare> liveShares = const [];
  List<PublicParty> publicParties = const [];
  bool liveLoaded = false;

  // People

  DiscoverySettings? discovery;
  List<Suggestion> suggestions = const [];
  bool suggestionsLoaded = false;

  DiscoverView? showing;

  /// "I'm in"s waiting on the reader's open posts.
  int get waiting => mine
      .where((post) => post.status == LfgStatus.open)
      .fold(0, (sum, post) => sum + post.waiting);

  /// Puts [view] on screen (null: none), reads it and watches what it shows.
  void show(DiscoverView? view, {Object? by}) {
    showing = view;
    _shownBy = view == null ? null : by;
    _watch();
    final load = switch (view) {
      DiscoverView.board => loadBoard(),
      DiscoverView.mine => loadMine(),
      DiscoverView.live => loadLive(),
      DiscoverView.people => loadSuggestions(),
      null => null,
    };
    load?.catchError((_) {});
  }

  Object? _shownBy;

  /// The screen [by] is gone: nothing is on screen, unless another one showed something since.
  void hide(Object by) {
    if (identical(_shownBy, by)) show(null);
  }

  /// The reader's own games, the most recently played first, to post for.
  Future<List<GameRef>> myGames() async {
    final handle = account.user?.handle;
    if (handle == null) return const [];
    final json = await account.call(
      'GET',
      'users/${Uri.encodeComponent(handle)}/library',
    );
    return [
      for (final game in (json['games'] as List? ?? const []))
        GameRef.fromJson(game as Map<String, dynamic>),
    ];
  }

  void _watch() => socket.watchTopics(this, switch (showing) {
    DiscoverView.board => {filter.topic},
    DiscoverView.live => {'discover'},
    _ => const <String>{},
  });

  Future<void> loadBoard({LfgFilter? filter}) async {
    if (filter != null) {
      this.filter = filter;
      _watch();
    }
    final asked = this.filter;
    final mine = ++_boardGeneration;
    final json = await account.call('GET', asked.query());
    if (mine != _boardGeneration) return;
    board = _posts(json['posts']);
    boardMore = json['more'] == true;
    boardLoaded = true;
    notifyListeners();
  }

  Future<void> olderBoard() async {
    final last = board.lastOrNull;
    if (!boardMore || last == null || _older) return;
    _older = true;
    final mine = _boardGeneration;
    try {
      final json = await account.call('GET', filter.query(before: last.id));
      if (mine != _boardGeneration) return;
      final known = board.map((post) => post.id).toSet();
      board = [
        ...board,
        ..._posts(json['posts']).where((post) => !known.contains(post.id)),
      ];
      boardMore = json['more'] == true;
      notifyListeners();
    } finally {
      _older = false;
    }
  }

  Future<void> loadBoardGames() async {
    final json = await account.call('GET', 'lfg/games');
    boardGames = [
      for (final game in (json['games'] as List? ?? const []))
        LfgGame.fromJson(game as Map<String, dynamic>),
    ];
    notifyListeners();
  }

  Future<void> loadMine() async {
    final json = await account.call('GET', 'me/lfg');
    mine = _posts(json['posts']);
    asked = _posts(json['asked']);
    mineLoaded = true;
    notifyListeners();
  }

  /// Posts a new looking-for-group post; it is the reader's newest.
  Future<LfgPost> post(LfgDraft draft) async {
    final post = LfgPost.fromJson(
      await account.call('POST', 'lfg', draft.toJson(DateTime.now())),
    );
    mine = [post, ...mine.where((p) => p.id != post.id)];
    notifyListeners();
    return post;
  }

  /// "I'm in".
  Future<void> imIn(String postId) async {
    final post = LfgPost.fromJson(
      await account.call('POST', 'lfg/$postId/requests'),
    );
    _replace(post);
    if (!asked.any((p) => p.id == post.id)) asked = [post, ...asked];
    notifyListeners();
  }

  /// Takes an unanswered "I'm in" back.
  Future<void> takeBack(String postId) async {
    await account.call('DELETE', 'lfg/$postId/requests/me');
    _update(postId, (post) => post.copyWith(myRequest: () => null));
    asked = asked.where((post) => post.id != postId).toList();
    notifyListeners();
  }

  /// The poster lets someone in (an invite to their party or share play) or says no.
  Future<void> answer(
    String postId,
    String userId, {
    required bool accept,
  }) async {
    _replace(
      LfgPost.fromJson(
        await account.call(
          'POST',
          'lfg/$postId/requests/$userId/${accept ? 'accept' : 'decline'}',
        ),
      ),
    );
    notifyListeners();
  }

  /// The poster closes their post.
  Future<void> close(String postId) async {
    await account.call('DELETE', 'lfg/$postId');
    _update(postId, (post) => post.copyWith(status: LfgStatus.closed));
    board = board.where((post) => post.id != postId).toList();
    notifyListeners();
  }

  Future<void> loadLive() async {
    final [shares, parties] = await Future.wait([
      account.call('GET', 'share-plays/public?live=1'),
      account.call('GET', 'parties/public'),
    ]);
    liveShares = [
      for (final share in (shares['sharePlays'] as List? ?? const []))
        PublicShare.fromJson(share as Map<String, dynamic>),
    ];
    publicParties = [
      for (final party in (parties['parties'] as List? ?? const []))
        PublicParty.fromJson(party as Map<String, dynamic>),
    ];
    liveLoaded = true;
    notifyListeners();
  }

  /// Asks the leader of a public party to let the reader in.
  Future<void> askParty(String partyId) async {
    await account.call('POST', 'parties/$partyId/requests');
    _partyAsked(partyId, true);
  }

  Future<void> cancelPartyAsk(String partyId) async {
    await account.call('DELETE', 'parties/$partyId/requests/me');
    _partyAsked(partyId, false);
  }

  /// Asks the host of a public share play to let the reader watch.
  Future<void> askShare(String sharePlayId) async {
    await account.call('POST', 'share-plays/$sharePlayId/requests');
    _shareAsked(sharePlayId, true);
  }

  void _partyAsked(String partyId, bool requested) {
    publicParties = [
      for (final party in publicParties)
        party.id == partyId ? party.asked(requested) : party,
    ];
    notifyListeners();
  }

  void _shareAsked(String sharePlayId, bool requested) {
    liveShares = [
      for (final share in liveShares)
        share.id == sharePlayId ? share.asked(requested) : share,
    ];
    notifyListeners();
  }

  Future<void> loadDiscovery() async {
    discovery = DiscoverySettings.fromJson(
      await account.call('GET', 'me/discovery'),
    );
    notifyListeners();
  }

  /// On, off, or null to follow whether the library is public.
  Future<void> setDiscoverable(bool? on) async {
    discovery = DiscoverySettings.fromJson(
      await account.call('PATCH', 'me/discovery', {'discoverable': on}),
    );
    notifyListeners();
  }

  Future<void> setLanguages(List<String> languages) async {
    discovery = DiscoverySettings.fromJson(
      await account.call('PATCH', 'me/discovery', {'languages': languages}),
    );
    notifyListeners();
  }

  Future<void> loadSuggestions() async {
    final json = await account.call('GET', 'discover/suggestions');
    suggestions = [
      for (final suggestion in (json['suggestions'] as List? ?? const []))
        Suggestion.fromJson(suggestion as Map<String, dynamic>),
    ];
    suggestionsLoaded = true;
    notifyListeners();
  }

  /// A friend request went to this suggestion.
  void requested(String userId) {
    suggestions = [
      for (final suggestion in suggestions)
        suggestion.person.id == userId ? suggestion.asking() : suggestion,
    ];
    notifyListeners();
  }

  /// Signed out: nothing kept.
  void clear() {
    filter = const LfgFilter();
    board = const [];
    boardMore = false;
    boardLoaded = false;
    boardGames = const [];
    _boardGeneration++;
    mine = const [];
    asked = const [];
    mineLoaded = false;
    liveShares = const [];
    publicParties = const [];
    liveLoaded = false;
    discovery = null;
    suggestions = const [];
    suggestionsLoaded = false;
    notifyListeners();
  }

  /// A post as it is now, wherever it shows.
  void _replace(LfgPost post) {
    LfgPost pick(LfgPost known) => known.id == post.id ? post : known;
    board = board.map(pick).toList();
    mine = mine.map(pick).toList();
    asked = asked.map(pick).toList();
  }

  void _update(String postId, LfgPost Function(LfgPost post) change) {
    LfgPost pick(LfgPost known) => known.id == postId ? change(known) : known;
    board = board.map(pick).toList();
    mine = mine.map(pick).toList();
    asked = asked.map(pick).toList();
  }

  bool _reading = false;
  bool _again = false;

  /// Reads what is on screen again; a change while it reads reads once more after.
  Future<void> _reload() async {
    if (_reading) {
      _again = true;
      return;
    }
    _reading = true;
    try {
      do {
        _again = false;
        await switch (showing) {
          DiscoverView.board => loadBoard(),
          DiscoverView.live => loadLive(),
          DiscoverView.mine => loadMine(),
          DiscoverView.people => loadSuggestions(),
          null => Future<void>.value(),
        };
      } while (_again);
    } on Object {
      // The next change, or the reader, tries again.
    } finally {
      _reading = false;
    }
  }

  void _event(TogetherEvent event) {
    final data = event.json;
    switch (event.type) {
      case 'live.ready' when showing != null:
        _reload();
      case 'lfg.changed' when showing == DiscoverView.board:
        _reload();
      case 'discover.changed' when showing == DiscoverView.live:
        _reload();
      case 'lfg.request' || 'lfg.request_cancelled' when mineLoaded:
        loadMine().catchError((_) {});
      case 'lfg.answered':
        final postId = data['postId'];
        if (postId is! String) return;
        final status = _answerFrom(data['answer']);
        final invite = LfgInvite.fromJson(data['invite']);
        _update(
          postId,
          (post) =>
              post.copyWith(myRequest: () => LfgMyRequest(status, invite)),
        );
        notifyListeners();
        // The invite came quietly: the party or share play is read to show it.
        if (status == LfgAnswer.accepted && invite != null) {
          (invite.share ? sharePlays?.refresh() : parties?.refresh())
              ?.catchError((_) {});
        }
      case 'party.request_answered':
        if (data['partyId'] case final String partyId) {
          _partyAsked(partyId, false);
        }
      case 'share_play.request_answered':
        if (data['sharePlayId'] case final String sharePlayId) {
          _shareAsked(sharePlayId, false);
        }
    }
  }

  static List<LfgPost> _posts(Object? list) => [
    for (final post in (list as List? ?? const []))
      LfgPost.fromJson(post as Map<String, dynamic>),
  ];

  @override
  void dispose() {
    socket.watchTopics(this, const {});
    _events.cancel();
    super.dispose();
  }
}
