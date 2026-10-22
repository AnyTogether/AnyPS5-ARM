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
        'art' => Art(
          id: json['id'] as String,
          icon: json['icon'] as String?,
          background: json['background'] as String?,
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
  );

  final String id;
  final String name;
  final GameState state;
  final String? trophies;
  final String art;
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
class Home extends Message {
  const Home();

  @override
  String toJson() => jsonEncode({'type': 'home'});
}
