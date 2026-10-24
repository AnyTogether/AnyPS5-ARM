import 'dart:convert';

/// A message on the launcher's control channel: one JSON object per WebSocket text frame.
sealed class Message {
  const Message();

  String toJson();

  static Message? fromJson(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return switch (json['type']) {
        'hello' => Hello(
          deviceID: json['deviceID'] as String,
          deviceName: json['deviceName'] as String,
          key: json['key'] as String?,
        ),
        'pairing' => Pairing(json['code'] as String),
        'welcome' => Welcome(
          session: BigInt.parse(json['session'] as String),
          udpPort: json['udpPort'] as int,
          macName: json['macName'] as String,
          key: json['key'] as String,
        ),
        'rejected' => Rejected(json['reason'] as String),
        'latency' => Latency((json['milliseconds'] as num).toDouble()),
        'library' => Library(
          games: [
            for (final game in json['games'] as List)
              RemoteGame.fromJson(game as Map<String, dynamic>),
          ],
          selected: json['selected'] as String?,
          running: json['running'] as String?,
          language: json['language'] as String,
        ),
        'look' => LookUpdate(
          deep: json['deep'] as String,
          middle: json['middle'] as String,
          accent: json['accent'] as String,
        ),
        'trophy' => TrophyEarned(
          name: json['name'] as String,
          detail: json['detail'] as String? ?? '',
          grade: json['grade'] as String,
          icon: json['icon'] as String?,
        ),
        'streaming' => Streaming(json['state'] as String),
        'activity' => ActivityUpdate(
          json['activity'] == null
              ? null
              : Activity.fromJson(json['activity'] as Map<String, dynamic>),
        ),
        'art' => Art(
          id: json['id'] as String,
          icon: json['icon'] as String?,
          background: json['background'] as String?,
        ),
        'togetherHandoff' => TogetherHandoff(
          id: json['id'] as String,
          deviceName: json['deviceName'] as String,
        ),
        'togetherHandoffAnswer' => TogetherHandoffAnswer(
          id: json['id'] as String,
          approved: json['approved'] as bool,
        ),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

class Hello extends Message {
  const Hello({
    required this.deviceID,
    required this.deviceName,
    required this.key,
  });

  final String deviceID;
  final String deviceName;
  final String? key;

  @override
  String toJson() => jsonEncode({
    'type': 'hello',
    'protocol': 1,
    'deviceID': deviceID,
    'deviceName': deviceName,
    'key': key,
  });
}

class Pairing extends Message {
  const Pairing(this.code);

  final String code;

  @override
  String toJson() => jsonEncode({'type': 'pairing', 'code': code});
}

class Welcome extends Message {
  const Welcome({
    required this.session,
    required this.udpPort,
    required this.macName,
    required this.key,
  });

  final BigInt session;
  final int udpPort;
  final String macName;
  final String key;

  @override
  String toJson() => jsonEncode({
    'type': 'welcome',
    'session': session.toString(),
    'udpPort': udpPort,
    'macName': macName,
    'key': key,
  });
}

class Rejected extends Message {
  const Rejected(this.reason);

  final String reason;

  @override
  String toJson() => jsonEncode({'type': 'rejected', 'reason': reason});
}

class Latency extends Message {
  const Latency(this.milliseconds);

  final double milliseconds;

  @override
  String toJson() =>
      jsonEncode({'type': 'latency', 'milliseconds': milliseconds});
}

enum GameState {
  installed,
  update,
  locked,
  installing,
  starting,
  running,
  unavailable,
}

/// A game as the launcher lists it; [art] changes whenever its pictures do.
class RemoteGame {
  const RemoteGame({
    required this.id,
    required this.name,
    required this.state,
    required this.trophies,
    required this.art,
    this.layout,
  });

  factory RemoteGame.fromJson(Map<String, dynamic> json) => RemoteGame(
    id: json['id'] as String,
    name: json['name'] as String,
    state: GameState.values.firstWhere(
      (state) => state.name == json['state'],
      orElse: () => GameState.unavailable,
    ),
    trophies: json['trophies'] as String?,
    art: json['art'] as String,
    layout: json['layout'] as String?,
  );

  final String id;
  final String name;
  final GameState state;
  final String? trophies;
  final String art;

  /// The pad layout saved on the Mac for this game, as LayoutTweaks JSON.
  final String? layout;
}

/// The launcher's games, the one selected, the one playing and its language.
class Library extends Message {
  const Library({
    required this.games,
    required this.selected,
    required this.running,
    required this.language,
  });

  final List<RemoteGame> games;
  final String? selected;
  final String? running;
  final String language;

  @override
  String toJson() => jsonEncode({
    'type': 'library',
    'games': [
      for (final game in games)
        {
          'id': game.id,
          'name': game.name,
          'state': game.state.name,
          'trophies': game.trophies,
          'art': game.art,
          'layout': game.layout,
        },
    ],
    'selected': selected,
    'running': running,
    'language': language,
  });
}

/// A game's icon and background, base64 JPEG.
class Art extends Message {
  const Art({required this.id, required this.icon, required this.background});

  final String id;
  final String? icon;
  final String? background;

  @override
  String toJson() => jsonEncode({
    'type': 'art',
    'id': id,
    'icon': icon,
    'background': background,
  });
}

class WantArt extends Message {
  const WantArt(this.id);

  final String id;

  @override
  String toJson() => jsonEncode({'type': 'wantArt', 'id': id});
}

/// A move on the launcher's screen: left, right, up, down, select, back or options.
class Command extends Message {
  const Command(this.name);

  final String name;

  @override
  String toJson() => jsonEncode({'type': 'command', 'name': name});
}

class SelectGame extends Message {
  const SelectGame(this.id);

  final String id;

  @override
  String toJson() => jsonEncode({'type': 'select', 'id': id});
}

/// What Play does for the game on the Mac.
class Launch extends Message {
  const Launch(this.id);

  final String id;

  @override
  String toJson() => jsonEncode({'type': 'launch', 'id': id});
}

class CloseGame extends Message {
  const CloseGame();

  @override
  String toJson() => jsonEncode({'type': 'close'});
}

/// The PS button: the launcher comes in front of the game.
/// Remote Play: the game's picture and sound at about this size, or no more.
class StreamRequest extends Message {
  const StreamRequest({required this.on, this.width = 0, this.height = 0});

  final bool on;
  final int width;
  final int height;

  @override
  String toJson() => jsonEncode({
    'type': 'stream',
    'on': on,
    'width': width,
    'height': height,
  });
}

/// Part of the picture was lost: the decoder waits for a key frame.
class KeyFrame extends Message {
  const KeyFrame();

  @override
  String toJson() => jsonEncode({'type': 'keyFrame'});
}

/// How Remote Play is going: on, off, noPermission or noGame.
class Streaming extends Message {
  const Streaming(this.state);

  final String state;

  @override
  String toJson() => jsonEncode({'type': 'streaming', 'state': state});
}

class Home extends Message {
  const Home();

  @override
  String toJson() => jsonEncode({'type': 'home'});
}

/// The pad layout for a game, for the Mac to keep with the game's settings; null is the default.
class SaveLayout extends Message {
  const SaveLayout(this.id, this.layout);

  final String id;
  final String? layout;

  @override
  String toJson() =>
      jsonEncode({'type': 'saveLayout', 'id': id, 'layout': layout});
}

/// A trophy just earned in the game playing.
/// The launcher's theme for the phone to wear, as #RRGGBB.
class LookUpdate extends Message {
  const LookUpdate({
    required this.deep,
    required this.middle,
    required this.accent,
  });

  final String deep;
  final String middle;
  final String accent;

  @override
  String toJson() => jsonEncode({
    'type': 'look',
    'deep': deep,
    'middle': middle,
    'accent': accent,
  });
}

class TrophyEarned extends Message {
  const TrophyEarned({
    required this.name,
    required this.detail,
    required this.grade,
    required this.icon,
  });

  final String name;
  final String detail;

  /// platinum, gold, silver or bronze.
  final String grade;

  /// Base64 JPEG.
  final String? icon;

  @override
  String toJson() => jsonEncode({
    'type': 'trophy',
    'name': name,
    'detail': detail,
    'grade': grade,
    'icon': icon,
  });
}

/// The launcher's steps with a game: waiting for its turn, the installer's five, and starting it.
enum ActivityPhase { queued, unwrap, relink, copy, bundle, finish, starting }

/// What the launcher is doing with a game.
class Activity {
  const Activity({
    required this.id,
    required this.phase,
    required this.updating,
    required this.fraction,
    required this.elapsed,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as String,
    phase: ActivityPhase.values.firstWhere(
      (phase) => phase.name == json['phase'],
      orElse: () => ActivityPhase.queued,
    ),
    updating: json['updating'] as bool? ?? false,
    fraction: (json['fraction'] as num?)?.toDouble(),
    elapsed: Duration(
      microseconds: (((json['elapsed'] as num?) ?? 0) * 1e6).round(),
    ),
  );

  final String id;
  final ActivityPhase phase;

  /// An installed game made again for a newer engine, not unlocked the first time.
  final bool updating;

  /// How much of the whole install is done, 0 to 1; null when not known.
  final double? fraction;

  /// How long the launcher has been at it when it said so.
  final Duration elapsed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'phase': phase.name,
    'updating': updating,
    'fraction': fraction,
    'elapsed': elapsed.inMicroseconds / 1e6,
  };
}

/// What the launcher is doing with a game now; null once it is done.
class ActivityUpdate extends Message {
  const ActivityUpdate(this.activity);

  final Activity? activity;

  @override
  String toJson() =>
      jsonEncode({'type': 'activity', 'activity': activity?.toJson()});
}

/// AnyTogether: either side asks the other, already signed in, to sign it in. The id is the
/// hand-off the asker started with the server; [deviceName] is shown before approving.
class TogetherHandoff extends Message {
  const TogetherHandoff({required this.id, required this.deviceName});

  final String id;
  final String deviceName;

  @override
  String toJson() => jsonEncode({
    'type': 'togetherHandoff',
    'id': id,
    'deviceName': deviceName,
  });
}

/// The answer: approved on the server, or turned down.
class TogetherHandoffAnswer extends Message {
  const TogetherHandoffAnswer({required this.id, required this.approved});

  final String id;
  final bool approved;

  @override
  String toJson() => jsonEncode({
    'type': 'togetherHandoffAnswer',
    'id': id,
    'approved': approved,
  });
}
