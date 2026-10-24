// The AnyTogether screens of the phone with demo people, as the README's pictures:
//
//     tool/screens/render.sh
//
// It runs this under flutter test (`flutter test tool/screens/render_test.dart`), which writes
// PNGs to build/screens, then makes the JPEGs in docs/screenshots. Nothing reaches a server.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:anyps5_remote/feedback/haptics.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/share_watch_screen.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo.dart';

const _size = Size(2400, 1648);
const _ratio = 3.0;
final _shot = GlobalKey();
final _images = <String, ui.Image>{};
late ui.Image _gameplay;

class _QuietHaptics implements HapticsOutput {
  @override
  void set(Rumble rumble) {}
}

String get _flutterRoot {
  final set = Platform.environment['FLUTTER_ROOT'];
  if (set != null && set.isNotEmpty) return set;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/bin/flutter').existsSync()) return dir.path;
    dir = dir.parent;
  }
  throw StateError('no Flutter SDK found');
}

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (any) await loader.load();
}

Future<String> _fonts() async {
  final material = '$_flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await _font('Apple Color Emoji', [
    '/System/Library/Fonts/Apple Color Emoji.ttc',
  ]);
  const sf = '/Library/Fonts/SF-Pro-Text';
  if (File('$sf-Regular.otf').existsSync()) {
    await _font('SF Pro Text', [
      for (final w in ['Regular', 'Medium', 'Semibold', 'Bold']) '$sf-$w.otf',
    ]);
    return 'SF Pro Text';
  }
  await _font('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
  ]);
  return 'Roboto';
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _crop(ui.Image source, Rect from, Size to) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    source,
    from,
    Offset.zero & to,
    Paint()..filterQuality = FilterQuality.high,
  );
  return recorder.endRecording().toImage(to.width.round(), to.height.round());
}

Future<ui.Image> _avatar(String seed) {
  final random = Random(seed.codeUnits.fold<int>(7, (a, c) => a * 31 + c));
  final hue = random.nextDouble() * 360;
  Color tone(double shift, double s, double l) =>
      HSLColor.fromAHSL(1, (hue + shift) % 360, s, l).toColor();
  const side = 256.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const square = Rect.fromLTWH(0, 0, side, side);
  canvas.drawRect(
    square,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(side, side), [
        tone(0, 0.55, 0.42),
        tone(40, 0.65, 0.22),
      ]),
  );
  for (var i = 0; i < 3; i++) {
    final center = Offset(
      random.nextDouble() * side,
      random.nextDouble() * side,
    );
    final radius = side * (0.35 + random.nextDouble() * 0.4);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          tone(-30 + 50.0 * i, 0.8, 0.62).withValues(alpha: 0.85),
          tone(-30 + 50.0 * i, 0.8, 0.62).withValues(alpha: 0),
        ]),
    );
  }
  canvas.drawCircle(
    const Offset(side / 2, side * 0.40),
    side * 0.17,
    Paint()..color = Colors.white.withValues(alpha: 0.92),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: const Offset(side / 2, side * 0.92),
      width: side * 0.62,
      height: side * 0.56,
    ),
    Paint()..color = Colors.white.withValues(alpha: 0.92),
  );
  return recorder.endRecording().toImage(side.toInt(), side.toInt());
}

Future<void> _art() async {
  final launcher = await _decode('../docs/screenshots/phone-launcher.jpg');
  const icon = Size(256, 256);
  _images['$iconBase/silksong.png'] = await _crop(
    launcher,
    const Rect.fromLTWH(494, 87, 150, 150),
    icon,
  );
  _images['$iconBase/stray.png'] = await _crop(
    launcher,
    const Rect.fromLTWH(1066, 96, 130, 130),
    icon,
  );
  _images['$iconBase/sarah.png'] = await _crop(
    launcher,
    const Rect.fromLTWH(316, 96, 130, 130),
    icon,
  );
  _images['$iconBase/doom.png'] = await _crop(
    launcher,
    const Rect.fromLTWH(128, 96, 130, 130),
    icon,
  );
  for (final person in pictured) {
    _images['$avatarBase/${person.id}.png'] = await _avatar(person.id);
  }
  final banner = await _decode(
    '../docs/screenshots/launcher-trophy-banner.jpg',
  );
  _gameplay = await _crop(
    banner,
    const Rect.fromLTWH(430, 110, 1170, 790),
    const Size(1170, 790),
  );
}

void _cacheArt() {
  final cache = PaintingBinding.instance.imageCache;
  for (final MapEntry(:key, :value) in _images.entries) {
    cache.putIfAbsent(
      NetworkImage(key),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: value.clone())),
      ),
    );
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screens/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late String family;

  setUpAll(() async {
    family = await _fonts();
    await _art();
  });

  Future<TogetherHub> hub(
    WidgetTester tester, {
    List<double> voice = const [],
    int unseen = 4,
  }) async {
    final preferences = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(signedIn());
      return SharedPreferences.getInstance();
    });
    final account = DemoAccount(preferences!);
    final hub = TogetherHub(
      account: account,
      socket: DemoSocket(account: account),
      voiceEngine: () => DemoVoice(voice),
      shareEngine: () => DemoShare(
        SizedBox.expand(
          child: RawImage(image: _gameplay, fit: BoxFit.cover),
        ),
      ),
      shareSound: QuietSound.new,
    );
    await hub.friends.refresh();
    await hub.messages.refresh();
    await hub.parties.refresh();
    await hub.notifications.refresh();
    hub.feed.unseen = unseen;
    return hub;
  }

  Widget app(String family, Widget home) => RepaintBoundary(
    key: _shot,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: family,
        fontFamilyFallback: const ['Apple Color Emoji'],
      ),
      home: home,
    ),
  );

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    TogetherHub hub,
    Widget home, {
    Future<void> Function()? then,
  }) async {
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = _ratio;
    debugDisableShadows = false;
    _cacheArt();
    await tester.pumpWidget(app(family, home));
    await settle(tester);
    if (then != null) {
      await then();
      await settle(tester);
    }
    await _save(tester, name);
    final problem = tester.takeException();
    if (problem != null) stdout.writeln('$name: $problem');
    await tester.pumpWidget(const SizedBox());
    hub.dispose();
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.reset();
    stdout.writeln('$name: ${(hub.account as DemoAccount).asked.toSet()}');
  }

  Widget together(TogetherHub hub, TogetherTab tab) =>
      TogetherScreen(hub: hub, tab: tab, gameName: gameName);

  testWidgets('friends', (tester) async {
    final h = await hub(tester);
    await shoot(tester, 'phone-friends', h, together(h, TogetherTab.friends));
  });

  testWidgets('messages', (tester) async {
    final h = await hub(tester);
    await shoot(
      tester,
      'phone-messages',
      h,
      together(h, TogetherTab.messages),
      then: () async {
        await h.messages.show('c-mira');
        (h.socket as DemoSocket).push('typing', {
          'conversationId': 'c-mira',
          'userId': 'mira',
        });
      },
    );
  });

  testWidgets('party', (tester) async {
    final h = await hub(tester, voice: [0.4, 0, 0]);
    await shoot(
      tester,
      'phone-party',
      h,
      together(h, TogetherTab.party),
      then: () => h.voice.join(),
    );
  });

  testWidgets('profile', (tester) async {
    final h = await hub(tester);
    await shoot(tester, 'phone-profile', h, together(h, TogetherTab.profile));
  });

  testWidgets('feed', (tester) async {
    final h = await hub(tester, unseen: 0);
    await shoot(tester, 'phone-feed', h, together(h, TogetherTab.feed));
  });

  testWidgets('notifications', (tester) async {
    final h = await hub(tester);
    await shoot(
      tester,
      'phone-notifications',
      h,
      together(h, TogetherTab.notifications),
    );
  });

  testWidgets('share play', (tester) async {
    final h = await hub(tester);
    await h.sharePlays.watch('sp-mira');
    (h.socket as DemoSocket).push('share_play.signal', {
      'sharePlayId': 'sp-mira',
      'from': 'mira',
      'device': 'mac-mira',
      'kind': 'offer',
      'data': {'type': 'offer', 'sdp': 'v=0'},
    });
    await shoot(
      tester,
      'phone-shareplay',
      h,
      ShareWatchScreen(plays: h.sharePlays, haptics: _QuietHaptics()),
    );
  });
}
