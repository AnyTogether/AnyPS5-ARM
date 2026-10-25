import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../connection/session.dart';
import '../protocol/messages.dart';
import '../strings.dart';
import '../together/together_hub.dart';
import 'about_sheet.dart';
import 'broadcast_button.dart';
import 'notifications_view.dart';
import 'together_screen.dart';
import 'together_sheet.dart';
import 'together_widgets.dart';

/// The launcher on the phone: the Mac's games over the selected one's background, the way the
/// launcher shows them. Picking a game picks it on the Mac too; the arrows, ✕, ○ and ≡ at the
/// bottom right move around the launcher's own screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onResume,
    this.status,
    this.remotePlay = false,
    this.onRemotePlay,
    this.together,
  });

  final Session session;

  /// AnyTogether's live side, behind the people button next to About.
  final TogetherHub? together;

  /// Back to the pad and the game playing.
  final VoidCallback onResume;

  /// Drawn at the top left: the connection dot and the Mac's name.
  final Widget? status;

  /// The game shown on the phone behind the pad, rather than the pad alone.
  final bool remotePlay;
  final ValueChanged<bool>? onRemotePlay;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const ink = Color(0xFF07080B);
  final _row = ScrollController();

  /// The game picked here before the launcher has answered with it.
  String? _picked;
  String? _shown;

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final library = widget.session.library;
    final games = library?.games ?? const <RemoteGame>[];
    if (library?.selected != null && library!.selected == _picked) {
      _picked = null;
    }
    final selectedID = _picked ?? library?.selected;
    final selected = games.where((game) => game.id == selectedID).firstOrNull;
    if (selected != null && selected.id != _shown) {
      _shown = selected.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(games, selected),
      );
    }
    final background = selected == null
        ? null
        : widget.session.art[selected.id]?.background;
    // The launcher's theme behind a game with no picture.
    final look = widget.session.look.value;
    final deep = look?.deep ?? ink;
    final glow = look == null
        ? const Color(0xFF1A1D27)
        : Color.lerp(look.deep, look.middle, 0.7)!;

    return Scaffold(
      backgroundColor: ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            // The pictures fill the screen while one fades into the next.
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: background == null
                ? DecoratedBox(
                    key: ValueKey('none ${glow.toARGB32()}'),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [glow, deep],
                        radius: 1.1,
                      ),
                    ),
                  )
                : Image.memory(
                    background,
                    key: ValueKey(selected!.id + selected.art),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x22000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.38, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.status != null) widget.status!,
                      const Spacer(),
                      if (widget.together case final hub?)
                        NotificationBell(
                          hub: hub,
                          onPressed: () =>
                              _openTogether(hub, TogetherTab.notifications),
                        ),
                      if (widget.together case final hub?)
                        ListenableBuilder(
                          listenable: hub,
                          builder: (context, _) => IconButton(
                            tooltip: texts.together,
                            onPressed: () => _openTogether(hub),
                            icon: CountBadge(
                              count: hub.badge,
                              child: const Icon(
                                Icons.people_alt_rounded,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: texts.about,
                        onPressed: () => showAbout(
                          context,
                          vibration: widget.session.haptics?.enabled ?? true,
                          onVibration: (value) {
                            widget.session.haptics
                              ?..enabled = value
                              ..stop();
                            widget.session.preferences.setBool(
                              'vibration',
                              value,
                            );
                          },
                          motion: widget.session.motion?.enabled ?? true,
                          onMotion: (value) {
                            widget.session.motion?.enabled = value;
                            widget.session.preferences.setBool('motion', value);
                          },
                          remotePlay: widget.remotePlay,
                          onRemotePlay: widget.onRemotePlay,
                          together: widget.session.together,
                          macName: widget.session.macName,
                          onUseMac: () => widget.session.signInWithMac(),
                          launcherServer: widget.session.launcherServer,
                          onOpenTogether: widget.together == null
                              ? null
                              : (tab) => _openTogether(widget.together!, tab),
                        ),
                        icon: const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 92,
                    child: games.isEmpty
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              texts.noGames,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 15,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: _row,
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            itemCount: games.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, index) => _Tile(
                              game: games[index],
                              icon: widget.session.art[games[index].id]?.icon,
                              selected: games[index].id == selectedID,
                              onTap: () => _pick(games[index], selectedID),
                            ),
                          ),
                  ),
                  const Spacer(),
                  if (selected != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _details(texts, selected, library!)),
                        const SizedBox(width: 16),
                        _Navigator(session: widget.session),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(Strings texts, RemoteGame game, Library library) {
    final playing = library.running == game.id;
    final otherPlaying = library.running != null && !playing;
    final ambient = Theme.of(context).textTheme.labelLarge;
    final font = TextStyle(
      fontFamily: ambient?.fontFamily,
      fontFamilyFallback: ambient?.fontFamilyFallback,
    );
    final (label, enabled) = switch (game.state) {
      GameState.running => (texts.resume, true),
      GameState.starting => (texts.starting, false),
      GameState.update => (texts.update, true),
      GameState.locked => (texts.unlock, true),
      GameState.installing => (texts.cancel, true),
      GameState.unavailable => (texts.unavailable, false),
      GameState.installed => (texts.play, true),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          game.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w300,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (playing)
              _Chip(text: texts.playing, color: const Color(0xFF4CD964)),
            if (game.trophies != null)
              _Chip(text: '🏆 ${game.trophies}', color: Colors.white70),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: enabled
                  ? () {
                      if (playing) {
                        widget.onResume();
                      } else {
                        widget.session.send(Launch(game.id));
                      }
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0x55FFFFFF),
                padding: const EdgeInsets.symmetric(
                  horizontal: 34,
                  vertical: 15,
                ),
                textStyle: font.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(label),
            ),
            if (playing || otherPlaying)
              OutlinedButton(
                onPressed: () => widget.session.send(const CloseGame()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 15,
                  ),
                  textStyle: font.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(texts.closeGame),
              ),
            if (playing)
              BroadcastButton(
                broadcasting: widget.session.broadcasting,
                font: font,
                onPressed: (start) => widget.session.send(
                  Command(start ? 'broadcastStart' : 'broadcastStop'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// AnyTogether's screen, or its sign-in first.
  void _openTogether(TogetherHub hub, [TogetherTab tab = TogetherTab.friends]) {
    if (hub.account.user == null) {
      showTogether(
        context,
        account: hub.account,
        macName: widget.session.macName,
        onUseMac: () => widget.session.signInWithMac(),
        onOpen: (tab) => _openTogether(hub, tab),
        launcherServer: widget.session.launcherServer,
      );
      return;
    }
    openTogether(context, hub: hub, tab: tab, gameName: _gameName);
  }

  /// A game's name from the Mac's library, for a friend playing it.
  String? _gameName(String titleId) => widget.session.library?.games
      .where((game) => game.id == titleId)
      .firstOrNull
      ?.name;

  void _pick(RemoteGame game, String? selectedID) {
    if (game.id == selectedID) return;
    setState(() => _picked = game.id);
    widget.session.send(SelectGame(game.id));
  }

  /// Keeps the selected tile in view when the Mac moves the selection.
  void _reveal(List<RemoteGame> games, RemoteGame selected) {
    if (!_row.hasClients) return;
    final index = games.indexOf(selected);
    const pitch = 92.0 + 14;
    final target = (index * pitch - _row.position.viewportDimension / 2 + pitch)
        .clamp(0.0, _row.position.maxScrollExtent);
    _row.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.game,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final RemoteGame game;
  final Uint8List? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final picture = icon;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.82,
        alignment: Alignment.center,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0x22FFFFFF),
            border: Border.all(
              color: selected ? Colors.white : const Color(0x22FFFFFF),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (picture != null)
                Image.memory(picture, fit: BoxFit.cover, gaplessPlayback: true)
              else
                const Icon(
                  Icons.sports_esports_rounded,
                  color: Colors.white38,
                  size: 34,
                ),
              if (game.state == GameState.locked ||
                  game.state == GameState.installing)
                const ColoredBox(
                  color: Color(0x88000000),
                  child: Icon(
                    Icons.lock_rounded,
                    color: Colors.white70,
                    size: 26,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x33000000),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Arrows, ✕, ○ and ≡ for the launcher's own screen on the Mac (menus, settings, panels).
class _Navigator extends StatelessWidget {
  const _Navigator({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    Widget key(String command, Widget label, {double size = 40}) => _Key(
      size: size,
      onTap: () => session.send(Command(command)),
      child: label,
    );
    const arrow = Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 124,
          height: 124,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: key(
                  'up',
                  const Icon(Icons.keyboard_arrow_up_rounded, color: arrow),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: key(
                  'down',
                  const Icon(Icons.keyboard_arrow_down_rounded, color: arrow),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: key(
                  'left',
                  const Icon(Icons.keyboard_arrow_left_rounded, color: arrow),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: key(
                  'right',
                  const Icon(Icons.keyboard_arrow_right_rounded, color: arrow),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            key(
              'options',
              const Text(
                '≡',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              size: 36,
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                key(
                  'back',
                  const Text(
                    '○',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  size: 50,
                ),
                const SizedBox(width: 10),
                key(
                  'select',
                  const Text(
                    '✕',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  size: 50,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.size, required this.onTap, required this.child});

  final double size;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) {
      setState(() => _down = true);
      widget.onTap();
    },
    onTapUp: (_) => setState(() => _down = false),
    onTapCancel: () => setState(() => _down = false),
    child: AnimatedScale(
      scale: _down ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _down ? const Color(0x55FFFFFF) : const Color(0x22FFFFFF),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: widget.child,
      ),
    ),
  );
}
