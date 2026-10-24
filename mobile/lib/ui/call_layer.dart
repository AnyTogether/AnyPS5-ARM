import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/calls.dart';
import 'together_widgets.dart';

const _pick = Color(0xFF34C759);
const _hang = Color(0xFFFF453A);

/// Calls over whatever the phone shows, the pad included: a friend calling (accept, decline),
/// and the call itself as a small bar at the top with who, how long, mute and hang up. It sits
/// above the screens, so it draws no tooltips and needs no Navigator.
class CallLayer extends StatefulWidget {
  const CallLayer({super.key, required this.calls});

  final Calls calls;

  @override
  State<CallLayer> createState() => _CallLayerState();
}

class _CallLayerState extends State<CallLayer> {
  String? _rang;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListenableBuilder(
      listenable: widget.calls,
      builder: (context, _) {
        final calls = widget.calls;
        final ringing = calls.incoming.firstOrNull;
        if (ringing != null && ringing.callId != _rang) {
          _rang = ringing.callId;
          HapticFeedback.heavyImpact();
        }
        final active = calls.active;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Slide(
              child: ringing == null
                  ? const SizedBox.shrink()
                  : _Incoming(
                      key: ValueKey(ringing.callId),
                      call: ringing,
                      busy: calls.busy,
                      onAccept: () => calls.accept(ringing),
                      onDecline: () => calls.decline(ringing),
                    ),
            ),
            _Slide(
              child: active == null
                  ? const SizedBox.shrink()
                  : _CallBar(
                      key: ValueKey(active.id ?? active.peer.id),
                      calls: calls,
                      call: active,
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _Slide extends StatelessWidget {
  const _Slide({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 280),
    switchInCurve: Curves.easeOutBack,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => SlideTransition(
      position: Tween(
        begin: const Offset(0, -1.2),
        end: Offset.zero,
      ).animate(animation),
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: child,
  );
}

BoxDecoration _card(Color edge) => BoxDecoration(
  color: const Color(0xF2101218),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: edge),
  boxShadow: const [
    BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 8)),
  ],
);

class _Incoming extends StatelessWidget {
  const _Incoming({
    super.key,
    required this.call,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final IncomingCall call;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Semantics(
      liveRegion: true,
      label: texts.callingYou(call.from.displayName),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: _card(const Color(0x6634C759)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pulse(child: Avatar(person: call.from, size: 44)),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texts.callingYou(call.from.displayName),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    texts.voiceCall,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _Round(
              label: texts.declineCall,
              color: _hang,
              icon: Icons.call_end_rounded,
              onTap: busy ? null : onDecline,
            ),
            const SizedBox(width: 10),
            _Round(
              label: texts.acceptCall,
              color: _pick,
              icon: Icons.call_rounded,
              onTap: busy ? null : onAccept,
            ),
          ],
        ),
      ),
    );
  }
}

/// The call going on: the friend (a ring while they speak, a crossed microphone when they
/// muted themselves), calling, connecting, the time talked or why it ended; mute and hang up.
class _CallBar extends StatefulWidget {
  const _CallBar({super.key, required this.calls, required this.call});

  final Calls calls;
  final ActiveCall call;

  @override
  State<_CallBar> createState() => _CallBarState();
}

class _CallBarState extends State<_CallBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _clock();
  }

  @override
  void didUpdateWidget(_CallBar old) {
    super.didUpdateWidget(old);
    _clock();
  }

  /// Ticks once a second while the call is live, never otherwise.
  void _clock() {
    final live = widget.call.phase == CallPhase.live;
    if (live && _tick == null) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!live) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final call = widget.call;
    final calls = widget.calls;
    final over = call.phase == CallPhase.ended;
    final name = call.peer.displayName;
    final status = switch (call.phase) {
      CallPhase.ended => texts.callEnded(call.ended ?? CallEnd.ended, name),
      CallPhase.calling => texts.calling,
      CallPhase.connecting => texts.callConnecting,
      CallPhase.live => texts.clock(
        DateTime.now().difference(call.since ?? DateTime.now()),
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: _card(
        over
            ? const Color(0x33FFFFFF)
            : calls.peerSpeaking
            ? const Color(0x994CD964)
            : const Color(0x338AB4FF),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Avatar(
                person: call.peer,
                size: 34,
                ring: !over && calls.peerSpeaking ? togetherPlaying : null,
              ),
              if (call.peerMuted && !over)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Semantics(
                    label: texts.peerMuted(name),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: togetherPanel,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_off_rounded,
                        size: 13,
                        color: togetherError,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  call.peerMuted && !over && call.phase == CallPhase.live
                      ? '$status · ${texts.peerMuted(name)}'
                      : status,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: over ? Colors.white54 : Colors.white60,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (!over) ...[
            const SizedBox(width: 12),
            _Round(
              label: calls.muted ? texts.voiceUnmute : texts.voiceMute,
              color: calls.muted
                  ? togetherError
                  : calls.speaking
                  ? togetherPlaying
                  : const Color(0x33FFFFFF),
              icon: calls.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              size: 34,
              selected: calls.muted,
              onTap: call.id == null
                  ? null
                  : () => calls.setMuted(!calls.muted),
            ),
            const SizedBox(width: 8),
            _Round(
              label: texts.endCall,
              color: _hang,
              icon: Icons.call_end_rounded,
              size: 34,
              onTap: calls.hangUp,
            ),
          ],
        ],
      ),
    );
  }
}

/// A round button with an icon, labelled for screen readers.
class _Round extends StatelessWidget {
  const _Round({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.selected,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: onTap == null ? 0.45 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: size * 0.48),
        ),
      ),
    ),
  );
}

/// A soft ring breathing around the caller's picture while it rings.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Still when the phone asks for less motion.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final t = Curves.easeOut.transform(_controller.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _pick.withValues(alpha: 0.45 * (1 - t)),
              spreadRadius: 10 * t,
            ),
          ],
        ),
        child: child,
      );
    },
    child: widget.child,
  );
}
