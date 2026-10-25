import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../strings.dart';
import '../together/activity.dart';
import '../together/discover.dart';
import '../together/together_hub.dart';
import 'find_players_view.dart';
import 'together_widgets.dart';

/// A new looking-for-group post: the game (one of the reader's, or a title ID), what for and how
/// many players on the left; when, how long, languages and a note on the right, the way a phone
/// held sideways has room for both.
class LfgForm extends StatefulWidget {
  const LfgForm({
    super.key,
    required this.hub,
    required this.onCancel,
    required this.onPosted,
    this.gameName,
  });

  final TogetherHub hub;
  final VoidCallback onCancel;
  final VoidCallback onPosted;
  final String? Function(String titleId)? gameName;

  @override
  State<LfgForm> createState() => _LfgFormState();
}

class _LfgFormState extends State<LfgForm> {
  final _titleId = TextEditingController();
  final _note = TextEditingController();
  List<GameRef> _games = const [];
  String? _picked;
  bool _other = false;
  LfgPurpose _purpose = LfgPurpose.online;
  int _slots = 1;
  Duration? _startIn;
  int _hours = 3;
  List<String>? _languages;
  String? _error;
  bool _busy = false;

  static const _starts = [null, 30, 60, 120, 240];
  static const _lengths = [1, 2, 3, 6, 12];

  @override
  void initState() {
    super.initState();
    final discover = widget.hub.discover;
    _games = [for (final game in discover.boardGames) game.game];
    discover
        .myGames()
        .then((mine) {
          if (!mounted) return;
          final known = mine.map((game) => game.titleId).toSet();
          setState(() {
            _games = [
              ...mine,
              ..._games.where((game) => !known.contains(game.titleId)),
            ];
            _picked ??= _games.firstOrNull?.titleId;
          });
        })
        .catchError((_) {});
    _picked = _games.firstOrNull?.titleId;
    if (discover.discovery == null) {
      discover.loadDiscovery().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _titleId.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The languages picked, at first the ones the reader plays in, or the app's.
  List<String> _chosen(Strings texts) {
    if (_languages case final picked?) return picked;
    final mine =
        widget.hub.discover.discovery?.languages
            .take(LfgDraft.maxLanguages)
            .toList() ??
        const [];
    return mine.isNotEmpty ? mine : [texts.language];
  }

  LfgDraft _draft(Strings texts) => LfgDraft(
    titleId: _other ? _titleId.text.trim().toUpperCase() : _picked ?? '',
    purpose: _purpose,
    languages: _chosen(texts),
    slots: _slots,
    startIn: _startIn,
    hours: _hours,
    note: _note.text,
  );

  Future<void> _post() async {
    final texts = Texts.of(context);
    final draft = _draft(texts);
    if (draft.issue case final issue?) {
      setState(() => _error = texts.draftIssue(issue));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.hub.discover.post(draft);
      if (mounted) widget.onPosted();
      return;
    } on Object catch (error) {
      if (mounted) setState(() => _error = lfgFailure(texts, error));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final most = LfgDraft.maxSlots(_purpose);
    final languages = _chosen(texts);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 16, 16),
      children: [
        Text(
          texts.lfgNew,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          texts.lfgNewLead,
          style: const TextStyle(color: Colors.white38, fontSize: 12.5),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(texts.lfgPickGame),
                  ChoiceRow(
                    children: [
                      for (final game in _games.take(8))
                        ChoicePill(
                          label:
                              widget.gameName?.call(game.titleId) ??
                              game.name(texts.language),
                          selected: !_other && _picked == game.titleId,
                          onTap: () => setState(() {
                            _other = false;
                            _picked = game.titleId;
                          }),
                        ),
                      ChoicePill(
                        label: texts.otherGame,
                        selected: _other || _games.isEmpty,
                        onTap: () => setState(() => _other = true),
                      ),
                    ],
                  ),
                  if (_other || _games.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: _titleId,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration: _field(texts.titleIdHint),
                        onChanged: (_) => _other = true,
                      ),
                    ),
                  SectionLabel(texts.whatFor),
                  ChoiceRow(
                    children: [
                      for (final purpose in LfgPurpose.values)
                        ChoicePill(
                          label: texts.purpose(purpose),
                          selected: _purpose == purpose,
                          onTap: () => setState(() {
                            _purpose = purpose;
                            _slots = _slots.clamp(
                              1,
                              LfgDraft.maxSlots(purpose),
                            );
                          }),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      texts.purposeHint(_purpose),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SectionLabel(texts.playersWanted),
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: '−',
                        onPressed: _slots > 1
                            ? () => setState(() => _slots--)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_slots',
                          key: const ValueKey('lfg slots'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: '+',
                        onPressed: _slots < most
                            ? () => setState(() => _slots++)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '/ $most',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(texts.when),
                  ChoiceRow(
                    children: [
                      for (final minutes in _starts)
                        ChoicePill(
                          label: minutes == null
                              ? texts.startsNow
                              : texts.inMinutes(minutes),
                          selected: _startIn?.inMinutes == minutes,
                          onTap: () => setState(
                            () => _startIn = minutes == null
                                ? null
                                : Duration(minutes: minutes),
                          ),
                        ),
                    ],
                  ),
                  SectionLabel(texts.endsAfter),
                  ChoiceRow(
                    children: [
                      for (final hours in _lengths)
                        ChoicePill(
                          label: texts.hoursN(hours),
                          selected: _hours == hours,
                          onTap: () => setState(() => _hours = hours),
                        ),
                    ],
                  ),
                  SectionLabel(texts.languagesUpTo),
                  ChoiceRow(
                    children: [
                      for (final code in {...languages, ...offeredLanguages})
                        ChoicePill(
                          label: texts.languageName(code),
                          selected: languages.contains(code),
                          onTap: languages.contains(code)
                              ? () => setState(
                                  () => _languages = languages
                                      .where((l) => l != code)
                                      .toList(),
                                )
                              : languages.length < LfgDraft.maxLanguages
                              ? () => setState(
                                  () => _languages = [...languages, code],
                                )
                              : null,
                        ),
                    ],
                  ),
                  SectionLabel(texts.note),
                  TextField(
                    controller: _note,
                    maxLength: LfgDraft.maxNote,
                    maxLines: 2,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _field(texts.notePlaceholder),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _error == null
                  ? const SizedBox.shrink()
                  : Text(
                      _error!,
                      style: const TextStyle(
                        color: togetherError,
                        fontSize: 13,
                      ),
                    ),
            ),
            TextButton(
              onPressed: _busy ? null : widget.onCancel,
              child: Text(texts.cancel),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _busy ? null : _post,
              icon: const Icon(Icons.campaign_rounded, size: 18),
              label: Text(texts.postIt),
            ),
          ],
        ),
      ],
    );
  }

  static InputDecoration _field(String hint) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
    filled: true,
    fillColor: const Color(0x14FFFFFF),
    counterStyle: const TextStyle(color: Colors.white30),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
