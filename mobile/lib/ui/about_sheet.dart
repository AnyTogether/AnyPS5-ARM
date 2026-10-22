import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../strings.dart';
import '../version.dart';

/// Who made the app and where its code is, over the screen it was opened from.
Future<void> showAbout(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(0xF2101218),
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => const _About(),
);

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return SafeArea(
      child: Padding(
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
              width: 150,
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
