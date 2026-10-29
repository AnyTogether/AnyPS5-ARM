import 'dart:async';
import 'dart:io';

import 'package:anyps5_remote/l10n.dart';

/// Every test reads the texts from the source tree's assets/l10n, as the app does from its
/// assets.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  L10n.loadFolder(Directory('assets/l10n'));
  await testMain();
}
