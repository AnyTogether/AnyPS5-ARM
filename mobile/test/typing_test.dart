import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/connection/session.dart';
import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/ui/typing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_test.dart' show FakeLauncher, waitFor;

const prompt = TextPrompt(
  id: 7,
  title: 'Name your save',
  placeholder: 'Save 1',
  text: 'Kral',
  maxLength: 8,
  keyboard: 'text',
  enter: 'go',
);

Future<void> showSheet(
  WidgetTester tester,
  ValueNotifier<TextPrompt?> asked,
  List<(TextPrompt, String, TypedAction)> answers, {
  Strings strings = Strings.english,
}) async {
  await tester.pumpWidget(
    Texts(
      strings: strings,
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('pad')),
              Positioned.fill(
                child: TypingSheet(
                  prompt: asked,
                  onAnswer: (prompt, text, action) =>
                      answers.add((prompt, text, action)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('messages', () {
    test(
      'the launcher says what the game asks for, or that it asks no more',
      () {
        final open = Message.fromJson(
          jsonEncode({
            'type': 'textInput',
            'prompt': {
              'id': 7,
              'kind': 'dialog',
              'title': 'Name your save',
              'placeholder': 'Save 1',
              'text': 'Kral',
              'maxLength': 8,
              'multiline': false,
              'keyboard': 'number',
              'enter': 'go',
            },
          }),
        );
        expect(open, isA<TextInputUpdate>());
        final asked = (open! as TextInputUpdate).prompt!;
        expect(asked.id, 7);
        expect(asked.title, 'Name your save');
        expect(asked.text, 'Kral');
        expect(asked.maxLength, 8);
        expect(asked.keyboard, 'number');
        expect(asked.enter, 'go');
        final closed = Message.fromJson('{"type":"textInput","prompt":null}');
        expect((closed! as TextInputUpdate).prompt, isNull);
        final again =
            Message.fromJson(TextInputUpdate(asked).toJson())!
                as TextInputUpdate;
        expect(again.prompt!.toJson(), asked.toJson());
      },
    );

    test('a prompt from a launcher that leaves fields out still reads', () {
      final open =
          Message.fromJson('{"type":"textInput","prompt":{"id":3}}')!
              as TextInputUpdate;
      expect(open.prompt!.id, 3);
      expect(open.prompt!.keyboard, 'text');
      expect(open.prompt!.maxLength, 0);
    });

    test('the typed text goes as the launcher reads it', () {
      final json = jsonDecode(
        const Typed(
          prompt: 7,
          text: 'Ayşe',
          action: TypedAction.submit,
        ).toJson(),
      ) as Map<String, dynamic>;
      expect(json, {
        'type': 'typed',
        'prompt': 7,
        'text': 'Ayşe',
        'action': 'submit',
      });
    });
  });

  group('fitting the text', () {
    test('is cut to the game\'s length without splitting a character', () {
      expect(TypingSheet.fit('abcdef', 4, multiline: false), 'abcd');
      expect(TypingSheet.fit('ab😀c', 3, multiline: false), 'ab');
      expect(TypingSheet.fit('ab😀c', 4, multiline: false), 'ab😀');
      expect(TypingSheet.fit('a\nb', 0, multiline: false), 'a b');
      expect(TypingSheet.fit('a\nb', 0, multiline: true), 'a\nb');
    });
  });

  group('session', () {
    late SharedPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
    });

    test('keeps the prompt, sends the text and lets the prompt go', () async {
      final launcher = FakeLauncher();
      await launcher.start();
      final session = Session(preferences: preferences, deviceName: 'Pixel 8');
      await session.connect(InternetAddress.loopbackIPv4, launcher.port);
      await waitFor(() => session.status == ConnectionStatus.connected);
      launcher.tell({
        'type': 'textInput',
        'prompt': {'id': 7, 'title': 'Code', 'maxLength': 4},
      });
      await waitFor(() => session.textPrompt.value != null);
      expect(session.textPrompt.value!.title, 'Code');
      session.type(session.textPrompt.value!, '1234', TypedAction.submit);
      expect(session.textPrompt.value, isNull, reason: 'answered, it goes');
      await waitFor(
        () => launcher.received.any((message) => message['type'] == 'typed'),
      );
      final typed = launcher.received.firstWhere(
        (message) => message['type'] == 'typed',
      );
      expect(typed['prompt'], 7);
      expect(typed['text'], '1234');
      expect(typed['action'], 'submit');
      launcher.tell({
        'type': 'textInput',
        'prompt': {'id': 8},
      });
      await waitFor(() => session.textPrompt.value?.id == 8);
      launcher.tell({'type': 'textInput', 'prompt': null});
      await waitFor(() => session.textPrompt.value == null);
      await session.close();
      await launcher.stop();
    });
  });

  group('sheet', () {
    testWidgets('rises with the game\'s prompt and sends what was typed', (
      tester,
    ) async {
      final asked = ValueNotifier<TextPrompt?>(null);
      final answers = <(TextPrompt, String, TypedAction)>[];
      await showSheet(tester, asked, answers);
      expect(find.byKey(const ValueKey('typing-sheet')), findsNothing);
      asked.value = prompt;
      await tester.pumpAndSettle();
      expect(find.text('Name your save'), findsOneWidget);
      expect(find.text('THE GAME ASKS'), findsOneWidget);
      expect(find.text('Kral'), findsOneWidget);
      expect(find.text('4/8'), findsOneWidget);
      expect(
        find.text('Go'),
        findsOneWidget,
        reason: 'the game\'s Enter label',
      );
      await tester.enterText(
        find.byKey(const ValueKey('typing-field')),
        'Kral Utku',
      );
      await tester.pump();
      expect(find.text('Kral Utk'), findsOneWidget, reason: 'kept to 8');
      expect(find.text('8/8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('typing-send')));
      await tester.pumpAndSettle();
      expect(answers, hasLength(1));
      expect(answers.single.$1.id, 7);
      expect(answers.single.$2, 'Kral Utk');
      expect(answers.single.$3, TypedAction.submit);
    });

    testWidgets(
      'cancel closes the game\'s keyboard; a prompt that ends hides it',
      (tester) async {
        final asked = ValueNotifier<TextPrompt?>(prompt);
        final answers = <(TextPrompt, String, TypedAction)>[];
        await showSheet(tester, asked, answers, strings: Strings.turkish);
        await tester.pumpAndSettle();
        expect(find.text('OYUN SORUYOR'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('typing-cancel')));
        await tester.pumpAndSettle();
        expect(answers.single.$3, TypedAction.cancel);
        asked.value = const TextPrompt(id: 9, maxLength: 0);
        await tester.pumpAndSettle();
        expect(
          find.text('Buraya yaz'),
          findsOneWidget,
          reason: 'no title: a plain one',
        );
        expect(find.byKey(const ValueKey('typing-count')), findsNothing);
        asked.value = null;
        await tester.pumpAndSettle();
        await tester.tap(find.text('pad'), warnIfMissed: false);
        expect(answers, hasLength(1), reason: 'gone without an answer');
      },
    );
  });
}
