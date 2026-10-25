import 'package:flutter/material.dart';

import '../strings.dart';

/// Go Live or End Broadcast for the game playing, as the Mac says it is: the launcher's
/// Broadcast to Twitch, YouTube or an RTMP server, set up in its settings.
class BroadcastButton extends StatelessWidget {
  const BroadcastButton({
    super.key,
    required this.broadcasting,
    required this.onPressed,
    this.font = const TextStyle(),
  });

  final ValueNotifier<bool> broadcasting;

  /// True to start, false to stop.
  final ValueChanged<bool> onPressed;
  final TextStyle font;

  static const live = Color(0xFFEB2933);

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: broadcasting,
      builder: (context, on, _) => OutlinedButton.icon(
        onPressed: () => onPressed(!on),
        icon: Icon(
          on ? Icons.stop_circle_outlined : Icons.sensors,
          size: 18,
          color: on ? Colors.white : live,
        ),
        label: Text(on ? texts.endBroadcast : texts.goLive),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: on ? live : null,
          side: BorderSide(color: on ? live : const Color(0x66FFFFFF)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: font.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
