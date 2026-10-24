import 'package:flutter/material.dart';

import '../strings.dart';
import '../together/together_account.dart';
import 'together_screen.dart';

/// AnyTogether on the phone: who is signed in, or the ways in. With a Mac connected
/// ([macName]), its account comes first: one tap, the Mac approves. Signed in, [onOpen] goes on
/// to AnyTogether's own screen, the sheets closed first.
Future<void> showTogether(
  BuildContext context, {
  required TogetherAccount account,
  required String? macName,
  required Future<void> Function()? onUseMac,
  void Function(TogetherTab tab)? onOpen,
  Uri? launcherServer,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(0xF2101218),
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 980),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => _Together(
    account: account,
    macName: macName,
    onUseMac: onUseMac,
    onOpen: onOpen,
    launcherServer: launcherServer,
  ),
);

class _Together extends StatefulWidget {
  const _Together({
    required this.account,
    required this.macName,
    required this.onUseMac,
    this.onOpen,
    this.launcherServer,
  });

  final TogetherAccount account;
  final String? macName;
  final Future<void> Function()? onUseMac;
  final void Function(TogetherTab tab)? onOpen;

  /// The server the connected launcher uses, offered when it is not this one.
  final Uri? launcherServer;

  @override
  State<_Together> createState() => _TogetherState();
}

class _TogetherState extends State<_Together> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _server = TextEditingController();
  String? _error;
  bool _editingServer = false;
  String? _serverError;

  static const _title = TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );
  static const _faint = TextStyle(color: Colors.white60, fontSize: 14);

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  /// Runs a step, showing what went wrong under it; a stop on the phone shows nothing.
  Future<void> _try(Future<void> Function() step) async {
    setState(() => _error = null);
    try {
      await step();
    } on TogetherCancelled {
      if (mounted && widget.account.user == null && widget.onUseMac != null) {
        setState(() => _error = Texts.of(context).togetherMacDeclined);
      }
    } on TogetherProblem catch (problem) {
      if (mounted) setState(() => _error = problem.title);
    } on Object {
      if (mounted) {
        setState(() => _error = Texts.of(context).togetherUnreachable);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final account = widget.account;
        final user = account.user;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              28,
              22,
              28,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                user != null
                    ? _signedIn(texts, user)
                    : _signIn(texts, account.step),
                _serverRow(texts),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _signedIn(Strings texts, TogetherUser user) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Mark(),
      const SizedBox(width: 18),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('@${user.handle}', style: _title),
            const SizedBox(height: 2),
            Text(
              user.displayName,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Text(texts.togetherSignedIn, style: _faint),
            if (widget.onOpen case final open?) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final (tab, icon, label) in _tabs(texts))
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                        open(tab);
                      },
                      icon: Icon(icon, size: 18),
                      label: Text(label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 18),
      OutlinedButton(
        onPressed: widget.account.signOut,
        child: Text(texts.togetherSignOut),
      ),
    ],
  );

  static String _shown(Uri server) => server.scheme == 'https'
      ? (server.hasPort ? '${server.host}:${server.port}' : server.host)
      : server.toString();

  /// Which AnyTogether this is, and a way to another one (a self-hosted server); the launcher's
  /// first when it uses another.
  Widget _serverRow(Strings texts) {
    final account = widget.account;
    final launcher = widget.launcherServer;
    final offer =
        launcher != null && launcher != account.base && !account.serverFixed;
    const small = TextStyle(color: Colors.white54, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(color: Color(0x14FFFFFF), height: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(texts.togetherServer, style: small),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _shown(account.base),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              if (offer)
                TextButton.icon(
                  onPressed: () => _useServer(launcher),
                  icon: const Icon(Icons.laptop_mac_rounded, size: 16),
                  label: Text(
                    texts.togetherServerMac(
                      widget.macName ?? 'Mac',
                      _shown(launcher),
                    ),
                  ),
                ),
              if (!account.serverFixed)
                TextButton(
                  onPressed: () => setState(() {
                    _editingServer = !_editingServer;
                    _serverError = null;
                    _server.text = account.base.toString();
                  }),
                  child: Text(
                    _editingServer ? texts.cancel : texts.togetherServerChange,
                  ),
                ),
            ],
          ),
          if (_editingServer) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _server,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: texts.togetherServer,
                      hintText: 'https://',
                    ),
                    onSubmitted: (_) => _saveServer(),
                  ),
                ),
                const SizedBox(width: 10),
                if (account.base != standardServer)
                  TextButton(
                    onPressed: () => _useServer(standardServer),
                    child: Text(texts.reset),
                  ),
                FilledButton.tonal(
                  onPressed: _saveServer,
                  child: Text(texts.togetherServerUse),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _serverError ?? texts.togetherServerDetail,
              style: TextStyle(
                color: _serverError == null
                    ? Colors.white54
                    : const Color(0xFFFF8A80),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _saveServer() {
    final server = serverAddress(_server.text);
    if (server == null) {
      setState(() => _serverError = Texts.of(context).togetherServerInvalid);
      return;
    }
    _useServer(server);
  }

  Future<void> _useServer(Uri server) async {
    await widget.account.useServer(server);
    if (mounted) {
      setState(() {
        _editingServer = false;
        _serverError = null;
      });
    }
  }

  static List<(TogetherTab, IconData, String)> _tabs(Strings texts) => [
    (TogetherTab.friends, Icons.people_alt_rounded, texts.friends),
    (TogetherTab.messages, Icons.chat_bubble_rounded, texts.messages),
  ];

  Widget _signIn(Strings texts, TogetherStep step) {
    final mac = widget.macName;
    final useMac = widget.onUseMac;
    final waiting = step is WaitingForMac;
    final busy = step is Busy;
    final macSide = mac == null || useMac == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: waiting ? null : () => _try(useMac),
                icon: waiting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.laptop_mac_rounded),
                label: Text(
                  waiting
                      ? texts.togetherWaitingMac(mac)
                      : texts.togetherUseMac(mac),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                texts.togetherUseMacDetail,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
              if (waiting)
                TextButton(
                  onPressed: widget.account.cancel,
                  child: Text(texts.cancel),
                ),
            ],
          );
    final emailSide = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (macSide != null) Text(texts.togetherOrEmail, style: _faint),
        if (step case CodeSent(:final email)) ...[
          Text(
            texts.togetherCodeSent(email),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(labelText: texts.togetherCode),
            onChanged: (text) {
              final digits = text.replaceAll(RegExp(r'\D'), '');
              if (digits.length == 6) {
                _try(() => widget.account.verifyEmail(digits));
              }
            },
          ),
          TextButton(
            onPressed: () {
              _code.clear();
              widget.account.cancel();
            },
            child: Text(texts.togetherOtherEmail),
          ),
        ] else ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            decoration: InputDecoration(labelText: texts.togetherEmail),
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: busy ? null : _sendCode,
            child: Text(texts.togetherSendCode),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const _Mark(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(texts.together, style: _title),
                  Text(texts.togetherIntro, style: _faint),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // A phone on its side: the Mac's way and the email way side by side.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (macSide != null) ...[
              Expanded(child: macSide),
              const SizedBox(width: 28),
            ],
            Expanded(child: emailSide),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13.5),
          ),
        ],
      ],
    );
  }

  void _sendCode() {
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    _try(() => widget.account.startEmail(email));
  }
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0x228AB4FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(Icons.group_rounded, color: Color(0xFF8AB4FF)),
  );
}
