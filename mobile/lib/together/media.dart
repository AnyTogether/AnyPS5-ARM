import 'together_account.dart';

/// How a share play or a party call carries its media: peer to peer (the mesh, as always), or
/// through the server's media server (an SFU, LiveKit) once it outgrew the mesh. One that moved
/// to the media server stays there until it ends.
enum MediaRoute { mesh, sfu }

/// Missing (an older server) or anything unknown is the mesh.
MediaRoute mediaRouteFrom(Object? value) =>
    value == 'sfu' ? MediaRoute.sfu : MediaRoute.mesh;

/// The names the host's game picture and sound carry in the media server's room.
const sfuGameVideo = 'game';
const sfuGameAudio = 'game-audio';

/// What this phone joins a media server room with: LiveKit's URL and a token for one room
/// (`share-<id>` or `call-<id>`), as this person (their user ID). The token works for joining
/// for ten minutes; a phone already in the room keeps its place.
class SfuAccess {
  const SfuAccess({
    required this.url,
    required this.token,
    required this.room,
    required this.identity,
    this.expiresAt,
  });

  static SfuAccess? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    final token = json['token'];
    if (url is! String || token is! String) return null;
    return SfuAccess(
      url: url,
      token: token,
      room: json['room'] as String? ?? '',
      identity: json['identity'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }

  final String url;
  final String token;
  final String room;
  final String identity;
  final DateTime? expiresAt;

  /// Still good for joining, with a minute to spare; otherwise a fresh one is asked for.
  bool get usable =>
      expiresAt == null ||
      expiresAt!.isAfter(DateTime.now().add(const Duration(minutes: 1)));
}

/// What the server holds (GET /media-server): whether it has a media server, and the biggest
/// share play and party it takes. Without one, the mesh's: four viewers, eight in a party.
class MediaLimits {
  const MediaLimits({
    required this.sfu,
    required this.maxShareViewers,
    required this.maxPartySize,
  });

  factory MediaLimits.fromJson(Map<String, dynamic> json) => MediaLimits(
    sfu: json['sfu'] == true,
    maxShareViewers:
        (json['maxShareViewers'] as num?)?.toInt() ?? mesh.maxShareViewers,
    maxPartySize: (json['maxPartySize'] as num?)?.toInt() ?? mesh.maxPartySize,
  );

  static const mesh = MediaLimits(
    sfu: false,
    maxShareViewers: 4,
    maxPartySize: 8,
  );

  final bool sfu;
  final int maxShareViewers;
  final int maxPartySize;

  /// Asked from the server; the mesh's limits when it cannot say.
  static Future<MediaLimits> of(TogetherAccount account) async {
    try {
      return MediaLimits.fromJson(await account.call('GET', 'media-server'));
    } on Object {
      return mesh;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaLimits &&
      other.sfu == sfu &&
      other.maxShareViewers == maxShareViewers &&
      other.maxPartySize == maxPartySize;

  @override
  int get hashCode => Object.hash(sfu, maxShareViewers, maxPartySize);
}
