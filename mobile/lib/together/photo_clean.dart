import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A photo drawn again from its pixels alone: no EXIF, location, camera or other metadata goes
/// along (the picker keeps it), turned the way the camera held it, at most [clean]'s longest
/// side, as a JPEG. The server does this for plain uploads; a sealed one it cannot read, so the
/// phone does it before sealing.
class CleanPhoto {
  const CleanPhoto(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;

  String get type => 'image/jpeg';
}

/// Null when the bytes are not a picture this phone can read.
Future<CleanPhoto?> cleanPhoto(Uint8List bytes, {int longest = 2048}) =>
    Isolate.run(() => cleanPhotoNow(bytes, longest: longest));

CleanPhoto? cleanPhotoNow(Uint8List bytes, {int longest = 2048}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var upright = img.bakeOrientation(decoded);
  if (upright.width > longest || upright.height > longest) {
    upright = upright.width >= upright.height
        ? img.copyResize(upright, width: longest)
        : img.copyResize(upright, height: longest);
  }
  // Only the pixels: a new image with no EXIF, ICC profile or text chunks.
  final pixels = img.Image(
    width: upright.width,
    height: upright.height,
    numChannels: 3,
  );
  img.compositeImage(pixels, upright);
  final jpeg = img.encodeJpg(pixels, quality: 88);
  return CleanPhoto(jpeg, pixels.width, pixels.height);
}
