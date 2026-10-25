// The AnyTogether screens of the phone with demo people, as the README's pictures:
//
//     tool/screens/render.sh
//
// It runs this under flutter test (`flutter test tool/screens/render_test.dart`), which writes
// PNGs to build/screens, then makes the JPEGs in docs/screenshots. Nothing reaches a server.
// With ANYPS5_SCREENS_GAMES=<games folder> it also draws the launcher on the phone, an update
// over it and the pad, with the games' own pictures from that folder.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/feedback/haptics.dart';
import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/ui/activity_card.dart';
import 'package:anyps5_remote/ui/home_screen.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:anyps5_remote/ui/setup_screen.dart' show StatusDot;
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
const _phone = Size(2340, 1080);
const _ratio = 3.0;
final _shot = GlobalKey();
final _images = <String, ui.Image>{};
late ui.Image _gameplay;
final _dumps =
    <({String id, String name, Uint8List icon, Uint8List? background})>[];

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
  await _font('Apple Symbols', ['/System/Library/Fonts/Apple Symbols.ttf']);
  await _font('Arial Unicode', [
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  ]);
  const sf = '/Library/Fonts/SF-Pro-Text';
  if (File('$sf-Regular.otf').existsSync()) {
    final faces = [
      for (final w in ['Regular', 'Medium', 'Semibold', 'Bold']) '$sf-$w.otf',
    ];
    await _font('SF Pro Text', faces);
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
  final library = await _decode('../docs/screenshots/launcher-library.jpg');
  const icon = Size(256, 256);
  for (final (name, column) in [
    ('silksong', 0),
    ('sarah', 1),
    ('doom', 2),
    ('catquest', 5),
  ]) {
    _images['$iconBase/$name.png'] = await _crop(
      library,
      Rect.fromLTWH(106 + 222.0 * column, 159, 172, 172),
      icon,
    );
  }
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

Future<Uint8List> _png(String path, int width) async {
  final codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
    targetWidth: width,
  );
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _games() async {
  final root = Platform.environment['ANYPS5_SCREENS_GAMES'];
  if (root == null || root.isEmpty) return;
  final folders = <Directory>[];
  void visit(Directory folder, int depth) {
    if (File('${folder.path}/sce_sys/param.json').existsSync()) {
      folders.add(folder);
      return;
    }
    if (depth == 2) return;
    for (final entry in folder.listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory && !name.startsWith('.')) visit(entry, depth + 1);
    }
  }

  visit(Directory(root), 0);
  for (final folder in folders) {
    final system = '${folder.path}/sce_sys';
    final param = jsonDecode(
      File('$system/param.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final localized =
        param['localizedParameters'] as Map<String, dynamic>? ?? {};
    final language = localized['defaultLanguage'] as String? ?? 'en-US';
    final names =
        (localized[language] ?? localized['en-US']) as Map<String, dynamic>? ??
        {};
    final id = param['titleId'] as String;
    if (!File('$system/icon0.png').existsSync()) continue;
    _dumps.add((
      id: id,
      name: names['titleName'] as String? ?? id,
      icon: await _png('$system/icon0.png', 256),
      background: File('$system/pic0.png').existsSync()
          ? await _png('$system/pic0.png', 1600)
          : null,
    ));
  }
  _dumps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    await _games();
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
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Apple Symbols',
          'Arial Unicode',
        ],
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
    Size size = _size,
  }) async {
    tester.view.physicalSize = size;
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

  Session launcher(TogetherHub hub, String selected) {
    final session = Session(
      preferences: hub.account.preferences,
      deviceName: 'Pixel 8',
      together: hub.account,
    );
    session.status = ConnectionStatus.connected;
    session.macName = 'Robin';
    session.latencyMs = 9;
    session.library = Library(
      games: [
        for (final game in _dumps)
          RemoteGame(
            id: game.id,
            name: game.name,
            state: game.id == 'PPSA99303'
                ? GameState.locked
                : GameState.installed,
            trophies: game.id == selected ? '8/34' : null,
            art: game.id,
          ),
      ],
      selected: selected,
      running: null,
      language: 'en',
    );
    for (final game in _dumps) {
      session.art[game.id] = GameArt(game.id)
        ..icon = game.icon
        ..background = game.background
        ..arrived = true;
    }
    return session;
  }

  Widget status(Session session) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const StatusDot(color: Color(0xFF4CD964)),
      const SizedBox(width: 8),
      Text(
        '${session.macName} · ${session.latencyMs!.round()} ms',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  const silksongId = 'PPSA12544';
  final drawGames = Platform.environment['ANYPS5_SCREENS_GAMES'] != null;

  Future<void> pictures(WidgetTester tester) =>
      tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));

  testWidgets('launcher', (tester) async {
    final h = await hub(tester);
    final session = launcher(h, silksongId);
    await shoot(
      tester,
      'phone-launcher',
      h,
      HomeScreen(
        session: session,
        onResume: () {},
        status: status(session),
        together: h,
      ),
      then: () => pictures(tester),
    );
  }, skip: !drawGames);

  testWidgets('update', (tester) async {
    final h = await hub(tester);
    final session = launcher(h, silksongId);
    session.activity.value = (
      activity: const Activity(
        id: silksongId,
        phase: ActivityPhase.relink,
        updating: true,
        fraction: 0.34,
        elapsed: Duration(seconds: 2),
      ),
      since: DateTime.now(),
    );
    await shoot(
      tester,
      'phone-activity',
      h,
      Stack(
        children: [
          HomeScreen(
            session: session,
            onResume: () {},
            status: status(session),
            together: h,
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  type: MaterialType.transparency,
                  child: ActivityCard(
                    activity: session.activity,
                    game: (id) {
                      final game = _dumps.where((g) => g.id == id).firstOrNull;
                      return game == null
                          ? null
                          : (name: game.name, icon: game.icon);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      then: () => pictures(tester),
    );
  }, skip: !drawGames);

  testWidgets('pad', (tester) async {
    final h = await hub(tester);
    final session = launcher(h, silksongId);
    await shoot(
      tester,
      'phone-pad',
      h,
      PadScreen(onState: (_) {}, status: status(session)),
    );
  }, skip: !drawGames);

  // The phone's own screen, as the corner of the README's photos of a game played with it.
  testWidgets('phone screen', (tester) async {
    for (final pad in [false, true]) {
      final h = await hub(tester);
      final session = launcher(h, silksongId);
      await shoot(
        tester,
        pad ? 'live/pad' : 'live/launcher',
        h,
        pad
            ? PadScreen(onState: (_) {}, status: status(session))
            : HomeScreen(
                session: session,
                onResume: () {},
                status: status(session),
                together: h,
              ),
        then: () => pictures(tester),
        size: _phone,
      );
    }
  }, skip: !drawGames);
}
