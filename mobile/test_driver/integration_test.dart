import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves every screenshot the flow test takes into ANYPS5_SHOTS (or build/shots).
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final folder = Directory(Platform.environment['ANYPS5_SHOTS'] ?? 'build/shots')..createSync(recursive: true);
        File('${folder.path}/$name.png').writeAsBytesSync(bytes);
        return true;
      },
    );
