import 'dart:io';

import 'package:anyps5_remote/together/together_account.dart';
import 'package:anyps5_remote/ui/storage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

void main() {
  for (final on in [true, false]) {
    testWidgets(
      'settings show the storage used${on ? '' : ': none when off'}',
      (tester) async {
        late FakeServer server;
        late TogetherAccount account;
        await tester.runAsync(() async {
          HttpOverrides.global = null;
          server = FakeServer();
          server.answer = (method, path, body) => switch (path) {
            '/api/v1/storage' => (200, {'enabled': on, 'quota': 104857600}),
            '/api/v1/me/storage' => (
              200,
              {
                'enabled': true,
                'usage': {
                  'used': 3145728,
                  'limit': 104857600,
                  'saves': 2097152,
                  'media': 1048576,
                },
              },
            ),
            _ => (404, {'code': 'not_found', 'status': 404, 'title': 'no'}),
          };
          await server.start();
          account = await server.account();
        });
        // Built in the real zone, so its calls reach the server.
        await tester.runAsync(
          () => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: StorageCard(account: account)),
            ),
          ),
        );
        await tester.runAsync(() async {
          await until(() => server.requests.isNotEmpty);
          await Future<void>.delayed(const Duration(milliseconds: 120));
        });
        await tester.pumpAndSettle();
        if (on) {
          expect(find.text('Cloud storage'), findsOneWidget);
          expect(find.text('3 MB of 100 MB'), findsOneWidget);
          expect(find.text('Saves 2 MB'), findsOneWidget);
          expect(find.text('Photos and clips 1 MB'), findsOneWidget);
        } else {
          expect(find.text('Cloud storage'), findsNothing);
          expect(
            server.requests.where((r) => r.$2 == '/api/v1/me/storage'),
            isEmpty,
          );
        }
        await tester.runAsync(server.stop);
      },
    );
  }
}
