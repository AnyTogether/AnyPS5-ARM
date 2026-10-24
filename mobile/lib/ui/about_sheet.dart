import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../strings.dart';
import '../version.dart';

/// Who made the app and where its code is, over the screen it was opened from; with
/// [vibration], also the switch for the game's rumble on the phone.
Future<void> showAbout(
  BuildContext context, {
  bool? vibration,
  ValueChanged<bool>? onVibration,
  bool? motion,
  ValueChanged<bool>? onMotion,
  bool? remotePlay,
  ValueChanged<bool>? onRemotePlay,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(0xF2101218),
  isScrollControlled: true,
  // A phone on its side: the text and the switches side by side across its width.
  constraints: const BoxConstraints(maxWidth: 980),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => _About(
    vibration: vibration,
    onVibration: onVibration,
    motion: motion,
    onMotion: onMotion,
    remotePlay: remotePlay,
    onRemotePlay: onRemotePlay,
  ),
);

class _About extends StatefulWidget {
  const _About({
    this.vibration,
    this.onVibration,
    this.motion,
    this.onMotion,
    this.remotePlay,
    this.onRemotePlay,
  });

  final bool? vibration;
  final ValueChanged<bool>? onVibration;
  final bool? motion;
  final ValueChanged<bool>? onMotion;
  final bool? remotePlay;
  final ValueChanged<bool>? onRemotePlay;

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  late bool? _vibration = widget.vibration;
  late bool? _motion = widget.motion;
  late bool? _remotePlay = widget.remotePlay;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/icon.png', width: 84, height: 84),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AnyPS5 Remote  ·  v$appVersion',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    texts.aboutText,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  _Row(label: texts.madeBy, value: author),
                  _Row(
                    label: texts.sourceCode,
                    value: 'github.com/utkuhalis/AnyPS5-ARM',
                    link: repository,
                  ),
                  _Row(
                    label: texts.builtOn,
                    value: 'github.com/boykopovar/AnyPS5',
                    link: upstream,
                  ),
                ],
              ),
            ),
            // The switches beside the text: a phone on its side has more width than height.
            if (_vibration != null ||
                _motion != null ||
                _remotePlay != null) ...[
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_vibration != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          texts.vibration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          texts.vibrationDetail,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _vibration!,
                        onChanged: (value) {
                          setState(() => _vibration = value);
                          widget.onVibration?.call(value);
                        },
                      ),
                    if (_motion != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          texts.motion,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          texts.motionDetail,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _motion!,
                        onChanged: (value) {
                          setState(() => _motion = value);
                          widget.onMotion?.call(value);
                        },
                      ),
                    if (_remotePlay != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          texts.remotePlay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          texts.remotePlayDetail,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                        value: _remotePlay!,
                        onChanged: (value) {
                          setState(() => _remotePlay = value);
                          widget.onRemotePlay?.call(value);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.link});

  final String label;
  final String value;
  final String? link;

  @override
  Widget build(BuildContext context) {
    final target = link;
    return InkWell(
      onTap: target == null
          ? null
          : () => launchUrl(
              Uri.parse(target),
              mode: LaunchMode.externalApplication,
            ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  color: target == null
                      ? Colors.white
                      : const Color(0xFF8AB4FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (target != null) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.open_in_new_rounded,
                size: 15,
                color: Color(0xFF8AB4FF),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
