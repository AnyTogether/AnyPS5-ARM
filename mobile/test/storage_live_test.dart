import 'dart:io';

import 'package:anyps5_remote/together/messages.dart';
import 'package:anyps5_remote/together/profiles.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:anyps5_remote/together/together_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Photos in messages and the storage used, against a real AnyTogether API with storage on.
/// Skipped unless ANYTOGETHER_E2E_URL names the server and ANYTOGETHER_E2E_MAILLOG its log
/// (MAIL_TRANSPORT=log writes the sign-in codes there), and ANYTOGETHER_E2E_PNG a picture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final url = env['ANYTOGETHER_E2E_URL'];

  Future<TogetherAccount> signIn(String name) async {
    final preferences = await SharedPreferences.getInstance();
    final account = TogetherAccount(
      preferences: preferences,
      base: Uri.parse(url!),
      clientName: 'phone-test/1.0',
    );
    final email = '$name-${DateTime.now().microsecondsSinceEpoch}@example.com';
    await account.startEmail(email);
    String? code;
    for (var i = 0; i < 40 && code == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final log = File(env['ANYTOGETHER_E2E_MAILLOG']!).readAsStringSync();
      final line = log
          .split('\n')
          .where((l) => l.contains('sign-in code for $email:'))
          .lastOrNull;
      code = line?.split(': ').last.substring(0, 6);
    }
    await account.verifyEmail(code!);
    return account;
  }

  test(
    'a photo from the phone reaches a friend and counts in the storage',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final ada = await signIn('ada');
      final bob = await signIn('bob');
      expect(await ada.storageEnabled(), isTrue);
      await ada.call('POST', 'me/friends/requests', {
        'handle': bob.user!.handle,
      });
      await bob.call('POST', 'me/friends/requests/${ada.user!.id}/accept', {});
      final conversation = await ada.call('POST', 'conversations', {
        'members': [bob.user!.id],
      });
      final photo = await ada.uploadImage(
        File(env['ANYTOGETHER_E2E_PNG']!).readAsBytesSync(),
      );
      expect(photo.kind, MediaKind.image);
      await ada.call('POST', 'conversations/${conversation['id']}/messages', {
        'clientId': uuidv7(),
        'text': 'look',
        'attachments': [
          {'mediaId': photo.id},
        ],
      });
      final page = await bob.call(
        'GET',
        'conversations/${conversation['id']}/messages?limit=10',
      );
      final seen = ChatMessage.fromJson(
        (page['messages'] as List).last as Map<String, dynamic>,
      );
      expect(seen.kind, MediaKind.image);
      expect(seen.caption, 'look');
      final attachment = seen.attachments.single;
      expect(attachment.shown, isTrue);
      final client = HttpClient();
      final response = await (await client.getUrl(
        Uri.parse(attachment.thumb ?? attachment.url!),
      )).close();
      expect(response.statusCode, 200, reason: 'signed links need no token');
      await response.drain<void>();
      client.close();
      final usage = await ada.storageUsage();
      expect(usage.media, greaterThan(0));
      expect(usage.limit, 100 * 1024 * 1024);
      final me = await ada.call('GET', 'me');
      final privacy = privacyFrom(
        (me['profile'] as Map<String, dynamic>)['privacy'],
      );
      expect(privacy[PrivacySection.gallery], Audience.friends);
    },
    skip: url == null ? 'no ANYTOGETHER_E2E_URL' : false,
  );
}
