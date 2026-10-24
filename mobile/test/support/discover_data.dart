import 'fake_server.dart';

/// A looking-for-group post as the API shows it (LfgView).
Map<String, dynamic> lfgPost(
  String id, {
  String author = 'ece',
  String purpose = 'online',
  int slots = 3,
  int filled = 0,
  String? startsAt,
  String? note,
  String status = 'open',
  bool mine = false,
  Map<String, dynamic>? myRequest,
  List<Map<String, dynamic>>? requests,
  List<String> languages = const ['en', 'tr'],
}) => {
  'id': id,
  'author': card(author, name: author == 'me' ? 'Utku' : null),
  'titleId': 'PPSA01234',
  'game': {
    'names': {'en': 'Astro Bot'},
    'iconUrl': null,
  },
  'purpose': purpose,
  'startsAt': startsAt,
  'languages': languages,
  'region': null,
  'slots': slots,
  'filled': filled,
  'note': note,
  'expiresAt': '2026-10-25T23:00:00Z',
  'status': status,
  'createdAt': '2026-10-25T17:00:00Z',
  'mine': mine,
  'myRequest': myRequest,
  'requests': ?requests,
};

/// A party in the public list (PublicPartyView).
Map<String, dynamic> publicParty(
  String id, {
  String join = 'open',
  int size = 2,
  bool requested = false,
  String host = 'ece',
}) => {
  'id': id,
  'host': card(host),
  'titleId': 'PPSA01234',
  'game': {
    'names': {'en': 'Astro Bot'},
    'iconUrl': null,
  },
  'language': 'tr',
  'join': join,
  'size': size,
  'max': 8,
  'requested': requested,
  'listedAt': '2026-10-25T17:00:00Z',
};

/// A share play in the public list (PublicShareView).
Map<String, dynamic> publicShare(
  String id, {
  String join = 'open',
  int viewers = 1,
  bool requested = false,
  String host = 'can',
}) => {
  'id': id,
  'host': card(host),
  'titleId': 'PPSA01234',
  'title': null,
  'game': {
    'names': {'en': 'Astro Bot'},
    'iconUrl': null,
  },
  'language': 'en',
  'join': join,
  'live': true,
  'viewers': viewers,
  'maxViewers': 4,
  'requested': requested,
  'startedAt': '2026-10-25T17:30:00Z',
};
