import 'dart:async';
import 'dart:io';

import 'package:anyps5_remote/connection/cable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Mac on the cable is joined to the local port', () async {
    final plugged = Completer<int>();
    final link = CableLink(
      port: 0,
      onPlugged: plugged.complete,
      onUnplugged: () {},
    );
    await link.start();
    final mac = await Socket.connect(
      InternetAddress.loopbackIPv4,
      link.boundPort!,
    );
    final local = await Socket.connect(
      InternetAddress.loopbackIPv4,
      await plugged.future.timeout(const Duration(seconds: 2)),
    );
    final fromMac = StreamIterator(local);
    final fromPhone = StreamIterator(mac);
    mac.add('to phone'.codeUnits);
    expect(await fromMac.moveNext(), isTrue);
    expect(String.fromCharCodes(fromMac.current), 'to phone');
    local.add('to mac'.codeUnits);
    expect(await fromPhone.moveNext(), isTrue);
    expect(String.fromCharCodes(fromPhone.current), 'to mac');
    mac.destroy();
    local.destroy();
    await link.stop();
  });

  test('unplugged once the Mac is gone for a while', () async {
    final plugged = Completer<int>();
    final unplugged = Completer<void>();
    final link = CableLink(
      port: 0,
      grace: const Duration(milliseconds: 200),
      onPlugged: plugged.complete,
      onUnplugged: unplugged.complete,
    );
    await link.start();
    final mac = await Socket.connect(
      InternetAddress.loopbackIPv4,
      link.boundPort!,
    );
    final local = await Socket.connect(
      InternetAddress.loopbackIPv4,
      await plugged.future,
    );
    mac.destroy();
    await unplugged.future.timeout(const Duration(seconds: 2));
    local.destroy();
    await link.stop();
  });

  test('a local connection with no Mac behind it is closed', () async {
    final link = CableLink(port: 0, onPlugged: (_) {}, onUnplugged: () {});
    await link.start();
    final local = await Socket.connect(
      InternetAddress.loopbackIPv4,
      link.localPort!,
    );
    await local.drain<void>().timeout(const Duration(seconds: 2));
    await link.stop();
  });
}
