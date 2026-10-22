import 'package:anyps5_remote/connection/device_name.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(deviceChannel, null));

  test('the name the phone gives itself', () async {
    messenger.setMockMethodCallHandler(
      deviceChannel,
      (call) async => call.method == 'name' ? 'Galaxy S25 Ultra' : null,
    );
    expect(await deviceName(fallback: 'Android'), 'Galaxy S25 Ultra');
  });

  test('the platform when the phone gives no name', () async {
    messenger.setMockMethodCallHandler(deviceChannel, (call) async => '  ');
    expect(await deviceName(fallback: 'Android'), 'Android');
  });

  test('the platform when the channel is missing', () async {
    expect(await deviceName(fallback: 'iPhone'), 'iPhone');
  });
}
