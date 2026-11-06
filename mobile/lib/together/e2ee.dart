import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption of direct messages, protocol v1 (docs/e2ee.md of AnyTogether): the same
/// steps as the web app's noble code, checked against its shared vectors
/// (test/fixtures/e2ee-v1.json). Only package:cryptography does the cryptography: X25519,
/// Ed25519, ChaCha20-Poly1305 (RFC 8439, 12-byte nonce), HKDF-SHA-256 and SHA-256. Nothing here
/// talks to a server or keeps a key; see e2ee_keys.dart and e2ee_devices.dart for that.

const e2eeVersion = 1;
const _tag = 'AnyTogether-E2EE-v1';

final _x25519 = X25519();
final _ed25519 = Ed25519();
final _aead = Chacha20.poly1305Aead();
final _sha256 = Sha256();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _zeroNonce = Uint8List(12);

enum E2eeErrorCode { badEncoding, badDevice, noKey, badMessage, badPayload }

/// Why a device, message or file could not be used. [E2eeErrorCode.noKey]: the message was not
/// sealed for this device (it was sent before the device was added).
class E2eeError implements Exception {
  const E2eeError(this.code);

  final E2eeErrorCode code;

  @override
  String toString() => 'E2eeError(${code.name})';
}

// Encodings

final _base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');

/// Standard base64 with padding; anything else, or another [length] of bytes, is refused.
Uint8List fromBase64(Object? text, [int? length]) {
  if (text is! String ||
      text.length % 4 != 0 ||
      !_base64Pattern.hasMatch(text)) {
    throw const E2eeError(E2eeErrorCode.badEncoding);
  }
  final Uint8List bytes;
  try {
    bytes = base64.decode(text);
  } on FormatException {
    throw const E2eeError(E2eeErrorCode.badEncoding);
  }
  if (length != null && bytes.length != length) {
    throw const E2eeError(E2eeErrorCode.badEncoding);
  }
  return bytes;
}

String toBase64(List<int> bytes) => base64.encode(bytes);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.toBytes();
}

final _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

Future<Uint8List> _hash(List<int> bytes) async =>
    Uint8List.fromList((await _sha256.hash(bytes)).bytes);

bool _isZero(List<int> bytes) => bytes.every((b) => b == 0);

// Devices

/// The first 16 bytes of SHA-256 of the signing key, lowercase hex.
Future<String> deviceIdOf(List<int> signKey) async =>
    _hex((await _hash(signKey)).sublist(0, 16));

/// What one device keeps and never sends: its Ed25519 seed and its X25519 secret, with the public
/// keys and the device ID they give.
class DeviceSecrets {
  DeviceSecrets._(
    this.signSeed,
    this.boxSecret,
    this.signKey,
    this.boxKey,
    this.deviceId,
    this._signPair,
    this._boxPair,
  );

  static Future<DeviceSecrets> fromSeeds(
    List<int> signSeed,
    List<int> boxSecret,
  ) async {
    if (signSeed.length != 32 || boxSecret.length != 32) {
      throw const E2eeError(E2eeErrorCode.badDevice);
    }
    final signPair = await _ed25519.newKeyPairFromSeed(signSeed);
    final boxPair = await _x25519.newKeyPairFromSeed(boxSecret);
    final signKey = Uint8List.fromList(
      (await signPair.extractPublicKey()).bytes,
    );
    return DeviceSecrets._(
      Uint8List.fromList(signSeed),
      Uint8List.fromList(boxSecret),
      signKey,
      Uint8List.fromList((await boxPair.extractPublicKey()).bytes),
      await deviceIdOf(signKey),
      signPair,
      boxPair,
    );
  }

  /// New keys, from the platform's secure random numbers.
  static Future<DeviceSecrets> generate() =>
      fromSeeds(randomBytes(32), randomBytes(32));

  final Uint8List signSeed;
  final Uint8List boxSecret;
  final Uint8List signKey;
  final Uint8List boxKey;
  final String deviceId;
  final SimpleKeyPair _signPair;
  final SimpleKeyPair _boxPair;

  Future<Uint8List> _sign(List<int> message) async => Uint8List.fromList(
    (await _ed25519.sign(message, keyPair: _signPair)).bytes,
  );
}

/// A device as the server lists it: public keys and the device's signature over them; [removedAt]
/// for one signed out or removed (kept to verify its old messages).
class PublicDevice {
  const PublicDevice({
    required this.id,
    required this.signKey,
    required this.boxKey,
    required this.sig,
    this.name = '',
    this.createdAt,
    this.removedAt,
  });

  /// Throws [E2eeError] when a field is missing or not a text.
  factory PublicDevice.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String) throw const E2eeError(E2eeErrorCode.badDevice);
      return value;
    }

    return PublicDevice(
      id: text('id'),
      signKey: text('signKey'),
      boxKey: text('boxKey'),
      sig: text('sig'),
      name: json['name'] is String ? json['name'] as String : '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      removedAt: DateTime.tryParse(json['removedAt'] as String? ?? ''),
    );
  }

  final String id;
  final String signKey;
  final String boxKey;
  final String sig;
  final String name;
  final DateTime? createdAt;
  final DateTime? removedAt;

  PublicDevice copyWith({String? id, String? boxKey, String? sig}) =>
      PublicDevice(
        id: id ?? this.id,
        signKey: signKey,
        boxKey: boxKey ?? this.boxKey,
        sig: sig ?? this.sig,
        name: name,
        createdAt: createdAt,
        removedAt: removedAt,
      );

  /// What PUT /me/e2ee/device takes.
  Map<String, dynamic> registration() => {
    'signKey': signKey,
    'boxKey': boxKey,
    'sig': sig,
    'name': name,
  };
}

Uint8List _deviceStatement(String userId, List<int> boxKey) =>
    _concat([_utf8('$_tag/device\n$userId\n'), boxKey]);

/// This device's public record for [userId], as PUT /me/e2ee/device takes it.
Future<PublicDevice> publicDevice(
  DeviceSecrets device,
  String userId, {
  String name = '',
}) async => PublicDevice(
  id: device.deviceId,
  signKey: toBase64(device.signKey),
  boxKey: toBase64(device.boxKey),
  sig: toBase64(await device._sign(_deviceStatement(userId, device.boxKey))),
  name: name,
);

Future<bool> _verify(List<int> message, List<int> sig, List<int> signKey) =>
    _ed25519.verify(
      message,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(signKey, type: KeyPairType.ed25519),
      ),
    );

/// A listed device belongs to [userId] as far as its keys can tell: its ID is its signing key's,
/// and its signature over its X25519 key and the user ID holds.
Future<bool> verifyDevice(String userId, PublicDevice device) async {
  try {
    final signKey = fromBase64(device.signKey, 32);
    final boxKey = fromBase64(device.boxKey, 32);
    if (await deviceIdOf(signKey) != device.id) return false;
    return await _verify(
      _deviceStatement(userId, boxKey),
      fromBase64(device.sig, 64),
      signKey,
    );
  } on Object {
    return false;
  }
}

// Messages

final _deviceIdPattern = RegExp(r'^[0-9a-f]{32}$');

/// A message's encrypted form, as the API stores and returns it.
class Sealed {
  const Sealed({
    required this.device,
    required this.eph,
    required this.nonce,
    required this.body,
    required this.sig,
    required this.keys,
  });

  /// Checks the shape (not the cryptography): throws [E2eeError] for anything else.
  factory Sealed.fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['v'] != e2eeVersion) {
      throw const E2eeError(E2eeErrorCode.badMessage);
    }
    final device = json['device'];
    final keys = json['keys'];
    if (device is! String ||
        !_deviceIdPattern.hasMatch(device) ||
        keys is! Map<String, dynamic>) {
      throw const E2eeError(E2eeErrorCode.badMessage);
    }
    String text(String key) {
      final value = json[key];
      if (value is! String) throw const E2eeError(E2eeErrorCode.badMessage);
      return value;
    }

    return Sealed(
      device: device,
      eph: text('eph'),
      nonce: text('nonce'),
      body: text('body'),
      sig: text('sig'),
      keys: {
        for (final MapEntry(:key, :value) in keys.entries)
          if (value is String) key: value,
      },
    );
  }

  /// The sending device's ID.
  final String device;

  /// The message's ephemeral X25519 public key.
  final String eph;
  final String nonce;
  final String body;
  final String sig;

  /// The content key, wrapped for each device of both people, by device ID.
  final Map<String, String> keys;

  Map<String, dynamic> toJson() => {
    'v': e2eeVersion,
    'device': device,
    'eph': eph,
    'nonce': nonce,
    'body': body,
    'sig': sig,
    'keys': keys,
  };
}

/// A sealed file's own key, nonce and content type.
class SealedFileKey {
  const SealedFileKey({
    required this.key,
    required this.nonce,
    required this.type,
  });

  final String key;
  final String nonce;
  final String type;

  Map<String, dynamic> toJson() => {'key': key, 'nonce': nonce, 'type': type};
}

/// A photo, clip or voice note in a sealed message: what is needed to open and show it.
class SealedAttachment {
  const SealedAttachment({
    required this.mediaId,
    required this.kind,
    required this.type,
    required this.size,
    required this.key,
    required this.nonce,
    this.width,
    this.height,
    this.durationMs,
    this.poster,
  });

  static const kinds = {'image', 'clip', 'voice'};

  static SealedAttachment fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const E2eeError(E2eeErrorCode.badPayload);
    }
    final mediaId = json['mediaId'];
    final kind = json['kind'];
    final type = json['type'];
    final key = json['key'];
    final nonce = json['nonce'];
    if (mediaId is! String ||
        kind is! String ||
        !kinds.contains(kind) ||
        type is! String ||
        key is! String ||
        nonce is! String) {
      throw const E2eeError(E2eeErrorCode.badPayload);
    }
    int? number(String name) {
      final value = json[name];
      return value is num ? value.toInt() : null;
    }

    final poster = json['poster'];
    SealedFileKey? posterKey;
    if (poster is Map<String, dynamic>) {
      final pk = poster['key'];
      final pn = poster['nonce'];
      final pt = poster['type'];
      if (pk is! String || pn is! String || pt is! String) {
        throw const E2eeError(E2eeErrorCode.badPayload);
      }
      posterKey = SealedFileKey(key: pk, nonce: pn, type: pt);
    }
    return SealedAttachment(
      mediaId: mediaId,
      kind: kind,
      type: type,
      size: number('size') ?? 0,
      key: key,
      nonce: nonce,
      width: number('width'),
      height: number('height'),
      durationMs: number('durationMs'),
      poster: posterKey,
    );
  }

  final String mediaId;

  /// image, clip or voice.
  final String kind;
  final String type;
  final int size;
  final String key;
  final String nonce;
  final int? width;
  final int? height;
  final int? durationMs;
  final SealedFileKey? poster;

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'kind': kind,
    'type': type,
    'size': size,
    'key': key,
    'nonce': nonce,
    'width': ?width,
    'height': ?height,
    'durationMs': ?durationMs,
    if (poster != null) 'poster': poster!.toJson(),
  };
}

/// What a sealed message says: text, an attachment, or both.
class Payload {
  const Payload({this.text, this.attachment});

  final String? text;
  final SealedAttachment? attachment;

  Map<String, dynamic> toJson() => {
    'v': e2eeVersion,
    'text': ?text,
    if (attachment != null) 'attachment': attachment!.toJson(),
  };

  static Payload parse(List<int> plain) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const E2eeError(E2eeErrorCode.badPayload);
    }
    if (json is! Map<String, dynamic> || json['v'] != e2eeVersion) {
      throw const E2eeError(E2eeErrorCode.badPayload);
    }
    final text = json['text'];
    if (text != null && text is! String) {
      throw const E2eeError(E2eeErrorCode.badPayload);
    }
    return Payload(
      text: text as String?,
      attachment: json['attachment'] == null
          ? null
          : SealedAttachment.fromJson(json['attachment']),
    );
  }
}

/// Whose message it is and where: the header every key and the body are bound to.
class MessageContext {
  const MessageContext({
    required this.conversationId,
    required this.messageId,
    required this.senderUserId,
    required this.senderDeviceId,
  });

  final String conversationId;
  final String messageId;
  final String senderUserId;
  final String senderDeviceId;

  Uint8List get header => _utf8(
    '$_tag/msg\n$conversationId\n$messageId\n$senderUserId\n$senderDeviceId',
  );
}

/// Fixed randomness, for the test vectors only.
class SealRandom {
  const SealRandom({
    required this.contentKey,
    required this.nonce,
    required this.ephSecret,
  });

  final List<int> contentKey;
  final List<int> nonce;
  final List<int> ephSecret;
}

class SealResult {
  const SealResult(this.sealed, this.contentKey);

  final Sealed sealed;
  final Uint8List contentKey;
}

/// HKDF over X25519([secret], [peer]), salted with the message's ephemeral key and the
/// recipient's key; an all-zero shared secret (a small-order key) is refused.
Future<SecretKey> _wrapKey(
  SimpleKeyPair secret,
  List<int> peer,
  List<int> eph,
  List<int> recipient,
) async {
  final List<int> shared;
  try {
    shared = await (await _x25519.sharedSecretKey(
      keyPair: secret,
      remotePublicKey: SimplePublicKey(peer, type: KeyPairType.x25519),
    )).extractBytes();
  } on Object {
    throw const E2eeError(E2eeErrorCode.badDevice);
  }
  if (_isZero(shared)) throw const E2eeError(E2eeErrorCode.badDevice);
  return _hkdf.deriveKey(
    secretKey: SecretKey(shared),
    nonce: _concat([eph, recipient]),
    info: _utf8('$_tag/wrap'),
  );
}

Future<Uint8List> _signed(
  List<int> header,
  List<int> eph,
  List<int> nonce,
  List<int> body,
) async => _concat([
  header,
  [0],
  eph,
  nonce,
  await _hash(body),
]);

Future<Uint8List> _encrypt(
  List<int> key,
  List<int> nonce,
  List<int> plain,
  List<int> aad,
) async {
  final box = await _aead.encrypt(
    plain,
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: aad,
  );
  return _concat([box.cipherText, box.mac.bytes]);
}

/// Throws on a wrong key, nonce, aad or a changed byte.
Future<Uint8List> _decrypt(
  List<int> key,
  List<int> nonce,
  List<int> sealed,
  List<int> aad,
) async {
  if (sealed.length < 16) throw const E2eeError(E2eeErrorCode.badMessage);
  final plain = await _aead.decrypt(
    SecretBox(
      sealed.sublist(0, sealed.length - 16),
      nonce: nonce,
      mac: Mac(sealed.sublist(sealed.length - 16)),
    ),
    secretKey: SecretKey(key),
    aad: aad,
  );
  return Uint8List.fromList(plain);
}

/// Encrypts [payload] once and wraps its key for each of [recipients] (the sender's own devices
/// among them). [payloadBytes] overrides the JSON, so the vectors can fix it byte for byte.
Future<SealResult> seal({
  required String conversationId,
  required String messageId,
  required String senderUserId,
  required DeviceSecrets sender,
  required List<PublicDevice> recipients,
  required Payload payload,
  List<int>? payloadBytes,
  SealRandom? random,
}) async {
  final header = MessageContext(
    conversationId: conversationId,
    messageId: messageId,
    senderUserId: senderUserId,
    senderDeviceId: sender.deviceId,
  ).header;
  final contentKey = Uint8List.fromList(random?.contentKey ?? randomBytes(32));
  final nonce = Uint8List.fromList(random?.nonce ?? randomBytes(12));
  final ephPair = await _x25519.newKeyPairFromSeed(
    random?.ephSecret ?? randomBytes(32),
  );
  final eph = (await ephPair.extractPublicKey()).bytes;
  final plain = payloadBytes ?? _utf8(jsonEncode(payload.toJson()));
  final body = await _encrypt(contentKey, nonce, plain, header);
  final keys = <String, String>{};
  for (final recipient in recipients) {
    final boxKey = fromBase64(recipient.boxKey, 32);
    final wrapKey = await _wrapKey(ephPair, boxKey, eph, boxKey);
    keys[recipient.id] = toBase64(
      await _encrypt(
        await wrapKey.extractBytes(),
        _zeroNonce,
        contentKey,
        _concat([header, _utf8('\n${recipient.id}')]),
      ),
    );
  }
  final sig = await sender._sign(await _signed(header, eph, nonce, body));
  return SealResult(
    Sealed(
      device: sender.deviceId,
      eph: toBase64(eph),
      nonce: toBase64(nonce),
      body: toBase64(body),
      sig: toBase64(sig),
      keys: keys,
    ),
    contentKey,
  );
}

/// The content key of a sealed message, unwrapped with this device's key. [E2eeErrorCode.noKey]
/// when the message was not sealed for this device.
Future<Uint8List> unwrapKey(
  Sealed sealed,
  MessageContext context,
  DeviceSecrets me,
) async {
  final wrapped = sealed.keys[me.deviceId];
  if (wrapped == null) throw const E2eeError(E2eeErrorCode.noKey);
  try {
    final eph = fromBase64(sealed.eph, 32);
    final wrapKey = await _wrapKey(me._boxPair, eph, eph, me.boxKey);
    return await _decrypt(
      await wrapKey.extractBytes(),
      _zeroNonce,
      fromBase64(wrapped, 48),
      _concat([context.header, _utf8('\n${me.deviceId}')]),
    );
  } on Object {
    throw const E2eeError(E2eeErrorCode.badMessage);
  }
}

/// Decrypts a sealed message with its content key and checks the author device's signature.
Future<Payload> openWithKey(
  Sealed sealed,
  MessageContext context,
  List<int> contentKey,
  String authorSignKey,
) async {
  final Uint8List plain;
  try {
    if (sealed.device != context.senderDeviceId) throw const FormatException();
    final header = context.header;
    final eph = fromBase64(sealed.eph, 32);
    final nonce = fromBase64(sealed.nonce, 12);
    final body = fromBase64(sealed.body);
    final signKey = fromBase64(authorSignKey, 32);
    if (await deviceIdOf(signKey) != sealed.device) {
      throw const FormatException();
    }
    final good = await _verify(
      await _signed(header, eph, nonce, body),
      fromBase64(sealed.sig, 64),
      signKey,
    );
    if (!good) throw const FormatException();
    plain = await _decrypt(contentKey, nonce, body, header);
  } on Object {
    throw const E2eeError(E2eeErrorCode.badMessage);
  }
  return Payload.parse(plain);
}

/// A sealed message as this device reads it. [authorDevices] are the author's devices, active
/// and removed, each already checked with [verifyDevice].
Future<Payload> open(
  Sealed sealed, {
  required String conversationId,
  required String messageId,
  required String authorId,
  required DeviceSecrets me,
  required List<PublicDevice> authorDevices,
}) async {
  final context = MessageContext(
    conversationId: conversationId,
    messageId: messageId,
    senderUserId: authorId,
    senderDeviceId: sealed.device,
  );
  final contentKey = await unwrapKey(sealed, context, me);
  final author = authorDevices.where((d) => d.id == sealed.device).firstOrNull;
  if (author == null) throw const E2eeError(E2eeErrorCode.badMessage);
  return openWithKey(sealed, context, contentKey, author.signKey);
}

// Attachments

/// What a file is sealed as: the attachment itself, or a clip's poster.
enum FilePart { file, poster }

class SealedFile {
  const SealedFile(this.ciphertext, this.key, this.nonce);

  final Uint8List ciphertext;
  final String key;
  final String nonce;
}

/// A photo, clip, voice note or poster, encrypted with a key of its own before it is uploaded;
/// [key] and [nonce] are fixed for the vectors only.
Future<SealedFile> sealFile(
  List<int> bytes,
  FilePart part, {
  List<int>? key,
  List<int>? nonce,
}) async {
  final k = Uint8List.fromList(key ?? randomBytes(32));
  final n = Uint8List.fromList(nonce ?? randomBytes(12));
  return SealedFile(
    await _encrypt(k, n, bytes, _utf8('$_tag/${part.name}')),
    toBase64(k),
    toBase64(n),
  );
}

Future<Uint8List> openFile(
  List<int> ciphertext,
  FilePart part, {
  required String key,
  required String nonce,
}) async {
  try {
    return await _decrypt(
      fromBase64(key, 32),
      fromBase64(nonce, 12),
      ciphertext,
      _utf8('$_tag/${part.name}'),
    );
  } on Object {
    throw const E2eeError(E2eeErrorCode.badMessage);
  }
}

// Safety number

typedef SafetyPerson = ({String userId, List<String> signKeys});

Future<String> _personDigits(SafetyPerson person) async {
  final hex = [for (final key in person.signKeys) _hex(fromBase64(key, 32))]
    ..sort();
  final digest = await _hash(
    _utf8('$_tag/safety\n${person.userId}\n${hex.join(',')}'),
  );
  final digits = StringBuffer();
  for (var i = 0; i < 30; i += 5) {
    var n = 0;
    for (var j = 0; j < 5; j++) {
      n = n * 256 + digest[i + j];
    }
    digits.write((n % 100000).toString().padLeft(5, '0'));
  }
  return digits.toString();
}

/// The 60 digits both people see, the smaller user ID's half first; null while either person
/// has no device. [SafetyPerson.signKeys] are the active devices' signing keys (base64).
Future<String?> safetyNumber(SafetyPerson a, SafetyPerson b) async {
  if (a.signKeys.isEmpty || b.signKeys.isEmpty) return null;
  final (first, second) = a.userId.compareTo(b.userId) < 0 ? (a, b) : (b, a);
  return '${await _personDigits(first)}${await _personDigits(second)}';
}

/// Twelve groups of five.
List<String> safetyGroups(String digits) => [
  for (var i = 0; i + 5 <= digits.length; i += 5) digits.substring(i, i + 5),
];
