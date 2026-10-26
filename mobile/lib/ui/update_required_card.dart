import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../safety_strings.dart';
import '../strings.dart';
import '../together/together_account.dart';
import '../version.dart';

/// AnyTogether retired this version (client_too_old): a card at the top of the screen, over
/// whatever the phone shows, with Update (the downloads page, where new versions come from) and
/// Later. Later hides it until AnyTogether asks for a newer minimum.
class UpdateRequiredCard extends StatefulWidget {
  const UpdateRequiredCard({super.key, required this.tooOld, this.open});

  final ValueListenable<ClientTooOld?> tooOld;

  /// Opens the update's page; the system browser when left out (the tests watch it).
  final Future<void> Function(Uri page)? open;

  @override
  State<UpdateRequiredCard> createState() => _UpdateRequiredCardState();
}

class _UpdateRequiredCardState extends State<UpdateRequiredCard> {
  String? _later;

  Future<void> _update(ClientTooOld old) async {
    final page = old.downloadUrl ?? Uri.parse('$repository/releases/latest');
    final open = widget.open;
    if (open != null) return open(page);
    await launchUrl(page, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.tooOld,
    builder: (context, old, _) {
      final texts = Texts.of(context);
      final shown = old != null && old.minimum != _later;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.2),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: !shown
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(old.minimum),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                constraints: const BoxConstraints(maxWidth: 560),
                decoration: BoxDecoration(
                  color: const Color(0xF0101218),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x66FFB74D)),
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
                    const Icon(
                      Icons.system_update_rounded,
                      color: Color(0xFFFFB74D),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            texts.updateRequiredTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            texts.updateRequiredBody(old.minimum, old.current),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _later = old.minimum),
                      child: Text(
                        texts.updateRequiredLater,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => _update(old),
                      child: Text(texts.updateRequiredUpdate),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
