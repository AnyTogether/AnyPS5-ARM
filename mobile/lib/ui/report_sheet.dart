import 'package:flutter/material.dart';

import '../chat_strings.dart';
import '../e2ee_strings.dart';
import '../strings.dart';
import '../together/reports.dart';
import 'find_players_view.dart' show ChoicePill, ChoiceRow;
import 'together_widgets.dart';

/// "Report this message": why, a note if there is more to say, and Send. [send] reports it;
/// true once it went, with a thank you on the way out.
Future<bool> reportMessageSheet(
  BuildContext context, {
  required Future<void> Function(ReportReason reason, String note) send,
}) async {
  final texts = Texts.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF151821),
    builder: (_) => Texts(
      strings: texts,
      child: _ReportSheet(send: send),
    ),
  );
  if (sent == true) {
    messenger?.showSnackBar(SnackBar(content: Text(texts.reportSent)));
  }
  return sent == true;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.send});

  final Future<void> Function(ReportReason reason, String note) send;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    final texts = Texts.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.send(reason, _note.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = togetherFailure(texts, error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: togetherError, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    texts.reportMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              texts.reportMessageLead,
              style: const TextStyle(color: Colors.white60, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            ChoiceRow(
              children: [
                for (final reason in ReportReason.values)
                  ChoicePill(
                    label: texts.reasonLabel(reason),
                    selected: _reason == reason,
                    onTap: _busy
                        ? null
                        : () => setState(() => _reason = reason),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              enabled: !_busy,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: texts.reportNote,
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: togetherError, fontSize: 13),
                ),
              ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: togetherError,
                  foregroundColor: togetherInk,
                ),
                onPressed: _reason == null || _busy ? null : _send,
                child: Text(texts.sendReport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
