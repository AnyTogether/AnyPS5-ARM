// The cryptography is pure Dart: slow in a debug test run on a busy machine.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';

import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/e2ee.dart';
import 'package:anyps5_remote/together/e2ee_devices.dart';
import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:anyps5_remote/together/together_hub.dart';
import 'package:anyps5_remote/ui/messages_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart' show card;
import 'support/scripted_hub.dart';

/// The thread of an end-to-end encrypted conversation on screen: the lock under the name and its
/// sheet, the not-encrypted label, the devices-changed notice, the composer when the other person
/// has no device, messages that do not open, and the report sheet's note.
void main() {
  late DeviceSecrets mine;
  late DeviceSecrets ece;
  late PublicDevice minePublic;
  late PublicDevice ecePublic;
  late Sealed sealed;

  setUpAll(() async {
    mine = await DeviceSecrets.generate();
    ece = await DeviceSecrets.generate();
    minePublic = await publicDevice(mine, 'me', name: 'Pixel 8');
    ecePublic = await publicDevice(ece, 'ece', name: 'Ece Mac');
    sealed = (await seal(
      conversationId: 'c1',
      messageId: '0190a000-0000-7000-8000-000000000002',
      senderUserId: 'ece',
      sender: ece,
      recipients: [minePublic, ecePublic],
      payload: const Payload(text: 'gizli'),
    )).sealed;
  });

  late TogetherHub hub;
  late ScriptedAccount account;

  Map<String, dynamic> direct({bool encrypted = true}) => {
    'id': 'c1',
    'kind': 'direct',
    'title': null,
    'createdBy': 'me',
    'members': [card('me'), card('ece')],
    'lastSeq': 2,
    'readSeq': 2,
    'unread': 0,
    'lastMessage': null,
    'updatedAt': '2026-11-06T12:00:00.000Z',
    'encrypted': encrypted,
  };

  ChatMessage message(
    int seq, {
    String author = 'ece',
    SealState seal = SealState.open,
    String? text = 'gizli',
  }) => ChatMessage(
    id: '0190a000-0000-7000-8000-${seq.toString().padLeft(12, '0')}',
    conversationId: 'c1',
    seq: seq,
    authorId: author,
    text: seal == SealState.open ? text : null,
    createdAt: DateTime.utc(2026, 11, 6, 12, seq),
    sealed: sealed,
    seal: seal,
  );

  setUp(() async {
    (hub, account) = await scriptedHub();
    hub.account.storage = StorageInfo.off;
    account.answer = (method, path, body) => switch ((method, path)) {
      ('POST', 'reports') => <String, dynamic>{},
      _ => null,
    };
  });

  tearDown(() => hub.dispose());

  Future<void> open(
    WidgetTester tester, {
    required List<PublicDevice> theirs,
    bool encrypted = true,
    List<ChatMessage>? thread,
    Map<String, dynamic>? memory,
  }) async {
    tester.view.physicalSize = const Size(2556, 1179);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (memory != null) {
      await hub.account.preferences.setString(
        'together.e2ee.conversations.me',
        jsonEncode({'c1': memory}),
      );
    }
    hub.e2ee.use(mine, {
      'me': UserDevices(active: [minePublic]),
      'ece': UserDevices(active: theirs),
    });
    hub.messages
      ..conversations = [Conversation.fromJson(direct(encrypted: encrypted))]
      ..loaded = true
      ..openId = 'c1'
      ..thread = thread ?? [message(1)];
    await tester.pumpWidget(
      MaterialApp(
        home: Texts(
          strings: Strings.english,
          child: Scaffold(body: MessagesPane(hub: hub)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the lock opens the sheet: the safety number, the mark, the devices',
    (tester) async {
      await open(tester, theirs: [ecePublic]);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      await tester.tap(find.text('End-to-end encrypted'));
      await tester.pumpAndSettle();
      expect(find.text('SAFETY NUMBER'), findsOneWidget);
      final number = await tester.runAsync(
        () => hub.e2ee.safetyNumberOf(hub.messages.chatOf(hub.messages.open)!),
      );
      await tester.pumpAndSettle();
      for (final group in safetyGroups(number!)) {
        expect(find.text(group), findsWidgets);
      }
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Ece Mac'), findsOneWidget);
      expect(
        find.text(
          'A new device cannot read messages sent before it was added.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('We compared them'));
      await tester.pumpAndSettle();
      expect(find.text('Compared'), findsOneWidget);
      expect(find.text('We compared them'), findsNothing);
      expect(hub.messages.lockOf(hub.messages.open).compared, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('someone on an older app: the label says it is not encrypted', (
    tester,
  ) async {
    await open(tester, theirs: [], encrypted: false, thread: []);
    expect(find.text('Not end-to-end encrypted'), findsOneWidget);
    await tester.tap(find.text('Not end-to-end encrypted'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'ECE uses an app that does not support it yet. Messages here work as before.',
      ),
      findsOneWidget,
    );
    expect(find.text('SAFETY NUMBER'), findsNothing);
  });

  testWidgets('encrypted, no device now: the composer says so', (tester) async {
    await open(tester, theirs: []);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text(
        'ECE is not signed in on a device that can read encrypted messages. They need an up-to-date app.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a devices-changed notice until it is dismissed', (tester) async {
    await open(
      tester,
      theirs: [ecePublic],
      memory: {
        'notice': 'theirs',
        'theirs': [ecePublic.id],
        'mine': [minePublic.id],
      },
    );
    expect(
      find.text("ECE's devices changed. Compare the safety number again."),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('devices changed'), findsNothing);
  });

  testWidgets('messages that do not open say why, never the stand-in', (
    tester,
  ) async {
    await open(
      tester,
      theirs: [ecePublic],
      thread: [
        message(1, seal: SealState.noKey),
        message(2, seal: SealState.failed),
        message(3),
      ],
    );
    expect(find.text('Sent before this device was added.'), findsOneWidget);
    expect(find.text('This message could not be decrypted.'), findsOneWidget);
    expect(find.text('gizli'), findsOneWidget);
    expect(find.text('[encrypted message]'), findsNothing);
  });

  testWidgets('reporting a sealed message says the moderators will read it', (
    tester,
  ) async {
    await open(tester, theirs: [ecePublic], thread: [message(2)]);
    await tester.tap(find.byTooltip('Message actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Reporting sends this message to the moderators so they can read it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Spam or ads'));
    for (var i = 0; i < 20 && !account.paths('POST').contains('reports'); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final report = account.calls.lastWhere((c) => c.$2 == 'reports').$3!;
    expect(report['targetKind'], 'message');
    expect(report['reason'], 'spam');
    expect(report['contentKey'], isA<String>());
    expect(find.text('Thanks. A moderator will look at it.'), findsOneWidget);
  });
}
