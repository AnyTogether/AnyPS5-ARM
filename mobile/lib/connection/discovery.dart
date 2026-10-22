import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

const serviceType = '_anyps5-remote._tcp';

/// AnyPS5 launchers on the local network, as each is resolved: its address (IPv4 when it has
/// one) and its control port.
Stream<(InternetAddress, int, String)> discover() async* {
  final discovery = BonsoirDiscovery(type: serviceType);
  await discovery.initialize();
  final found = StreamController<(InternetAddress, int, String)>();
  final subscription = discovery.eventStream?.listen((event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        event.service.resolve(discovery.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        final addresses = event.service.hostAddresses
            .map(InternetAddress.tryParse)
            .whereType<InternetAddress>()
            .toList();
        if (addresses.isEmpty) return;
        final address = addresses.firstWhere(
          (address) => address.type == InternetAddressType.IPv4,
          orElse: () => addresses.first,
        );
        found.add((address, event.service.port, event.service.name));
      default:
        break;
    }
  });
  await discovery.start();
  try {
    yield* found.stream;
  } finally {
    await subscription?.cancel();
    await discovery.stop();
  }
}
