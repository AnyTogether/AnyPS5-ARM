import 'package:flutter/material.dart';

import '../e2ee_strings.dart';
import '../strings.dart';
import '../together/e2ee.dart';
import '../together/e2ee_devices.dart';
import '../together/messages.dart';
import 'together_widgets.dart';

/// What a direct conversation's lock means, opened from its header: whether it is end-to-end
/// encrypted and why, the safety number to compare, the "we compared them" mark, and both
/// people's devices.
Future<void> showEncryptionSheet(
  BuildContext context, {
  required Messages messages,
  required Conversation conversation,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(0xF2101218),
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 720),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) =>
      EncryptionSheet(messages: messages, conversation: conversation),
);

class EncryptionSheet extends StatefulWidget {
  const EncryptionSheet({
    super.key,
    required this.messages,
    required this.conversation,
  });

  final Messages messages;
  final Conversation conversation;

  @override
  State<EncryptionSheet> createState() => _EncryptionSheetState();
}

class _EncryptionSheetState extends State<EncryptionSheet> {
  Future<String?>? _number;
  String? _numberOf;

  E2ee? get _e2ee => widget.messages.e2ee;

  /// The safety number, worked out again only when a device list changed.
  Future<String?> _safety(DirectChat chat) {
    final e = _e2ee!;
    final key = [
      ...?e.devicesOf(chat.me)?.ids,
      '|',
      ...?e.devicesOf(chat.other)?.ids,
    ].join(',');
    if (_number == null || _numberOf != key) {
      _numberOf = key;
      _number = e.safetyNumberOf(chat);
    }
    return _number!;
  }

  @override
  Widget build(BuildContext context) {
    final e = _e2ee;
    if (e == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) {
        final texts = Texts.of(context);
        final chat = widget.messages.chatOf(widget.conversation);
        if (chat == null) return const SizedBox.shrink();
        final lock = e.lockOf(chat);
        final name = widget.conversation.name(chat.me);
        final on = lock.state == ChatLock.encrypted;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Heading(lock: lock, name: name),
                if (on) ...[
                  const SizedBox(height: 18),
                  FutureBuilder<String?>(
                    future: _safety(chat),
                    builder: (context, snapshot) => _SafetyNumber(
                      digits: snapshot.data,
                      how: texts.e2eeSafetyHow(name),
                      compared: lock.compared,
                      onCompared: () => e.markCompared(chat.id),
                    ),
                  ),
                ],
                if (lock.state != ChatLock.plain) ...[
                  SectionLabel(texts.e2eeDevices),
                  _DeviceGroup(
                    title: texts.e2eeYou,
                    devices: e.devicesOf(chat.me)?.active ?? const [],
                    thisDevice: e.device?.deviceId,
                  ),
                  const SizedBox(height: 10),
                  _DeviceGroup(
                    title: name,
                    devices: e.devicesOf(chat.other)?.active ?? const [],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    texts.e2eeNewDeviceNote,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The lock, large, and what it means here.
class _Heading extends StatelessWidget {
  const _Heading({required this.lock, required this.name});

  final ConversationLock lock;
  final String name;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final (icon, color, title, detail) = switch (lock.state) {
      ChatLock.plain => (
        Icons.lock_open_rounded,
        Colors.white54,
        texts.e2eeOff,
        texts.e2eeOffDetail(name),
      ),
      ChatLock.noDevice => (
        Icons.lock_rounded,
        togetherAway,
        texts.e2eeOn,
        texts.e2eeNoDevice(name),
      ),
      _ => (
        lock.compared ? Icons.verified_user_rounded : Icons.lock_rounded,
        togetherAccent,
        texts.e2eeOn,
        texts.e2eeOnDetail(name),
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Twelve groups of five digits, set like a key card, how to compare them, and the mark.
class _SafetyNumber extends StatelessWidget {
  const _SafetyNumber({
    required this.digits,
    required this.how,
    required this.compared,
    required this.onCompared,
  });

  final String? digits;
  final String how;
  final bool compared;
  final VoidCallback onCompared;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final groups = digits == null ? const <String>[] : safetyGroups(digits!);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: compared ? const Color(0x668AB4FF) : const Color(0x14FFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  texts.upper(texts.e2eeSafetyNumber),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: compared
                    ? Row(
                        key: const ValueKey('compared'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: togetherAccent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            texts.e2eeCompared,
                            style: const TextStyle(
                              color: togetherAccent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('not')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: groups.join(' '),
            excludeSemantics: true,
            child: groups.isEmpty
                ? const SizedBox(
                    height: 96,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      // Four to a row where there is room, three on a narrow phone.
                      final perRow = box.maxWidth >= 360 ? 4 : 3;
                      return Wrap(
                        spacing: 0,
                        runSpacing: 8,
                        children: [
                          for (final group in groups)
                            SizedBox(
                              width: box.maxWidth / perRow,
                              child: Text(
                                group,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 2.2,
                                  height: 1.2,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            how,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (!compared) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: groups.isEmpty ? null : onCompared,
                style: FilledButton.styleFrom(
                  backgroundColor: togetherAccent,
                  foregroundColor: togetherInk,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  texts.e2eeMarkCompared,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One person's devices: name, when it was added, and which one this phone is.
class _DeviceGroup extends StatelessWidget {
  const _DeviceGroup({
    required this.title,
    required this.devices,
    this.thisDevice,
  });

  final String title;
  final List<PublicDevice> devices;
  final String? thisDevice;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('—', style: TextStyle(color: Colors.white38)),
          ),
        for (final device in devices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  device.id == thisDevice
                      ? Icons.smartphone_rounded
                      : Icons.devices_other_rounded,
                  size: 18,
                  color: Colors.white54,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    device.name.isEmpty ? '…' : device.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (device.id == thisDevice) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1F8AB4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      texts.e2eeThisDevice,
                      style: const TextStyle(
                        color: togetherAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  _fingerprint(device.id),
                  style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The device ID's start, to tell two devices of the same name apart.
String _fingerprint(String id) =>
    id.length < 8 ? id : '${id.substring(0, 4)} ${id.substring(4, 8)}';
