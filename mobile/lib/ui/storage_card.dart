import 'package:flutter/material.dart';

import '../media_strings.dart';
import '../strings.dart';
import '../together/storage.dart';
import '../together/together_account.dart';
import 'together_widgets.dart';

/// The account's cloud storage: how much of the quota saves and media use, as one bar in two
/// parts. Shows nothing at all where the server keeps no files, or before anyone signs in.
class StorageCard extends StatefulWidget {
  const StorageCard({super.key, required this.account});

  final TogetherAccount account;

  @override
  State<StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<StorageCard> {
  StorageUsage? _usage;
  bool _enabled = false;
  bool _failed = false;

  static const _savesColor = togetherAccent;
  static const _mediaColor = Color(0xFFB59CFF);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = widget.account;
    if (account.user == null) return;
    final on = await account.storageEnabled();
    if (!mounted) return;
    setState(() => _enabled = on);
    if (!on) return;
    try {
      final usage = await account.storageUsage();
      if (mounted) setState(() => _usage = usage);
    } on TogetherProblem catch (problem) {
      if (!mounted) return;
      setState(() {
        if (problem.code == 'storage_disabled') {
          _enabled = false;
        } else {
          _failed = true;
        }
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    final texts = Texts.of(context);
    final usage = _usage;
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_outlined, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  texts.storageTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (usage != null)
                Text(
                  texts.storageUsed(usage),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_failed)
            Text(
              texts.storageFailed,
              style: const TextStyle(color: togetherError, fontSize: 12.5),
            )
          else ...[
            _bar(usage),
            const SizedBox(height: 8),
            if (usage != null)
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _legend(
                    _savesColor,
                    '${texts.storageSaves} ${texts.megabytes(usage.saves)}',
                  ),
                  _legend(
                    _mediaColor,
                    '${texts.storageMedia} ${texts.megabytes(usage.media)}',
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              texts.storageDetail,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Saves, then media, along the whole quota.
  Widget _bar(StorageUsage? usage) {
    final limit = usage?.limit ?? 0;
    double part(int bytes) => limit <= 0 ? 0 : (bytes / limit).clamp(0, 1);
    final saves = part(usage?.saves ?? 0);
    final media = part(usage?.media ?? 0).clamp(0.0, 1 - saves);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0x1FFFFFFF)),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * saves,
                child: const ColoredBox(color: _savesColor),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                left: constraints.maxWidth * saves,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * media,
                child: const ColoredBox(color: _mediaColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );
}
