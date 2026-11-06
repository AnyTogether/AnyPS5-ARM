import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'e2ee.dart';
import 'storage.dart';
import 'together_account.dart';

/// Media for an end-to-end encrypted message: uploaded as ciphertext only, and downloaded and
/// opened on the phone, kept in memory (or a temporary file, for the video player) and nowhere
/// else.

/// Uploads a sealed file: POST /me/media/sealed?kind=, the ciphertext as the body; a clip's
/// [poster] (sealed as [FilePart.poster]) goes to PUT /me/media/:id/poster after it.
Future<Attachment> uploadSealedMedia(
  TogetherAccount account,
  MediaKind kind,
  Uint8List ciphertext, {
  Uint8List? poster,
}) async {
  final json = await account.upload(
    'me/media/sealed?kind=${kind.name}',
    ciphertext,
    'application/octet-stream',
    method: 'POST',
  );
  final view = json['media'] is Map<String, dynamic>
      ? json['media'] as Map<String, dynamic>
      : json;
  final media = Attachment.fromJson(view);
  if (media.id.isEmpty) {
    throw const TogetherProblem(502, 'internal', 'No media ID came back');
  }
  if (poster != null) {
    await account.upload(
      'me/media/${media.id}/poster',
      poster,
      'application/octet-stream',
    );
  }
  return media;
}

/// Downloads sealed media from its signed links (they need no token) and opens it with the keys
/// from its message; the last few are kept in memory.
class SealedMedia {
  SealedMedia({HttpClient? http, this.keep = 48 * 1024 * 1024})
    : _http =
          http ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  /// The app's one.
  static final shared = SealedMedia();

  /// The biggest download: a clip's limit and the tag.
  static const most = 25 * 1024 * 1024 + 16;

  final HttpClient _http;

  /// Bytes kept in memory at most.
  final int keep;
  final _kept = <String, Uint8List>{};
  final _loading = <String, Future<Uint8List>>{};
  int _keptBytes = 0;

  /// The file, or with [part] poster a clip's poster, opened. Throws [E2eeError] when it does
  /// not open, and anything the download throws.
  Future<Uint8List> open(Attachment media, {FilePart part = FilePart.file}) {
    final url = part == FilePart.file ? media.url : media.poster;
    final keys = part == FilePart.file ? media.file : media.posterFile;
    if (url == null || keys == null) {
      return Future.error(const E2eeError(E2eeErrorCode.noKey));
    }
    final id = '${media.id}|${part.name}|${keys.key}';
    final kept = _kept.remove(id);
    if (kept != null) {
      _kept[id] = kept;
      return Future.value(kept);
    }
    return _loading[id] ??= _fetch(url)
        .then(
          (ciphertext) =>
              openFile(ciphertext, part, key: keys.key, nonce: keys.nonce),
        )
        .then((plain) {
          _keepBytes(id, plain);
          return plain;
        })
        .whenComplete(() {
          _loading.remove(id);
        });
  }

  void _keepBytes(String id, Uint8List bytes) {
    if (bytes.length > keep) return;
    _kept[id] = bytes;
    _keptBytes += bytes.length;
    while (_keptBytes > keep && _kept.isNotEmpty) {
      final oldest = _kept.keys.first;
      _keptBytes -= _kept.remove(oldest)!.length;
    }
  }

  Future<Uint8List> _fetch(String url) async {
    final request = await _http.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('media answered ${response.statusCode}');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in response) {
      out.add(chunk);
      if (out.length > most) throw const HttpException('media too big');
    }
    return out.toBytes();
  }

  /// A clip or voice note opened into a temporary file for the player, which can only play
  /// files; the caller deletes it when done.
  Future<File> temporaryFile(Attachment media) async {
    final bytes = await open(media);
    final folder = await Directory.systemTemp.createTemp('anyps5-sealed-');
    final extension = switch (media.file?.type ?? media.contentType) {
      'video/mp4' => 'mp4',
      'audio/mp4' || 'audio/aac' || 'audio/x-m4a' => 'm4a',
      'audio/ogg' => 'ogg',
      'audio/webm' => 'webm',
      _ => 'bin',
    };
    final file = File('${folder.path}/media.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
