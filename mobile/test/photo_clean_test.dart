// The image codec is pure Dart: slow in a debug test run on a busy machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:anyps5_remote/together/photo_clean.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

bool contains(List<int> haystack, String needle) {
  final bytes = ascii.encode(needle);
  outer:
  for (var i = 0; i + bytes.length <= haystack.length; i++) {
    for (var j = 0; j < bytes.length; j++) {
      if (haystack[i + j] != bytes[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// A JPEG the way a phone camera writes one: EXIF with the camera, the place and the rotation.
Uint8List cameraJpeg({int width = 40, int height = 20, int orientation = 1}) {
  final picture = img.Image(width: width, height: height);
  img.fill(picture, color: img.ColorRgb8(200, 30, 30));
  picture.exif.imageIfd['Make'] = img.IfdValueAscii('PhoneMaker');
  picture.exif.imageIfd['Model'] = img.IfdValueAscii('SecretCam 9');
  picture.exif.imageIfd.orientation = orientation;
  picture.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
  picture.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(41, 1);
  return img.encodeJpg(picture);
}

void main() {
  test('a camera photo goes without its EXIF, camera or place', () {
    final original = cameraJpeg();
    expect(contains(original, 'Exif'), isTrue);
    expect(contains(original, 'SecretCam'), isTrue);
    final clean = cleanPhotoNow(original)!;
    expect(contains(clean.bytes, 'Exif'), isFalse);
    expect(contains(clean.bytes, 'SecretCam'), isFalse);
    expect(contains(clean.bytes, 'PhoneMaker'), isFalse);
    final read = img.decodeJpg(clean.bytes)!;
    expect(read.exif.isEmpty, isTrue);
    expect((clean.width, clean.height), (40, 20));
    expect(clean.type, 'image/jpeg');
  });

  test('it is turned the way the camera was held', () {
    final clean = cleanPhotoNow(cameraJpeg(orientation: 6))!;
    expect((clean.width, clean.height), (20, 40));
  });

  test('a big one is made smaller, a PNG becomes a JPEG', () {
    final png = img.encodePng(img.Image(width: 300, height: 150));
    final clean = cleanPhotoNow(png, longest: 100)!;
    expect((clean.width, clean.height), (100, 50));
    expect(clean.bytes.sublist(0, 2), [0xFF, 0xD8]);
  });

  test('bytes that are no picture give nothing', () async {
    expect(await cleanPhoto(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
