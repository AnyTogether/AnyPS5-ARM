import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../discover_strings.dart';
import '../join_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/join_codes.dart';
import '../together/parties.dart';
import 'activity_tile.dart' show GameIcon;
import 'together_widgets.dart';

const _field = Color(0x14FFFFFF);

InputDecoration _decoration(String hint) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: const TextStyle(color: Colors.white30),
  filled: true,
  fillColor: _field,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
);

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));

/// "Join with a code": a code or its link typed or pasted, what it opens, and asking to join.
class JoinWithCode extends StatefulWidget {
  const JoinWithCode({super.key, required this.codes, this.gameName});

  final JoinCodes codes;
  final String? Function(String titleId)? gameName;

  @override
  State<JoinWithCode> createState() => _JoinWithCodeState();
}

class _JoinWithCodeState extends State<JoinWithCode> {
  final _text = TextEditingController();
  JoinInfo? _info;
  String? _line;
  bool _lineIsError = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final texts = Texts.of(context);
    final code = JoinCode.normalize(_text.text);
    if (code == null) {
      setState(() {
        _info = null;
        _line = texts.notACode;
        _lineIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _line = null;
    });
    try {
      final info = await widget.codes.lookUp(code);
      if (!mounted) return;
      setState(() {
        _info = info;
        _line = info.state == JoinState.none
            ? null
            : texts.asked(info.kind, info.state);
        _lineIsError = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _info = null;
        _line = texts.codeFailure(error);
        _lineIsError = true;
      });
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _ask(JoinInfo info) async {
    final texts = Texts.of(context);
    setState(() => _busy = true);
    try {
      final state = await widget.codes.ask(info.code);
      if (!mounted) return;
      setState(() {
        _info = info.withState(state);
        _line = texts.asked(info.kind, state);
        _lineIsError = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _line = texts.codeFailure(error);
        _lineIsError = true;
      });
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final info = _info;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(texts.joinWithCode),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  letterSpacing: 1,
                ),
                decoration: _decoration('XXXX-XXXX'),
                onSubmitted: (_) => _lookUp(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _lookUp,
              child: Text(texts.lookUp),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          texts.joinWithCodeDetail,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        if (info != null) ...[
          const SizedBox(height: 10),
          _CodeTarget(
            info: info,
            gameName: widget.gameName,
            busy: _busy,
            onAsk: () => _ask(info),
          ),
        ],
        if (_line case final line?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              line,
              style: TextStyle(
                color: _lineIsError ? togetherError : togetherPlaying,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// Whose party or share play a code opens, its game and how full it is, and Ask to join.
class _CodeTarget extends StatelessWidget {
  const _CodeTarget({
    required this.info,
    required this.busy,
    required this.onAsk,
    this.gameName,
  });

  final JoinInfo info;
  final bool busy;
  final VoidCallback onAsk;
  final String? Function(String titleId)? gameName;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final host = info.host;
    final hostName = host?.displayName ?? '';
    final game = info.game;
    final title = switch (info.kind) {
      JoinKind.sharePlay => texts.codeShare(hostName),
      _ => texts.codeParty(hostName),
    };
    final gameTitle = game == null
        ? null
        : gameName?.call(game.titleId) ?? game.name(texts.language);
    // A Play Together game is joined from the launcher, where the game runs.
    final canAsk =
        info.kind != JoinKind.gameSession &&
        info.state == JoinState.none &&
        !info.full;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (host != null)
                Avatar(person: host, size: 36)
              else
                const SizedBox.square(
                  dimension: 36,
                  child: Icon(Icons.celebration_rounded, color: togetherAccent),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        if (host != null) '@${host.handle}',
                        if (info.max > 0) texts.people(info.size, info.max),
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (gameTitle != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                GameIcon(url: game!.iconUrl, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gameTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (info.kind == JoinKind.gameSession)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                texts.codeGame,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            )
          else if (canAsk) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: busy ? null : onAsk,
                child: Text(texts.askToJoin),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The party's join code for its members: the code to read out, until when it works, copying it
/// or its link; the leader makes one, a new one, or stops it.
class PartyCode extends StatelessWidget {
  const PartyCode({
    super.key,
    required this.parties,
    required this.party,
    required this.leader,
    required this.run,
  });

  final Parties parties;
  final Party party;
  final bool leader;

  /// Runs a party step, showing what went wrong.
  final Future<void> Function(Future<void> Function() step) run;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final code = party.joinCode;
    if (code == null || !code.works()) {
      if (!leader) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(texts.codeTitle),
          OutlinedButton.icon(
            onPressed: () => run(() async {
              final made = await parties.makeCode();
              if (made != null && context.mounted) {
                _say(context, texts.codeMade(made.display));
              }
            }),
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text(texts.makeCode),
          ),
          const SizedBox(height: 4),
          Text(
            texts.makeCodeDetail,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(texts.codeTitle),
        Semantics(
          label: '${texts.codeTitle} ${code.code.split('').join(' ')}',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SelectableText(
              code.display,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Text(
          texts.codeDetail(code.expiresAt),
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SmallButton(
              icon: Icons.copy_rounded,
              label: texts.copyCode,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code.display));
                if (context.mounted) _say(context, texts.codeCopied);
              },
            ),
            if (code.url.isNotEmpty)
              _SmallButton(
                icon: Icons.link_rounded,
                label: texts.copyLink,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code.url));
                  if (context.mounted) _say(context, texts.linkCopied);
                },
              ),
            if (leader) ...[
              _SmallButton(
                icon: Icons.refresh_rounded,
                label: texts.newCode,
                onPressed: () => run(() async {
                  final made = await parties.makeCode();
                  if (made != null && context.mounted) {
                    _say(context, texts.codeMade(made.display));
                  }
                }),
              ),
              _SmallButton(
                icon: Icons.block_rounded,
                label: texts.stopCode,
                onPressed: () => run(() async {
                  await parties.stopCode();
                  if (context.mounted) _say(context, texts.codeStopped);
                }),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: togetherAccent,
      backgroundColor: _field,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 12.5)),
  );
}

/// The party's Discord server or channel: opened by anyone in it, set by the leader.
class PartyDiscord extends StatefulWidget {
  const PartyDiscord({
    super.key,
    required this.parties,
    required this.party,
    required this.leader,
    required this.run,
  });

  final Parties parties;
  final Party party;
  final bool leader;
  final Future<void> Function(Future<void> Function() step) run;

  @override
  State<PartyDiscord> createState() => _PartyDiscordState();
}

class _PartyDiscordState extends State<PartyDiscord> {
  late final _text = TextEditingController(text: widget.party.discord ?? '');
  String? _bad;

  @override
  void didUpdateWidget(PartyDiscord old) {
    super.didUpdateWidget(old);
    if (old.party.discord != widget.party.discord) {
      _text.text = widget.party.discord ?? '';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String? link) async {
    final texts = Texts.of(context);
    if (link != null && discordLinkOf(link) == null) {
      setState(() => _bad = texts.discordLinkBad);
      return;
    }
    setState(() => _bad = null);
    await widget.run(() async {
      await widget.parties.setDiscord(
        link == null ? null : discordLinkOf(link),
      );
      if (mounted) {
        _say(
          context,
          link == null ? texts.discordLinkRemoved : texts.discordLinkSaved,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final link = widget.party.discord;
    if (!widget.leader && link == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(texts.discordLink),
        if (link != null)
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(link),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.forum_rounded, size: 18),
            label: Text(texts.openDiscord),
          ),
        if (widget.leader) ...[
          if (link != null) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: _decoration('discord.gg/…'),
                  onSubmitted: (value) =>
                      _save(value.trim().isEmpty ? null : value),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: texts.save,
                onPressed: () =>
                    _save(_text.text.trim().isEmpty ? null : _text.text),
                icon: const Icon(Icons.check_rounded, color: togetherAccent),
              ),
              if (link != null)
                IconButton(
                  tooltip: texts.remove,
                  onPressed: () => _save(null),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _bad ?? texts.discordLinkDetail,
            style: TextStyle(
              color: _bad == null ? Colors.white38 : togetherError,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

/// A Discord invite or channel link as the server keeps it (https://host/path, no query), or
/// null when it is not one; "discord.gg/abc" without the scheme counts.
String? discordLinkOf(String raw) {
  var text = raw.trim();
  if (!text.contains('://')) text = 'https://$text';
  final url = Uri.tryParse(text);
  if (url == null ||
      url.scheme != 'https' ||
      url.userInfo.isNotEmpty ||
      url.hasPort) {
    return null;
  }
  const hosts = {
    'discord.gg',
    'discord.com',
    'www.discord.com',
    'ptb.discord.com',
    'canary.discord.com',
  };
  final host = url.host.toLowerCase();
  if (!hosts.contains(host)) return null;
  final path = url.path.replaceAll(RegExp(r'/$'), '');
  final fits = host == 'discord.gg'
      ? RegExp(r'^/[A-Za-z0-9-]{2,64}$').hasMatch(path)
      : RegExp(r'^/invite/[A-Za-z0-9-]{2,64}$').hasMatch(path) ||
            RegExp(r'^/channels/\d{5,25}(/\d{5,25})?$').hasMatch(path);
  return fits ? 'https://$host$path' : null;
}
