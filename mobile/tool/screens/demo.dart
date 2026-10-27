import 'dart:async';
import 'dart:convert';

import 'package:anyps5_remote/together/share_play.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/together/together_socket.dart';
import 'package:anyps5_remote/together/voice_mesh.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const avatarBase = 'https://demo.anytogether.invalid/avatars';
const iconBase = 'https://demo.anytogether.invalid/icons';

class DemoGame {
  const DemoGame(this.titleId, this.name, this.icon);

  final String titleId;
  final String name;
  final String? icon;

  String? get iconUrl => icon == null ? null : '$iconBase/$icon.png';

  Map<String, dynamic> get ref => {
    'titleId': titleId,
    'names': {'en': name},
    'iconUrl': iconUrl,
  };
}

const silksong = DemoGame('PPSA90001', 'Hollow Knight: Silksong', 'silksong');
const catQuest = DemoGame('PPSA90002', 'Cat Quest III', 'catquest');
const astroBot = DemoGame('PPSA90003', 'Astro Bot', null);
const sarah = DemoGame('PPSA90004', 'Dreaming Sarah', 'sarah');
const doom = DemoGame('PPSA90005', 'DOOM', 'doom');

const games = [silksong, catQuest, astroBot, sarah, doom];

String? gameName(String titleId) =>
    games.where((g) => g.titleId == titleId).firstOrNull?.name;

class DemoPerson {
  const DemoPerson(this.id, this.name, {this.picture});

  final String id;
  final String name;
  final bool? picture;

  String get handle => id;

  Map<String, dynamic> get card => {
    'userId': id,
    'handle': id,
    'displayName': name,
    'avatar': picture == true ? '$avatarBase/$id.png' : null,
  };
}

const ines = DemoPerson('ines', 'Ines Duarte', picture: true);
const mira = DemoPerson('mira', 'Mira Vance', picture: true);
const kenji = DemoPerson('kenji', 'Kenji Arata', picture: true);
const sol = DemoPerson('sol', 'Sol Okafor');
const theo = DemoPerson('theo', 'Theo Lund', picture: true);
const ada = DemoPerson('ada', 'Ada Brook');
const pablo = DemoPerson('pablo', 'Pablo Rios', picture: true);
const nora = DemoPerson('nora', 'Nora Kim');
const leo = DemoPerson('leo', 'Leo Marsh');

const pictured = [ines, mira, kenji, theo, pablo];

DateTime _ago(Duration d) => DateTime.now().subtract(d);
String _at(Duration d) => _ago(d).toUtc().toIso8601String();

String _id(int n) => '0190a000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

Map<String, dynamic> _friend(DemoPerson p, Map<String, dynamic> presence) => {
  ...p.card,
  'presence': presence,
};

Map<String, dynamic> get _friends => {
  'friends': [
    _friend(mira, {
      'state': 'in_game',
      'titleId': silksong.titleId,
      'since': _at(const Duration(minutes: 48)),
      'share': {
        'sharePlayId': 'sp-mira',
        'titleId': silksong.titleId,
        'title': silksong.name,
        'open': true,
        'viewers': 1,
        'maxViewers': 3,
      },
    }),
    _friend(kenji, {
      'state': 'in_game',
      'titleId': astroBot.titleId,
      'since': _at(const Duration(minutes: 20)),
      'party': {'id': 'p-kenji', 'size': 3, 'max': 8, 'open': true},
    }),
    _friend(theo, {
      'state': 'in_game',
      'titleId': catQuest.titleId,
      'since': _at(const Duration(hours: 1)),
    }),
    _friend(sol, {'state': 'online'}),
    _friend(ada, {'state': 'away'}),
    _friend(leo, {'state': 'offline'}),
  ],
};

Map<String, dynamic> _message(
  String conversation,
  int seq,
  String author,
  String text,
  Duration ago,
) => {
  'id': _id(seq + 100),
  'conversationId': conversation,
  'seq': seq,
  'authorId': author,
  'text': text,
  'replyTo': null,
  'editedAt': null,
  'deletedAt': null,
  'createdAt': _at(ago),
};

final _miraThread = [
  ('mira', 'ok the Silksong co-op thing actually works', 22),
  ('ines', 'wait, from your Mac?', 21),
  ('mira', 'yep. sharing it now, grab a pad', 20),
  ('ines', 'joining after this boss', 18),
  ('mira', 'Moss Mother took me 6 tries 😅', 9),
  ('ines', 'only 6? show-off', 8),
  ('mira', 'party at 9? Kenji and Sol are in', 3),
];

Map<String, dynamic> _conversation(
  String id,
  List<DemoPerson> members, {
  required int lastSeq,
  required int readSeq,
  required Map<String, dynamic> last,
  String? title,
}) => {
  'id': id,
  'kind': title == null ? 'direct' : 'group',
  'title': title,
  'createdBy': 'ines',
  'members': [ines.card, for (final m in members) m.card],
  'lastSeq': lastSeq,
  'readSeq': readSeq,
  'unread': lastSeq - readSeq,
  'lastMessage': last,
  'updatedAt': last['createdAt'],
};

Map<String, dynamic> get _conversations => {
  'conversations': [
    _conversation(
      'c-mira',
      [mira],
      lastSeq: 7,
      readSeq: 5,
      last: _message(
        'c-mira',
        7,
        'mira',
        _miraThread.last.$2,
        const Duration(minutes: 3),
      ),
    ),
    _conversation(
      'c-night',
      [kenji, sol, theo],
      title: 'Friday night co-op',
      lastSeq: 41,
      readSeq: 40,
      last: _message(
        'c-night',
        41,
        'kenji',
        'bringing snacks, someone bring a second pad',
        const Duration(minutes: 26),
      ),
    ),
    _conversation(
      'c-theo',
      [theo],
      lastSeq: 12,
      readSeq: 12,
      last: _message(
        'c-theo',
        12,
        'theo',
        'the pirate cat stole my loot AGAIN',
        const Duration(hours: 2),
      ),
    ),
    _conversation(
      'c-sol',
      [sol],
      lastSeq: 30,
      readSeq: 30,
      last: _message(
        'c-sol',
        30,
        'ines',
        'gg, rematch tomorrow',
        const Duration(hours: 20),
      ),
    ),
    _conversation(
      'c-ada',
      [ada],
      lastSeq: 4,
      readSeq: 4,
      last: _message(
        'c-ada',
        4,
        'ada',
        'thanks for the invite!',
        const Duration(days: 2),
      ),
    ),
  ],
};

Map<String, dynamic> get _thread => {
  'messages': [
    for (final (i, (author, text, minutes)) in _miraThread.indexed)
      _message('c-mira', i + 1, author, text, Duration(minutes: minutes)),
  ],
  'more': false,
};

Map<String, dynamic> _trophy(
  int id,
  String grade,
  String name, {
  String? detail,
  double? rarity,
  String? label,
}) => {
  'trophyId': id,
  'grade': grade,
  'hidden': false,
  'texts': {
    'en': {'name': name, 'detail': detail},
  },
  'rarity': rarity,
  'rarityLabel': label,
};

Map<String, dynamic> _activity(
  int n,
  String kind,
  DemoPerson actor,
  Duration ago, {
  DemoGame? game,
  String? highlight,
  List<Map<String, dynamic>> trophies = const [],
  int? trophyCount,
  int? seconds,
  DemoPerson? friend,
  Map<String, dynamic>? milestone,
  Map<String, int> counts = const {},
  String? mine,
}) => {
  'id': _id(n),
  'kind': kind,
  'createdAt': _at(ago),
  'actor': actor.card,
  'game': game?.ref,
  'highlight': highlight,
  'trophies': trophies,
  'trophyCount': trophyCount ?? trophies.length,
  'seconds': seconds,
  'friend': friend?.card,
  'milestone': milestone,
  'reactions': {'counts': counts, 'mine': mine},
};

Map<String, dynamic> get _feed => {
  'items': [
    _activity(
      1,
      'platinum',
      mira,
      const Duration(minutes: 12),
      game: silksong,
      highlight: 'platinum',
      trophies: [
        _trophy(1, 'platinum', 'Silksong', rarity: 0.021, label: 'ultra_rare'),
      ],
      counts: {'fire': 4, 'clap': 2, 'heart': 1},
      mine: 'fire',
    ),
    _activity(
      2,
      'trophy',
      kenji,
      const Duration(minutes: 40),
      game: catQuest,
      highlight: 'rare',
      trophies: [
        _trophy(14, 'gold', 'Full Sail', rarity: 0.064, label: 'very_rare'),
        _trophy(9, 'silver', 'Cannonball', rarity: 0.31, label: 'common'),
        _trophy(5, 'bronze', 'Treasure Hunter', rarity: 0.58, label: 'common'),
      ],
      trophyCount: 5,
      counts: {'wow': 2},
    ),
    _activity(
      3,
      'long_session',
      theo,
      const Duration(hours: 2),
      game: sarah,
      seconds: 3 * 3600 + 25 * 60,
      counts: {'clap': 1},
    ),
    _activity(
      4,
      'friendship',
      sol,
      const Duration(hours: 5),
      friend: ada,
      counts: {'heart': 3},
    ),
    _activity(
      5,
      'milestone',
      kenji,
      const Duration(hours: 9),
      milestone: {'kind': 'trophies', 'value': 500},
      counts: {'fire': 6},
    ),
    _activity(6, 'first_play', ines, const Duration(days: 1), game: doom),
  ],
  'next': null,
};

Map<String, dynamic> _notice(
  int n,
  String kind,
  DemoPerson? actor,
  Duration ago, {
  String? subject,
  Map<String, dynamic> data = const {},
  bool read = false,
}) => {
  'id': _id(n + 500),
  'kind': kind,
  'actor': actor?.card,
  'subjectId': subject,
  'data': data,
  'read': read,
  'createdAt': _at(ago),
  'updatedAt': _at(ago),
};

Map<String, dynamic> get _notifications => {
  'notifications': [
    _notice(
      1,
      'message',
      mira,
      const Duration(minutes: 3),
      subject: 'c-mira',
      data: {
        'conversationId': 'c-mira',
        'count': 2,
        'text': 'party at 9? Kenji and Sol are in',
      },
    ),
    _notice(
      2,
      'party_invite',
      kenji,
      const Duration(minutes: 18),
      subject: 'p-kenji',
      data: {'partyId': 'p-kenji', 'size': 3},
    ),
    _notice(3, 'friend_request', nora, const Duration(minutes: 55)),
    _notice(
      4,
      'game_invite',
      theo,
      const Duration(hours: 1),
      data: {'sessionId': 'g-1', 'titleId': catQuest.titleId},
      read: true,
    ),
    _notice(
      5,
      'missed_call',
      sol,
      const Duration(hours: 3),
      subject: 'call-9',
      read: true,
    ),
    _notice(6, 'friend_accepted', ada, const Duration(days: 1), read: true),
  ],
  'unread': 3,
  'more': false,
};

Map<String, dynamic> get partyJson => {
  'id': 'p-ines',
  'leaderId': 'ines',
  'privacy': 'friends',
  'members': [ines.card, mira.card, kenji.card, sol.card, theo.card],
  'invited': [ada.card],
  'call': {
    'id': 'call-party',
    'in': ['mira', 'kenji', 'theo'],
    'muted': ['theo', 'kenji'],
    'deafened': ['kenji'],
  },
  'joinCode': {
    'code': 'K7QM3XPA',
    'url': 'https://anytogether.net/join/K7QM3XPA',
    'expiresAt': _ago(const Duration(hours: -20)).toUtc().toIso8601String(),
  },
  'discord': 'https://discord.gg/anyps5',
};

Map<String, dynamic> _library(
  DemoGame g,
  int hours,
  int minutes,
  int earned,
  int total,
  int points,
  Duration last,
) => {
  ...g.ref,
  'firstPlayedAt': _at(const Duration(days: 60)),
  'lastPlayedAt': _at(last),
  'secondsPlayed': hours * 3600 + minutes * 60,
  'trophiesEarned': earned,
  'trophiesTotal': total,
  'progress': (earned * 100 / total).round(),
  'points': points,
};

Map<String, dynamic> _earned(
  DemoGame g,
  Map<String, dynamic> trophy,
  Duration ago,
) => {...g.ref, ...trophy, 'earnedAt': _at(ago)};

Map<String, dynamic> get shareView => {
  'id': 'sp-mira',
  'host': mira.card,
  'hostDevice': 'mac-mira',
  'titleId': silksong.titleId,
  'title': silksong.name,
  'open': true,
  'maxViewers': 3,
  'viewers': [
    {
      'user': ines.card,
      'device': 'phone-ines',
      'slot': null,
      'joinedAt': _at(const Duration(minutes: 4)),
    },
  ],
  'startedAt': _at(const Duration(minutes: 30)),
};

final _empty = <String, dynamic>{};

Map<String, dynamic> answer(
  String method,
  String path,
  Map<String, dynamic>? body,
) {
  final bare = path.split('?').first;
  return switch ((method, bare)) {
    ('GET', 'me/friends') => _friends,
    ('GET', 'me/friends/requests') => {
      'incoming': [nora.card, pablo.card],
      'outgoing': [],
    },
    ('GET', 'me/conversations') => _conversations,
    ('GET', 'me/conversations/unread') => {'conversations': 2, 'messages': 3},
    ('GET', 'conversations/c-mira/messages') => _thread,
    ('GET', 'me/feed') => _feed,
    ('GET', 'me/notifications') => _notifications,
    ('GET', 'me/notifications/unread') => {'unread': 3},
    ('GET', 'me/party') => {'party': partyJson, 'invites': []},
    ('GET', 'me/share-play') => {'invites': [], 'watching': null},
    ('POST', 'calls') => {
      'call': {
        'id': 'call-party',
        'in': [
          {'userId': 'mira', 'device': 'd-mira'},
          {'userId': 'kenji', 'device': 'd-kenji'},
          {'userId': 'theo', 'device': 'd-theo'},
        ],
      },
      'iceServers': [],
      'expiresAt': null,
    },
    ('POST', 'share-plays/sp-mira/join') => {
      'sharePlay': shareView,
      'iceServers': [],
      'expiresAt': null,
    },
    ('GET', 'users/ines') => {
      ...ines.card,
      'bio': 'Metroidvanias, cosy co-op and one more run. Usually on after 8.',
      'country': 'PT',
      'friendship': 'me',
      'visible': {
        'library': true,
        'trophies': true,
        'friends': true,
        'presence': true,
        'search': true,
      },
      'presence': {'state': 'online'},
    },
    ('GET', 'users/ines/library') => {
      'games': [
        _library(silksong, 41, 12, 38, 52, 2140, const Duration(hours: 3)),
        _library(catQuest, 14, 47, 25, 25, 1630, const Duration(days: 4)),
        _library(sarah, 6, 5, 9, 14, 380, const Duration(days: 9)),
        _library(doom, 2, 38, 4, 31, 120, const Duration(days: 1)),
      ],
    },
    ('GET', 'users/ines/trophies') => {
      'trophies': [
        _earned(
          catQuest,
          _trophy(
            1,
            'platinum',
            'Purrate King',
            rarity: 0.08,
            label: 'very_rare',
          ),
          const Duration(days: 4),
        ),
        _earned(
          silksong,
          _trophy(22, 'gold', 'Needle Sharp', rarity: 0.11, label: 'rare'),
          const Duration(hours: 3),
        ),
      ],
    },
    ('GET', 'users/ines/friends') => {
      'friends': [
        mira.card,
        kenji.card,
        sol.card,
        theo.card,
        ada.card,
        leo.card,
      ],
    },
    ('GET', 'users/ines/activity') => _feed,
    _ => _empty,
  };
}

class DemoSocket extends TogetherSocket {
  DemoSocket({required super.account});

  final _demoEvents = StreamController<TogetherEvent>.broadcast(sync: true);
  int _n = 0;

  @override
  Stream<TogetherEvent> get events => _demoEvents.stream;

  @override
  void start() {
    status = SocketStatus.ready;
    session = 'phone-ines';
    notifyListeners();
  }

  @override
  void stop() {}

  @override
  void wake() {}

  @override
  bool send(Map<String, dynamic> frame) => true;

  void push(String type, Map<String, dynamic> data) =>
      _demoEvents.add(TogetherEvent('demo-${++_n}', type, data));

  @override
  void dispose() {
    _demoEvents.close();
    super.dispose();
  }
}

class DemoAccount extends TogetherAccount {
  DemoAccount(SharedPreferences preferences)
    : super(
        preferences: preferences,
        base: Uri.parse('https://demo.anytogether.invalid'),
        clientName: 'remote-demo',
      );

  final asked = <String>[];

  @override
  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    asked.add('$method $path');
    return jsonDecode(jsonEncode(answer(method, path, body)))
        as Map<String, dynamic>;
  }
}

Map<String, Object> signedIn() => {
  'together.session': jsonEncode({
    'accessToken': 'demo',
    'accessExpiry': DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String(),
    'refreshToken': 'demo',
    'user': {'id': 'ines', 'handle': 'ines', 'displayName': 'Ines Duarte'},
  }),
};

class DemoVoiceLink implements VoiceLink {
  DemoVoiceLink(this.level);

  final double level;

  @override
  Future<Map<String, dynamic>> createOffer({bool restart = false}) async => {
    'type': 'offer',
    'sdp': 'v=0',
  };

  @override
  Future<Map<String, dynamic>> createAnswer() async => {
    'type': 'answer',
    'sdp': 'v=0',
  };

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {}

  @override
  Future<void> setRemote(Map<String, dynamic> description) async {}

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async {}

  @override
  String get signalingState => 'stable';

  @override
  String get connectionState => 'connected';

  @override
  bool get hasRemote => true;

  @override
  Future<({double incoming, double outgoing})> levels() async =>
      (incoming: level, outgoing: 0.0);

  @override
  set onCandidate(void Function(Map<String, dynamic> candidate) handler) {}

  @override
  set onState(void Function() handler) {}

  @override
  Future<void> setHearing(bool on) async {}

  @override
  Future<void> close() async {}
}

class DemoVoice implements VoiceEngine {
  DemoVoice(this.levels);

  final List<double> levels;
  int _links = 0;

  @override
  Future<void> start() async {}

  @override
  Future<VoiceLink> link(List<Map<String, dynamic>> iceServers) async =>
      DemoVoiceLink(_links < levels.length ? levels[_links++] : 0);

  @override
  void setTalking(bool on) {}

  @override
  Future<void> stop() async {}
}

class DemoShareLink implements ShareLink {
  DemoShareLink(this.picture);

  final Widget picture;
  void Function()? _state;

  @override
  String connectionState = 'new';

  @override
  String get signalingState => 'stable';

  @override
  bool hasRemote = false;

  @override
  Future<void> setRemote(Map<String, dynamic> description) async =>
      hasRemote = true;

  @override
  Future<Map<String, dynamic>> createAnswer() async => {
    'type': 'answer',
    'sdp': 'v=0',
  };

  @override
  Future<void> setLocal(Map<String, dynamic> description) async {
    connectionState = 'connected';
    scheduleMicrotask(() => _state?.call());
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) async {}

  @override
  set onCandidate(void Function(Map<String, dynamic> candidate) handler) {}

  @override
  set onState(void Function() handler) => _state = handler;

  @override
  set onChannel(void Function(ShareChannel channel) handler) {}

  @override
  Widget video() => picture;

  @override
  Future<ShareQuality> quality() async => const ShareQuality(
    roundTripMs: 23,
    framesPerSecond: 60,
    kilobitsPerSecond: 9200,
    lostPercent: 0,
    height: 1080,
  );

  @override
  Future<void> close() async {}
}

class DemoShare implements ShareEngine {
  DemoShare(this.picture);

  final Widget picture;

  @override
  Future<ShareLink> link(List<Map<String, dynamic>> iceServers) async =>
      DemoShareLink(picture);
}

class QuietSound implements ShareSound {
  @override
  void sound(dynamic packet) {}

  @override
  void stop() {}
}
