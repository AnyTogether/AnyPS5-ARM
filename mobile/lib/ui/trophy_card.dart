import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../protocol/messages.dart';
import '../strings.dart';

/// A trophy just earned, dropping in at the top of the screen for a few seconds, over whatever
/// the phone shows.
class TrophyCard extends StatefulWidget {
  const TrophyCard({super.key, required this.trophy});

  final ValueListenable<TrophyEarned?> trophy;

  static const shown = Duration(seconds: 4);

  @override
  State<TrophyCard> createState() => _TrophyCardState();
}

class _TrophyCardState extends State<TrophyCard> {
  TrophyEarned? _trophy;
  bool _visible = false;
  Timer? _hide;

  static const grades = {
    'platinum': Color(0xFFB9C8E2),
    'gold': Color(0xFFE8C15A),
    'silver': Color(0xFFCBD0D6),
    'bronze': Color(0xFFC88B57),
  };

  @override
  void initState() {
    super.initState();
    widget.trophy.addListener(_earned);
  }

  @override
  void dispose() {
    widget.trophy.removeListener(_earned);
    _hide?.cancel();
    super.dispose();
  }

  void _earned() {
    final trophy = widget.trophy.value;
    if (trophy == null) return;
    setState(() {
      _trophy = trophy;
      _visible = true;
    });
    _hide?.cancel();
    _hide = Timer(TrophyCard.shown, () => setState(() => _visible = false));
  }

  @override
  Widget build(BuildContext context) {
    final trophy = _trophy;
    if (trophy == null) return const SizedBox.shrink();
    final texts = Texts.of(context);
    final color = grades[trophy.grade] ?? Colors.white;
    final icon = trophy.icon == null ? null : base64Decode(trophy.icon!);
    return IgnorePointer(
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, -1.4),
        duration: const Duration(milliseconds: 380),
        curve: _visible ? Curves.easeOutBack : Curves.easeIn,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: const Color(0xF0101218),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.6)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: icon != null
                        ? Image.memory(icon, fit: BoxFit.cover)
                        : ColoredBox(
                            color: color.withValues(alpha: 0.2),
                            child: Icon(
                              Icons.emoji_events_rounded,
                              color: color,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 14,
                            color: color,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            texts.trophyEarned,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trophy.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (trophy.detail.isNotEmpty)
                        Text(
                          trophy.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
