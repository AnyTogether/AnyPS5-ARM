import 'package:flutter/services.dart';

/// Answered by MainActivity on Android and AppDelegate on iOS.
const deviceChannel = MethodChannel('org.anyps5.remote/device');

/// The name the phone gives itself (Settings → About phone), shown on the Mac as the phone that
/// connected; [fallback] when it gives none.
Future<String> deviceName({required String fallback}) async {
  try {
    final name = (await deviceChannel.invokeMethod<String>('name'))?.trim();
    return name == null || name.isEmpty ? fallback : name;
  } on Object {
    return fallback;
  }
}
