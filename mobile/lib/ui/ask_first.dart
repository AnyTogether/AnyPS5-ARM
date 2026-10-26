import 'package:flutter/material.dart';

import '../strings.dart';
import 'together_widgets.dart';

/// A social step that cannot be taken back asks first, as unsending does: the question, Cancel
/// and the step itself in red. True only when the step was chosen.
Future<bool> askFirst(
  BuildContext context, {
  required String question,
  required String action,
}) async {
  final texts = Texts.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF151821),
      content: Text(
        question,
        style: const TextStyle(color: Colors.white70, fontSize: 14.5),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            texts.cancel,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: togetherError,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return sure == true;
}
