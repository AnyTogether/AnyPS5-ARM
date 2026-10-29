import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connection/cable.dart';
import 'connection/discovery.dart';
import 'connection/device_name.dart';
import 'feedback/haptics.dart';
import 'feedback/motion.dart';
import 'l10n.dart';
import 'layout/layout_tweaks.dart';
import 'connection/session.dart';
import 'protocol/messages.dart';
import 'strings.dart';
import 'together/together_hub.dart';
import 'stream/platform_player.dart';
import 'ui/activity_card.dart';
import 'ui/call_layer.dart';
import 'ui/home_screen.dart';
import 'ui/pad_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/handoff_card.dart';
import 'ui/update_required_card.dart';
import 'ui/trophy_card.dart';
import 'ui/typing_sheet.dart';
import 'ui/voice_pill.dart';
import 'ui/welcome_screen.dart';
import 'version.dart';

/// The control port the launcher listens on when it can; a typed address uses it.
const launcherPort = 47700;

/// A launcher to use instead of searching (host:port), given at build time for checks that must
/// not reach another launcher on the network.
const fixedLauncher = String.fromEnvironment('ANYPS5_LAUNCHER');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await L10n.load();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final preferences = await SharedPreferences.getInstance();
    final name = await deviceName(
      fallback: Platform.isIOS ? 'iPhone' : 'Android',
    );
    runApp(RemoteApp(preferences: preferences, deviceName: name));
  } catch (error) {
    // Anything that fails before the first frame is shown, never a black screen.
    runApp(StartupError(error: error));
  }
}

/// The reason the app could not start, readable on the phone.
class StartupError extends StatelessWidget {
  const StartupError({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            '${Strings.english.startFailed}\n\n$error',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ),
    ),
  );
}

class RemoteApp extends StatefulWidget {
  const RemoteApp({
    super.key,
    required this.preferences,
    required this.deviceName,
  });

  final SharedPreferences preferences;

  /// What the Mac calls this phone.
  final String deviceName;

  @override
  State<RemoteApp> createState() => _RemoteAppState();
}

class _RemoteAppState extends State<RemoteApp> {
  static const readyPause = Duration(milliseconds: 900);

  /// Remote Play's decoder and speaker; the stream is asked for only with [_remotePlay] on.
  final _player = PlatformStreamPlayer();
  late bool _remotePlay = widget.preferences.getBool('remotePlay') ?? false;

  late final Session _session =
      Session(preferences: widget.preferences, deviceName: widget.deviceName)
        ..player = _player
        ..haptics = (HapticsDriver(PlatformHaptics())
          ..enabled = widget.preferences.getBool('vibration') ?? true)
        ..motion = (MotionSource()
          ..enabled = widget.preferences.getBool('motion') ?? true);

  /// AnyTogether's live side: friends, messages, the party and its voice, on every screen.
  late final TogetherHub _together = TogetherHub(account: _session.together);
  StreamSubscription<(InternetAddress, int, String)>? _discovery;
  Timer? _manualTimer;
  Timer? _readyTimer;
  Timer? _layoutSave;
  bool _manual = false;
  bool _wasConnected = false;

  /// The Mac on a cable takes over from Wi-Fi; when it is unplugged the phone goes back to the
  /// launcher it last found or was given.
  late final CableLink _cableLink = CableLink(
    onPlugged: (port) {
      _plugged = true;
      _session.connect(InternetAddress.loopbackIPv4, port, cable: true);
    },
    onUnplugged: () {
      _plugged = false;
      final last = _lastLauncher;
      if (last != null) _session.connect(last.$1, last.$2);
    },
  );
  (InternetAddress, int)? _lastLauncher;
  bool _plugged = false;

  /// Past the "Ready" moment: the launcher or the pad shows.
  bool _ready = false;

  /// The pad shows while a game plays, unless PS took the phone to the launcher.
  bool _padShown = false;
  String? _running;
  String? _foundMac;
  late bool _welcomed = widget.preferences.getBool('welcomed') ?? false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    if (_welcomed) _search();
    // Without the cable port the phone still works over Wi-Fi.
    _cableLink.start().catchError((_) {});
  }

  /// Looks for the launcher; the address field shows if nothing turns up within a few seconds.
  void _search() {
    if (fixedLauncher.isNotEmpty) {
      final parts = fixedLauncher.split(':');
      _connect(InternetAddress(parts[0]), int.parse(parts[1]));
      return;
    }
    _discovery ??= discover().listen((found) {
      setState(() => _foundMac = found.$3);
      _connect(found.$1, found.$2);
    }, onError: (_) => setState(() => _manual = true));
    _manualTimer ??= Timer(
      const Duration(seconds: 6),
      () => setState(() => _manual = true),
    );
  }

  /// A launcher found or typed in becomes the target unless one is already connected, so a
  /// launcher that comes back on another port or address is followed.
  void _connect(InternetAddress address, int port) {
    _lastLauncher = (address, port);
    if (_session.status == ConnectionStatus.connected || _plugged) return;
    _manualTimer?.cancel();
    _session.connect(address, port);
  }

  void _changed() {
    final connected = _session.status == ConnectionStatus.connected;
    if (connected != _wasConnected) {
      _wasConnected = connected;
      WakelockPlus.toggle(enable: connected);
      _readyTimer?.cancel();
      if (connected) {
        // "Ready" shows for a moment, then the launcher or the game takes over.
        _readyTimer = Timer(readyPause, () => setState(() => _ready = true));
      } else {
        _ready = false;
      }
    }
    final library = _session.library;
    if (library != null) {
      if (library.language != widget.preferences.getString('language')) {
        widget.preferences.setString('language', library.language);
      }
      // A game that starts takes the pad; one that ends gives the phone back to the launcher.
      if (library.running != _running) {
        _running = library.running;
        _show(pad: _running != null);
      }
    }
    setState(() {});
  }

  void _show({required bool pad}) {
    _padShown = pad;
    pad ? _session.resumePad() : _session.pausePad();
    pad ? _session.motion?.start() : _session.motion?.stop();
    _stream();
  }

  /// The game's picture while the pad shows and Remote Play is on; the pad alone otherwise.
  void _stream() {
    if (_padShown && _remotePlay) {
      if (_session.streamWanted) return;
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final size = view.physicalSize;
      _session.startStream(size.longestSide.round(), size.shortestSide.round());
    } else {
      _session.stopStream();
    }
  }

  void _setRemotePlay(bool on) {
    widget.preferences.setBool('remotePlay', on);
    setState(() => _remotePlay = on);
    _stream();
  }

  void _home() {
    _session.send(const Home());
    setState(() => _show(pad: false));
  }

  void _resume() {
    final running = _session.library?.running;
    if (running == null) return;
    _session.send(Launch(running));
    setState(() => _show(pad: true));
  }

  void _start() {
    widget.preferences.setBool('welcomed', true);
    setState(() => _welcomed = true);
    _search();
  }

  @override
  void dispose() {
    _discovery?.cancel();
    _manualTimer?.cancel();
    _readyTimer?.cancel();
    _layoutSave?.cancel();
    _cableLink.stop();
    _together.dispose();
    _session.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (!_welcomed) {
      home = WelcomeScreen(onStart: _start);
    } else if (_ready && _session.status == ConnectionStatus.connected) {
      home = _padShown
          ? PadScreen(
              onState: _session.update,
              onHome: _home,
              onCapture: () => _session.send(const Command('capture')),
              status: _status(),
              glow: lightColor(_session.output),
              tweaks: _runningTweaks(),
              onTweaks: _saveTweaks,
              video: _remotePlay
                  ? StreamView(
                      player: _player,
                      notice: _session.streaming.value == 'noPermission'
                          ? Strings.of(
                              _session.library?.language ??
                                  widget.preferences.getString('language'),
                            ).remotePlayNoPermission
                          : null,
                    )
                  : null,
            )
          : HomeScreen(
              session: _session,
              onResume: _resume,
              status: _status(),
              remotePlay: _remotePlay,
              onRemotePlay: _setRemotePlay,
              together: _together,
            );
    } else {
      home = SetupScreen(
        session: _session,
        foundMac: _foundMac,
        showManual: _manual,
        onAddress: (address) => _connect(address, launcherPort),
        onRetry: _session.retry,
        together: _together,
      );
    }
    return Texts(
      strings: Strings.of(
        _session.library?.language ?? widget.preferences.getString('language'),
      ),
      child: MaterialApp(
        title: 'AnyPS5 Remote',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => Stack(
          children: [
            ?child,
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ActivityCard(
                      activity: _session.activity,
                      game: (id) {
                        final games = _session.library?.games ?? const [];
                        final matches = games.where((game) => game.id == id);
                        if (matches.isEmpty) return null;
                        return (
                          name: matches.first.name,
                          icon: _session.art[id]?.icon,
                        );
                      },
                    ),
                    TrophyCard(trophy: _session.trophy),
                    CallLayer(calls: _together.calls),
                    UpdateRequiredCard(tooOld: _session.together.tooOld),
                    HandoffCard(
                      asked: _session.handoffAsked,
                      handle: _session.together.user?.handle,
                      onAnswer: (ask, approve) => _session
                          .answerHandoff(ask, approve: approve)
                          .catchError((_) {}),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: TypingSheet(
                prompt: _session.textPrompt,
                look: _session.look,
                onAnswer: _session.type,
              ),
            ),
            const Positioned(
              right: 10,
              bottom: 6,
              child: IgnorePointer(
                child: Text(
                  'v$appVersion',
                  style: TextStyle(
                    color: Color(0x4DFFFFFF),
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: KeyedSubtree(key: ValueKey(home.runtimeType), child: home),
        ),
      ),
    );
  }

  /// The layout the Mac keeps for the game playing.
  LayoutTweaks _runningTweaks() {
    final library = _session.library;
    final game = library?.games
        .where((game) => game.id == library.running)
        .firstOrNull;
    return LayoutTweaks.fromJson(game?.layout);
  }

  /// Edits are sent once they settle, so a drag is one save.
  void _saveTweaks(LayoutTweaks tweaks) {
    final running = _session.library?.running;
    if (running == null) return;
    _layoutSave?.cancel();
    _layoutSave = Timer(
      const Duration(milliseconds: 400),
      () => _session.send(SaveLayout(running, tweaks.toJson())),
    );
  }

  Widget _status() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const StatusDot(color: Color(0xFF4CD964)),
      const SizedBox(width: 8),
      if (_session.cable) ...[
        const Icon(Icons.usb_rounded, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
      ],
      Text(
        [
          _session.macName ?? 'Mac',
          if (_session.latencyMs != null) '${_session.latencyMs!.round()} ms',
        ].join(' · '),
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      VoicePill(voice: _together.voice),
    ],
  );
}
