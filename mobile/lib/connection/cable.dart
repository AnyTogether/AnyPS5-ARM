import 'dart:async';
import 'dart:io';

/// The Mac's way in over a cable. On an iPhone plugged into the Mac, the launcher opens [port]
/// through the USB link (usbmuxd); each such connection is joined to the next one made to
/// [localPort], so the session connects to [localPort] as it would to the launcher over Wi-Fi.
class CableLink {
  CableLink({
    this.port = defaultPort,
    this.grace = const Duration(seconds: 4),
    required this.onPlugged,
    required this.onUnplugged,
  });

  static const defaultPort = 47702;

  /// The port the Mac connects to, 0 for any (the tests).
  final int port;

  /// How long the Mac may be gone between two connections before the cable counts as unplugged.
  final Duration grace;

  /// The Mac came on the cable: connect to the local port given.
  final void Function(int localPort) onPlugged;

  /// The Mac has been gone for [grace].
  final void Function() onUnplugged;

  ServerSocket? _cable;
  ServerSocket? _local;
  Socket? _waiting;
  Timer? _gone;
  bool _plugged = false;

  /// Where the Mac connects, once started.
  int? get boundPort => _cable?.port;

  /// Where the session connects, once started.
  int? get localPort => _local?.port;

  Future<void> start() async {
    _cable ??= await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );
    _local ??= await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _cable!.listen(_fromMac);
    _local!.listen(_fromSession);
  }

  Future<void> stop() async {
    _gone?.cancel();
    _waiting?.destroy();
    _waiting = null;
    await _cable?.close();
    await _local?.close();
    _cable = null;
    _local = null;
  }

  void _fromMac(Socket mac) {
    _gone?.cancel();
    _waiting?.destroy();
    _waiting = mac;
    _plugged = true;
    onPlugged(_local!.port);
  }

  /// The session's connection takes the Mac's waiting one; with none waiting it is closed, and
  /// the session tries again.
  void _fromSession(Socket local) {
    final mac = _waiting;
    _waiting = null;
    if (mac == null) {
      local.destroy();
      return;
    }
    mac.setOption(SocketOption.tcpNoDelay, true);
    local.setOption(SocketOption.tcpNoDelay, true);
    var ended = false;
    void end() {
      if (ended) return;
      ended = true;
      mac.destroy();
      local.destroy();
      _gone?.cancel();
      _gone = Timer(grace, () {
        if (_waiting != null || !_plugged) return;
        _plugged = false;
        onUnplugged();
      });
    }

    mac.listen(local.add, onDone: end, onError: (_) => end());
    local.listen(mac.add, onDone: end, onError: (_) => end());
  }
}
