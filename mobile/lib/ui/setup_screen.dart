import 'dart:io';

import 'package:flutter/material.dart';

import '../connection/session.dart';
import '../strings.dart';

/// Getting connected, step by step: finding the Mac, the Mac allowing the phone, ready. Every
/// step moves on by itself; when nothing is found, tips and an address field show.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.session,
    required this.foundMac,
    required this.showManual,
    required this.onAddress,
    required this.onRetry,
  });

  final Session session;

  /// The launcher Bonjour found, by name, before the session connects to it.
  final String? foundMac;
  final bool showManual;
  final void Function(InternetAddress address) onAddress;
  final VoidCallback onRetry;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _StepState { waiting, active, done, failed }

class _SetupScreenState extends State<SetupScreen> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final session = widget.session;
    final status = session.status;
    final found =
        widget.foundMac != null ||
        status == ConnectionStatus.pairing ||
        status == ConnectionStatus.connected;
    final refused = status == ConnectionStatus.rejected;
    final macName = session.macName ?? widget.foundMac;

    final findStep = found ? _StepState.done : _StepState.active;
    final allowStep = refused
        ? _StepState.failed
        : status == ConnectionStatus.connected
        ? _StepState.done
        : status == ConnectionStatus.pairing || found
        ? _StepState.active
        : _StepState.waiting;
    final readyStep = status == ConnectionStatus.connected
        ? _StepState.done
        : _StepState.waiting;

    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepRow(
                    state: findStep,
                    title: found
                        ? texts.found(macName ?? 'Mac')
                        : texts.searching,
                    detail: found ? null : texts.searchingDetail,
                  ),
                  if (!found && widget.showManual) _manual(texts),
                  _StepRow(
                    state: allowStep,
                    title: refused
                        ? (session.rejectedReason == 'busy'
                              ? texts.busy
                              : texts.refused)
                        : texts.allowOnMac,
                    detail: status == ConnectionStatus.pairing
                        ? texts.sameCode
                        : null,
                    child:
                        status == ConnectionStatus.pairing &&
                            session.code != null
                        ? _code(session.code!)
                        : refused
                        ? _retry(texts)
                        : null,
                  ),
                  _StepRow(
                    state: readyStep,
                    title: texts.ready,
                    detail: status == ConnectionStatus.connected
                        ? texts.opening
                        : null,
                    last: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _code(String code) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final digit in code.split(''))
          Container(
            margin: const EdgeInsets.only(right: 10),
            width: 50,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _retry(Strings texts) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton(
      onPressed: widget.onRetry,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0x55FFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      ),
      child: Text(texts.retry),
    ),
  );

  Widget _manual(Strings texts) => Padding(
    padding: const EdgeInsets.only(left: 44, bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          texts.notFound,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _address,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '192.168.1.20',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0x33FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
            onSubmitted: (text) {
              final address = InternetAddress.tryParse(text.trim());
              if (address != null) widget.onAddress(address);
            },
          ),
        ),
      ],
    ),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.state,
    required this.title,
    this.detail,
    this.child,
    this.last = false,
  });

  final _StepState state;
  final String title;
  final String? detail;
  final Widget? child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => const Color(0xFF4CD964),
      _StepState.active => const Color(0xFFFFC857),
      _StepState.failed => const Color(0xFFFF6B5E),
      _StepState.waiting => const Color(0x40FFFFFF),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: switch (state) {
              _StepState.done => Icon(
                Icons.check_circle_rounded,
                color: color,
                size: 26,
              ),
              _StepState.failed => Icon(
                Icons.error_rounded,
                color: color,
                size: 26,
              ),
              _StepState.active => Padding(
                padding: const EdgeInsets.all(4),
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: color,
                ),
              ),
              _StepState.waiting => Icon(
                Icons.circle_outlined,
                color: color,
                size: 24,
              ),
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: state == _StepState.waiting
                        ? Colors.white38
                        : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail!,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ],
                ?child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The connection's colour: green connected, amber on the way, red refused.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: size),
      ],
    ),
  );
}
