import 'package:anyps5_remote/protocol/messages.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/ui/broadcast_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Mac says whether the game is broadcast', () {
    final on = Message.fromJson('{"type":"broadcast","on":true}');
    expect(on, isA<Broadcasting>());
    expect((on as Broadcasting).on, isTrue);
    expect(
      (Message.fromJson(const Broadcasting(false).toJson()) as Broadcasting).on,
      isFalse,
    );
  });

  test('the phone starts and stops it with commands', () {
    expect(
      const Command('broadcastStart').toJson(),
      '{"type":"command","name":"broadcastStart"}',
    );
  });

  testWidgets('Go Live, then End Broadcast once the Mac is live', (
    tester,
  ) async {
    final broadcasting = ValueNotifier(false);
    final asked = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Texts(
          strings: Strings.turkish,
          child: Scaffold(
            body: BroadcastButton(
              broadcasting: broadcasting,
              onPressed: asked.add,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Yayına Başla'), findsOneWidget);
    await tester.tap(find.byType(BroadcastButton));
    expect(asked, [true]);
    broadcasting.value = true;
    await tester.pump();
    expect(find.text('Yayını Bitir'), findsOneWidget);
    await tester.tap(find.byType(BroadcastButton));
    expect(asked, [true, false]);
  });
}
