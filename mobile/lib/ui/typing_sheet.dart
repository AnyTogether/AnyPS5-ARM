import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection/session.dart';
import '../protocol/messages.dart';
import '../strings.dart';
import '../typing_strings.dart';

/// The game asks for text (a save's name, a code): the phone's own keyboard types it. The sheet
/// rises over whatever the phone shows with the game's prompt, the text it starts with and how
/// many characters it takes; Send puts the text into the game, Cancel closes the game's keyboard.
/// It goes away by itself once the game stops asking, or another phone answered.
class TypingSheet extends StatefulWidget {
  const TypingSheet({
    super.key,
    required this.prompt,
    required this.onAnswer,
    this.look,
  });

  final ValueListenable<TextPrompt?> prompt;
  final void Function(TextPrompt prompt, String text, TypedAction action)
  onAnswer;

  /// The launcher's theme, whose accent the sheet wears.
  final ValueListenable<Look?>? look;

  static const fallbackAccent = Color(0xFF4F94FF);

  /// UTF-16 units, as the game counts its characters.
  static int units(String text) => text.length;

  /// [text] cut to [max] UTF-16 units without splitting a character, one line unless [multiline].
  static String fit(String text, int max, {required bool multiline}) {
    var value = multiline ? text : text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (max <= 0 || value.length <= max) return value;
    final runes = value.runes.toList();
    final out = StringBuffer();
    var used = 0;
    for (final rune in runes) {
      final width = rune > 0xFFFF ? 2 : 1;
      if (used + width > max) break;
      out.writeCharCode(rune);
      used += width;
    }
    value = out.toString();
    return value;
  }

  @override
  State<TypingSheet> createState() => _TypingSheetState();
}

class _TypingSheetState extends State<TypingSheet> {
  TextPrompt? _shown;
  bool _open = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// The field's own overlay (its selection handles need one) holds the sheet; it is built
  /// again with this state.
  late final _entry = OverlayEntry(builder: _entryBuilder);

  @override
  void initState() {
    super.initState();
    widget.prompt.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(TypingSheet old) {
    super.didUpdateWidget(old);
    if (old.prompt != widget.prompt) {
      old.prompt.removeListener(_changed);
      widget.prompt.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.prompt.removeListener(_changed);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    final prompt = widget.prompt.value;
    if (prompt == null) {
      if (!_open) return;
      _focus.unfocus();
      setState(() => _open = false);
      return;
    }
    if (_open && _shown?.id == prompt.id) return;
    final text = TypingSheet.fit(
      prompt.text,
      prompt.maxLength,
      multiline: prompt.multiline,
    );
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _shown = prompt;
      _open = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _focus.requestFocus();
    });
  }

  void _answer(TypedAction action) {
    final prompt = _shown;
    if (prompt == null || !_open) return;
    HapticFeedback.selectionClick();
    widget.onAnswer(prompt, _controller.text, action);
    _focus.unfocus();
    setState(() => _open = false);
  }

  TextInputType _keyboard(TextPrompt prompt) => switch (prompt.keyboard) {
    'number' => TextInputType.number,
    'url' => TextInputType.url,
    'mail' => TextInputType.emailAddress,
    _ => prompt.multiline ? TextInputType.multiline : TextInputType.text,
  };

  TextInputAction _enter(TextPrompt prompt) {
    if (prompt.multiline) return TextInputAction.newline;
    return switch (prompt.enter) {
      'search' => TextInputAction.search,
      'go' => TextInputAction.go,
      _ => TextInputAction.send,
    };
  }

  @override
  Widget build(BuildContext context) {
    _entry.markNeedsBuild();
    return IgnorePointer(
      ignoring: !_open,
      child: Overlay(initialEntries: [_entry]),
    );
  }

  Widget _entryBuilder(BuildContext context) {
    final prompt = _shown;
    if (prompt == null) return const SizedBox.shrink();
    final texts = Texts.of(context);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final look = widget.look;
    if (look == null) return _layer(context, prompt, texts, still, inset, null);
    return ValueListenableBuilder<Look?>(
      valueListenable: look,
      builder: (context, worn, _) =>
          _layer(context, prompt, texts, still, inset, worn),
    );
  }

  Widget _layer(
    BuildContext context,
    TextPrompt prompt,
    Strings texts,
    bool still,
    double inset,
    Look? look,
  ) {
    final accent = look?.accent ?? TypingSheet.fallbackAccent;
    final max = prompt.maxLength;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _open ? 1 : 0,
              duration: Duration(milliseconds: still ? 1 : 220),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const ColoredBox(color: Color(0xA6050811)),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: Duration(milliseconds: still ? 1 : 260),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: inset,
            child: SafeArea(
              top: false,
              child: Center(
                child: AnimatedSlide(
                  offset: _open ? Offset.zero : const Offset(0, 1.2),
                  duration: Duration(milliseconds: still ? 1 : 420),
                  curve: _open ? Curves.easeOutBack : Curves.easeInCubic,
                  child: Container(
                    key: const ValueKey('typing-sheet'),
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xF2121726),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 40,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.keyboard_alt_outlined,
                              size: 16,
                              color: accent,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              texts.upper(texts.typeKicker),
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          prompt.title.isEmpty ? texts.typeTitle : prompt.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.08,
                            letterSpacing: -0.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('typing-field'),
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          keyboardType: _keyboard(prompt),
                          textInputAction: _enter(prompt),
                          minLines: 1,
                          maxLines: prompt.multiline ? 4 : 1,
                          cursorColor: accent,
                          inputFormatters: [
                            if (!prompt.multiline)
                              FilteringTextInputFormatter.deny(
                                RegExp(r'[\r\n]'),
                              ),
                            if (max > 0) LengthLimitingTextInputFormatter(max),
                          ],
                          onSubmitted: prompt.multiline
                              ? null
                              : (_) => _answer(TypedAction.submit),
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: prompt.placeholder.isEmpty
                                ? texts.typeKeyboardHint
                                : prompt.placeholder,
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF1C2335),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0x1AFFFFFF),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: accent, width: 1.4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (max > 0)
                              Text(
                                '${TypingSheet.units(_controller.text)}/$max',
                                key: const ValueKey('typing-count'),
                                style: TextStyle(
                                  color:
                                      TypingSheet.units(_controller.text) >= max
                                      ? const Color(0xFFFF9F33)
                                      : Colors.white38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            const Spacer(),
                            TextButton(
                              key: const ValueKey('typing-cancel'),
                              onPressed: () => _answer(TypedAction.cancel),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white70,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(texts.typeCancel),
                            ),
                            const SizedBox(width: 6),
                            FilledButton(
                              key: const ValueKey('typing-send'),
                              onPressed: () => _answer(TypedAction.submit),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Text(texts.typeEnter(prompt.enter)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
