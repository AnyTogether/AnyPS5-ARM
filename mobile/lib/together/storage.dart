import 'dart:typed_data';

/// What a message holds: text, or one piece of media with an optional caption.
enum MediaKind {
  text,
  image,
  clip,
  voice;

  /// The kind the API names; anything this phone does not know stays [fallback].
  static MediaKind parse(Object? name, {MediaKind fallback = text}) =>
      values.where((kind) => kind.name == name).firstOrNull ?? fallback;
}

int? _int(Object? value) => value is num ? value.toInt() : null;

/// Whether the server keeps files (cloud saves and media) and its limits, from GET /storage.
/// Off, every storage feature is hidden.
class StorageInfo {
  const StorageInfo({
    required this.enabled,
    this.quota = 0,
    this.imageMax = 10 * 1024 * 1024,
  });

  static const off = StorageInfo(enabled: false);

  factory StorageInfo.fromJson(Map<String, dynamic> json) => StorageInfo(
    enabled: json['enabled'] == true,
    quota: _int(json['quota']) ?? 0,
    imageMax:
        _int((json['media'] as Map<String, dynamic>?)?['image']) ??
        10 * 1024 * 1024,
  );

  final bool enabled;

  /// Bytes each account may keep, saves and media together.
  final int quota;

  /// The biggest picture the server takes.
  final int imageMax;
}

/// How much of the account's quota is used, and by what (bytes).
class StorageUsage {
  const StorageUsage({
    required this.used,
    required this.limit,
    required this.saves,
    required this.media,
  });

  factory StorageUsage.fromJson(Map<String, dynamic> json) => StorageUsage(
    used: _int(json['used']) ?? 0,
    limit: _int(json['limit']) ?? 0,
    saves: _int(json['saves']) ?? 0,
    media: _int(json['media']) ?? 0,
  );

  final int used;
  final int limit;
  final int saves;
  final int media;

  /// 0-1 of the quota used.
  double get fraction => limit <= 0 ? 0 : (used / limit).clamp(0, 1);
}

/// A piece of media in a message as this member may see it: the media with signed links that
/// need no token, or [removed] (deleted or hidden) or [blocked] (one of you blocked the other).
class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    this.url,
    this.thumb,
    this.poster,
    this.width,
    this.height,
    this.durationMs,
    this.contentType,
    this.removed = false,
    this.blocked = false,
    this.local,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'] as String? ?? '',
    kind: MediaKind.parse(json['kind'], fallback: MediaKind.image),
    url: json['url'] as String?,
    thumb: json['thumb'] as String?,
    poster: json['poster'] as String?,
    width: _int(json['width']),
    height: _int(json['height']),
    durationMs: _int(json['durationMs']),
    contentType: json['contentType'] as String?,
    removed: json['removed'] == true,
    blocked: json['blocked'] == true,
  );

  final String id;
  final MediaKind kind;
  final String? url;
  final String? thumb;
  final String? poster;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? contentType;
  final bool removed;
  final bool blocked;

  /// The picture itself while it is still on its way from this phone.
  final Uint8List? local;

  /// There is something to show.
  bool get shown => !removed && !blocked && (url != null || local != null);

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// Width over height, when both are known.
  double? get aspect =>
      width != null && height != null && height! > 0 ? width! / height! : null;
}

/// A picture's content type from its first bytes: PNG, JPEG or WebP (the server decides anyway).
String imageContentType(List<int> bytes) {
  if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'image/png';
  }
  if (bytes.length > 11 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
