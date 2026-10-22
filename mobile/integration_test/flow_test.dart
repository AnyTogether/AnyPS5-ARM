// The whole first start on a device or simulator, against a running `anyps5-tool remote` on the
// same network: welcome, finding the Mac, pairing, the launcher, a game on the pad and PS back.
// Start the tool with --games so it has a library. Run with flutter drive.
import 'dart:io';

import 'package:anyps5_remote/main.dart' as app;
import 'package:anyps5_remote/ui/home_screen.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline))
      throw TestFailure('never showed: $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first start flows from welcome to a game and back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await waitFor(tester, find.text('Start'));
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('1-welcome');
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 400));
    await binding.takeScreenshot('2-searching');
    await waitFor(tester, find.textContaining('found'));
    // A launcher that allows every phone skips the pairing step.
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data?.contains('press Allow') == true ||
                widget.data == 'Opening the launcher…'),
      ),
    );
    if (find.textContaining('press Allow').evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('3-pairing');
    }
    await waitFor(tester, find.text('Ready'));
    await waitFor(tester, find.text('Opening the launcher…'));
    await binding.takeScreenshot('4-ready');
    await waitFor(tester, find.byType(HomeScreen));
    // The pictures arrive after the library.
    await waitFor(tester, find.byType(Image));
    // Picking a game here picks it on the Mac, and its background follows.
    await tester.tap(find.byType(Image).at(2));
    await waitFor(tester, find.textContaining('Silksong'));
    await waitFor(tester, find.byType(Image).at(6));
    await settle(tester);
    await binding.takeScreenshot('5-launcher');
    await tester.tap(find.text('Play'));
    await waitFor(tester, find.byType(PadScreen));
    await settle(tester);
    await binding.takeScreenshot('6-pad');
    final pad = tester.getRect(find.byType(PadScreen));
    await tester.tapAt(
      Offset(pad.left + pad.width * 0.50, pad.top + pad.height * 0.86),
    );
    await waitFor(tester, find.text('Back to Game'));
    await settle(tester);
    await binding.takeScreenshot('7-ps-home');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
