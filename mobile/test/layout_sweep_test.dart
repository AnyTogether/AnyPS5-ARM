// Every AnyTogether screen and the launcher home, in English and Turkish, on the smallest phones
// held sideways (iPhone SE: 568×320 and 667×375), a large one (932×430) and a tablet, with the
// text a size larger as well. A RenderFlex overflow or any other layout error fails the test.
// The demo people and data are the README pictures' (tool/screens/demo.dart).
import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/feedback/haptics.dart';
import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/about_sheet.dart';
import 'package:anyps5_remote/ui/home_screen.dart';
import 'package:anyps5_remote/ui/pad_screen.dart';
import 'package:anyps5_remote/ui/profile_edit.dart';
import 'package:anyps5_remote/ui/setup_screen.dart';
import 'package:anyps5_remote/ui/share_watch_screen.dart';
import 'package:anyps5_remote/ui/together_screen.dart';
import 'package:anyps5_remote/ui/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/screens/demo.dart';

const _sizes = {
  'SE 1st gen': Size(568, 320),
  'SE': Size(667, 375),
  'Pro Max': Size(932, 430),
  'iPad': Size(1180, 820),
};

class _QuietHaptics implements HapticsOutput {
  @override
  void set(Rumble rumble) {}
}

/// Opens [open] over an empty page once it is on screen, for the bottom sheets.
class _Opener extends StatefulWidget {
  const _Opener(this.open);

  final void Function(BuildContext context) open;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.open(context));
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

Session _session(TogetherHub hub, {bool connected = true}) {
  final session = Session(
    preferences: hub.account.preferences,
    deviceName: 'Pixel 8',
    together: hub.account,
  );
  if (connected) {
    session.status = ConnectionStatus.connected;
    session.macName = 'Robin’s MacBook Pro';
    session.latencyMs = 9;
    session.library = Library(
      games: [
        for (final (i, game) in games.indexed)
          RemoteGame(
            id: game.titleId,
            name: game.name,
            state: i == 1 ? GameState.locked : GameState.installed,
            trophies: i == 0 ? '8/34' : null,
            art: game.titleId,
          ),
      ],
      selected: silksong.titleId,
      running: null,
      language: 'en',
    );
  }
  return session;
}

/// The phone's other screens, each with the demo account signed in.
final Map<String, Future<Widget> Function(TogetherHub hub)> _screens = {
  'welcome': (_) async => WelcomeScreen(onStart: () {}),
  'setup': (hub) async => SetupScreen(
    session: _session(hub, connected: false),
    foundMac: null,
    showManual: true,
    onAddress: (_) {},
    onRetry: () {},
    together: hub,
  ),
  'launcher': (hub) async =>
      HomeScreen(session: _session(hub), onResume: () {}, together: hub),
  'pad': (_) async => PadScreen(onState: (_) {}),
  'conversation': (hub) async {
    await hub.messages.show('c-mira');
    return TogetherScreen(
      hub: hub,
      tab: TogetherTab.messages,
      gameName: gameName,
    );
  },
  'share play': (hub) async {
    await hub.sharePlays.watch('sp-mira');
    return ShareWatchScreen(plays: hub.sharePlays, haptics: _QuietHaptics());
  },
  'profile edit': (hub) async => ProfileEditScreen(
    profiles: Profiles(hub.account),
    pickPhoto: () async => null,
  ),
  'about': (hub) async => _Opener(
    (context) => showAbout(
      context,
      vibration: true,
      onVibration: (_) {},
      motion: true,
      onMotion: (_) {},
      remotePlay: false,
      onRemotePlay: (_) {},
      together: hub.account,
      macName: 'Robin’s MacBook Pro',
    ),
  ),
};

void main() {
  Future<TogetherHub> hub(WidgetTester tester) async {
    final preferences = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(signedIn());
      return SharedPreferences.getInstance();
    });
    final account = DemoAccount(preferences!);
    final hub = TogetherHub(
      account: account,
      socket: DemoSocket(account: account),
      voiceEngine: () => DemoVoice(const []),
      shareEngine: () => DemoShare(const SizedBox.expand()),
      shareSound: QuietSound.new,
    );
    await hub.friends.refresh();
    await hub.messages.refresh();
    await hub.parties.refresh();
    await hub.notifications.refresh();
    return hub;
  }

  for (final language in ['en', 'tr']) {
    for (final MapEntry(key: device, value: size) in _sizes.entries) {
      for (final scale in [1.0, 1.3]) {
        for (final MapEntry(key: name, value: screen) in _screens.entries) {
          testWidgets('$name fits on $device ($language, text ×$scale)', (
            tester,
          ) async {
            tester.view.physicalSize = size * 2;
            tester.view.devicePixelRatio = 2;
            addTearDown(tester.view.reset);
            final h = await hub(tester);
            final home = await screen(h);
            final layout = await _errors(tester, language, scale, home);
            expect(layout, isEmpty, reason: layout.join('\n\n'));
            if (name == 'about') expect(find.byType(BottomSheet), findsOne);
            await tester.pumpWidget(const SizedBox());
            h.dispose();
            await tester.pump(const Duration(seconds: 1));
          });
        }
        for (final tab in TogetherTab.values) {
          testWidgets('${tab.name} fits on $device ($language, text ×$scale)', (
            tester,
          ) async {
            tester.view.physicalSize = size * 2;
            tester.view.devicePixelRatio = 2;
            addTearDown(tester.view.reset);
            final h = await hub(tester);
            final layout = await _errors(
              tester,
              language,
              scale,
              TogetherScreen(hub: h, tab: tab, gameName: gameName),
            );
            expect(layout, isEmpty, reason: layout.join('\n\n'));
            await tester.pumpWidget(const SizedBox());
            h.dispose();
            await tester.pump(const Duration(seconds: 1));
          });
        }
      }
    }
  }
}

/// The layout errors [home] makes, in [language] with the text at [scale].
Future<List<String>> _errors(
  WidgetTester tester,
  String language,
  double scale,
  Widget home,
) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(
      Texts(
        strings: Strings.of(language),
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  } finally {
    FlutterError.onError = previous;
  }
  return errors
      .map((e) => e.toString())
      .where((e) => !e.contains('HTTP request failed'))
      .where((e) => !e.contains('NetworkImageLoadException'))
      .toList();
}
