import 'activity.dart';
import 'people.dart';
import 'together_account.dart';

/// A join code: eight letters and digits a party's leader or a share play's host hands out (or
/// posts on Discord). Whoever holds it can ask to join; the leader or host still says yes.
class JoinCode {
  const JoinCode({
    required this.code,
    required this.url,
    required this.expiresAt,
  });

  static JoinCode? fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['code'] is! String) return null;
    return JoinCode(
      code: json['code'] as String,
      url: json['url'] as String? ?? '',
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  /// The letters a code is made of: no 0, O, 1 or I, so it reads aloud.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 8;

  final String code;

  /// The website's page for the code, with its "Ask to join" button.
  final String url;
  final DateTime expiresAt;

  /// "K7QM-3XPA".
  String get display => format(code);

  bool works([DateTime? now]) => expiresAt.isAfter(now ?? DateTime.now());

  /// A code in two halves of four, the way people read it; anything else as it is.
  static String format(String code) {
    final upper = code.toUpperCase();
    if (upper.length != length) return code;
    return '${upper.substring(0, 4)}-${upper.substring(4)}';
  }

  /// The code in what was typed or pasted: any case, with or without the dash or spaces, or the
  /// whole link; null when it cannot be one.
  static String? normalize(String text) {
    var rest = text.trim();
    final at = rest.toLowerCase().lastIndexOf('/join/');
    if (at >= 0) {
      rest = rest.substring(at + '/join/'.length);
      final end = rest.indexOf(RegExp(r'[?#/]'));
      if (end >= 0) rest = rest.substring(0, end);
    }
    final code = rest.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (code.length != length) return null;
    if (!code.split('').every(alphabet.contains)) return null;
    return code;
  }
}

enum JoinKind { party, sharePlay, gameSession }

/// Where the reader stands with what a code opens.
enum JoinState { none, member, requested, invited }

JoinState _state(Object? value) => switch (value) {
  'member' => JoinState.member,
  'requested' => JoinState.requested,
  'invited' => JoinState.invited,
  _ => JoinState.none,
};

JoinKind _kind(Object? value) => switch (value) {
  'share_play' => JoinKind.sharePlay,
  'game_session' => JoinKind.gameSession,
  _ => JoinKind.party,
};

/// What a code opens, as its holder sees it: whose party or share play, the game, how full.
class JoinInfo {
  const JoinInfo({
    required this.code,
    required this.kind,
    required this.id,
    required this.size,
    required this.max,
    required this.state,
    this.host,
    this.game,
  });

  factory JoinInfo.fromJson(Map<String, dynamic> json) {
    final host = json['host'];
    final game = json['game'];
    return JoinInfo(
      code: json['code'] as String? ?? '',
      kind: _kind(json['kind']),
      id: json['id'] as String? ?? '',
      host: host is Map<String, dynamic>
          ? Person(
              id: host['userId'] as String? ?? '',
              handle: host['handle'] as String? ?? '',
              displayName:
                  host['displayName'] as String? ??
                  host['handle'] as String? ??
                  '',
              avatar: host['avatar'] as String?,
            )
          : null,
      game: game is Map<String, dynamic> && game['titleId'] is String
          ? GameRef(
              titleId: game['titleId'] as String,
              names: {
                ...namesFrom(game['names']),
                if (game['title'] case final String title) 'default': title,
              },
              iconUrl: game['iconUrl'] as String?,
            )
          : null,
      size: (json['size'] as num?)?.toInt() ?? 0,
      max: (json['max'] as num?)?.toInt() ?? 0,
      state: _state(json['state']),
    );
  }

  final String code;
  final JoinKind kind;
  final String id;
  final Person? host;
  final GameRef? game;
  final int size;
  final int max;
  final JoinState state;

  bool get full => max > 0 && size >= max;

  JoinInfo withState(JoinState state) => JoinInfo(
    code: code,
    kind: kind,
    id: id,
    host: host,
    game: game,
    size: size,
    max: max,
    state: state,
  );
}

/// Looking a code up and asking to join with it.
class JoinCodes {
  JoinCodes(this.account);

  final TogetherAccount account;

  Future<JoinInfo> lookUp(String code) async =>
      JoinInfo.fromJson(await account.call('GET', 'join/$code'));

  /// Asks to join: a request the leader or host answers (or the invite waiting already).
  Future<JoinState> ask(String code) async =>
      _state((await account.call('POST', 'join/$code'))['state']);
}
