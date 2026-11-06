import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'e2ee.dart';

/// Where this phone keeps its end-to-end encryption keys: never in the app's preferences (where
/// the session is), never sent anywhere.
abstract class DeviceKeyStore {
  /// The keys kept under [slot], null when there are none (or they cannot be read).
  Future<DeviceSecrets?> read(String slot);

  Future<void> write(String slot, DeviceSecrets secrets);
}

/// The platform's keystore: the iOS Keychain, readable after the first unlock and only on this
/// device (not synced to iCloud, not in a backup restored elsewhere); on Android, data encrypted
/// with a key that never leaves the Android Keystore, and left out of backups
/// (res/xml/backup_rules.xml and data_extraction_rules.xml).
class SecureDeviceKeyStore implements DeviceKeyStore {
  SecureDeviceKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: android, iOptions: apple);

  static const android = AndroidOptions();
  static const apple = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<DeviceSecrets?> read(String slot) async =>
      decodeSecrets(await _storage.read(key: slot));

  @override
  Future<void> write(String slot, DeviceSecrets secrets) =>
      _storage.write(key: slot, value: encodeSecrets(secrets));
}

/// Keys kept in memory only, for tests and previews.
class MemoryDeviceKeyStore implements DeviceKeyStore {
  final kept = <String, String>{};

  @override
  Future<DeviceSecrets?> read(String slot) async => decodeSecrets(kept[slot]);

  @override
  Future<void> write(String slot, DeviceSecrets secrets) async =>
      kept[slot] = encodeSecrets(secrets);
}

/// The slot for one account on one server: signing in again as the same person uses the same
/// keys, another person on the same phone gets keys of their own.
String keySlot(Uri server, String userId) =>
    'anytogether.e2ee.v1.${server.host}${server.hasPort ? ':${server.port}' : ''}.$userId';

String encodeSecrets(DeviceSecrets secrets) => jsonEncode({
  'v': e2eeVersion,
  'signSeed': toBase64(secrets.signSeed),
  'boxSecret': toBase64(secrets.boxSecret),
});

Future<DeviceSecrets?> decodeSecrets(String? text) async {
  if (text == null) return null;
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['v'] != e2eeVersion) return null;
    return await DeviceSecrets.fromSeeds(
      fromBase64(json['signSeed'], 32),
      fromBase64(json['boxSecret'], 32),
    );
  } on Object {
    return null;
  }
}
