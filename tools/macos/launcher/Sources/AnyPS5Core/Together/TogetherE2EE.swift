import CryptoKit
import Foundation

/// End-to-end encryption of direct messages, protocol v1: AnyTogether's docs/e2ee.md, checked
/// byte for byte against its shared vectors (Tests/AnyPS5CoreTests/Fixtures/E2EE). Apple
/// CryptoKit does all of the cryptography: X25519 (Curve25519.KeyAgreement), Ed25519
/// (Curve25519.Signing), ChaCha20-Poly1305 as in RFC 8439 with a 12-byte nonce (ChaChaPoly),
/// HKDF-SHA-256 and SHA-256. Nothing here is hand-rolled; this file only puts the steps together.
/// No UI and no network: TogetherE2EEClient.swift talks to the server, TogetherE2EEState.swift
/// keeps what a thread needs.
public enum TogetherE2EE {
    public static let version = 1
    static let tag = "AnyTogether-E2EE-v1"

    /// Why something could not be read: the same codes as packages/e2ee.
    public enum Failure: Error, Equatable, Sendable {
        case badEncoding, badDevice
        /// The message has no key for this device: it was sent before the device was added.
        case noKey
        /// Changed, moved, signed by someone else or otherwise not what it says.
        case badMessage
        /// Opened and signed, but not a payload of protocol v1.
        case badPayload
    }

    // MARK: Encodings

    /// Standard base64 with padding, of `length` bytes when given; anything else throws.
    public static func base64(_ text: String, length: Int? = nil) throws -> Data {
        guard text.count % 4 == 0, text.utf8.allSatisfy({ Self.base64Alphabet.contains($0) }),
              !text.dropLast(2).contains("="), let data = Data(base64Encoded: text) else { throw Failure.badEncoding }
        if let length, data.count != length { throw Failure.badEncoding }
        return data
    }

    private static let base64Alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".utf8)

    static func hex(_ data: some Sequence<UInt8>) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func utf8(_ text: String) -> Data { Data(text.utf8) }

    // MARK: Devices

    /// What one device keeps and never sends: its Ed25519 seed and its X25519 secret.
    public struct DeviceSecrets: Equatable, Sendable {
        public let signSeed: Data
        public let boxSecret: Data
        public let signKey: Data
        public let boxKey: Data
        public let deviceId: String

        public init(signSeed: Data, boxSecret: Data) throws {
            guard signSeed.count == 32, boxSecret.count == 32,
                  let signer = try? Curve25519.Signing.PrivateKey(rawRepresentation: signSeed),
                  let box = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: boxSecret) else { throw Failure.badDevice }
            self.signSeed = signSeed
            self.boxSecret = boxSecret
            signKey = signer.publicKey.rawRepresentation
            boxKey = box.publicKey.rawRepresentation
            deviceId = TogetherE2EE.deviceId(of: signKey)
        }

        /// New keys from the system's random source.
        public static func generate() -> DeviceSecrets {
            let signer = Curve25519.Signing.PrivateKey()
            let box = Curve25519.KeyAgreement.PrivateKey()
            // Keys CryptoKit just made always load again.
            return try! DeviceSecrets(signSeed: signer.rawRepresentation, boxSecret: box.rawRepresentation)
        }

        func sign(_ data: Data) throws -> Data {
            try Curve25519.Signing.PrivateKey(rawRepresentation: signSeed).signature(for: data)
        }

        /// This device's public record for `userId`, as PUT /me/e2ee/device takes it.
        public func publicDevice(for userId: String) throws -> Device {
            Device(id: deviceId, signKey: signKey.base64EncodedString(), boxKey: boxKey.base64EncodedString(),
                   sig: try sign(TogetherE2EE.deviceStatement(userId, boxKey)).base64EncodedString())
        }
    }

    /// A device as the server lists it (E2eeDeviceView): public keys and the device's signature.
    public struct Device: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var signKey: String
        public var boxKey: String
        public var sig: String
        public var name: String?
        public var createdAt: String?
        /// Set for a removed device: kept to verify its old messages.
        public var removedAt: String?

        public init(id: String, signKey: String, boxKey: String, sig: String, name: String? = nil, createdAt: String? = nil, removedAt: String? = nil) {
            self.id = id
            self.signKey = signKey
            self.boxKey = boxKey
            self.sig = sig
            self.name = name
            self.createdAt = createdAt
            self.removedAt = removedAt
        }

        /// What it is, as device lists show it: never its name (older launchers registered the
        /// computer's own) or its ID.
        public var kind: DeviceKind { TogetherE2EE.deviceKind(of: name ?? "") }

        /// When it was added, from `createdAt`.
        public var added: Date? {
            guard let createdAt else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
        }
    }

    /// What kind of device a device key is on, read from the name its app registered (docs/e2ee.md
    /// in AnyTogether). Lists show this, never the name, which often holds a person's name.
    public enum DeviceKind: String, CaseIterable, Sendable {
        case windows, mac, linux, iphone, ipad, android, browser, device
    }

    /// The same reading as deviceKindOf in AnyTogether's packages/e2ee, so the server's names for
    /// other people's devices ("Windows PC", "iPhone") keep their kind.
    public static func deviceKind(of name: String) -> DeviceKind {
        let n = name.lowercased()
        func has(_ pattern: String) -> Bool { n.range(of: pattern, options: .regularExpression) != nil }
        if has(#"chrome|firefox|safari|\bedge\b|opera|browser"#) { return .browser }
        if has(#"iphone|\bios\b"#) { return .iphone }
        if has("ipad") { return .ipad }
        if has("android|pixel|galaxy|samsung|oneplus|xiaomi|redmi|huawei") { return .android }
        if has(#"\bmac\b|macbook|imac|mac ?mini|mac ?studio|mac ?pro|macos"#) { return .mac }
        if has(#"linux|ubuntu|fedora|debian|\barch\b|steam ?deck|steamos"#) { return .linux }
        if has(#"windows|\bpc\b|^desktop-|^laptop-"#) { return .windows }
        return .device
    }

    /// What this Mac registers as: what it is, never the Mac's own name.
    public static let macDeviceName = "AnyPS5 on Mac"

    /// The first 16 bytes of SHA-256(signKey), lowercase hex.
    public static func deviceId(of signKey: Data) -> String {
        hex(SHA256.hash(data: signKey).prefix(16))
    }

    static func deviceStatement(_ userId: String, _ boxKey: Data) -> Data {
        utf8("\(tag)/device\n\(userId)\n") + boxKey
    }

    /// A listed device belongs to `userId` as far as its keys can tell: its ID is its signing
    /// key's, and its signature over its X25519 key and the user ID holds.
    public static func verify(_ device: Device, for userId: String) -> Bool {
        guard let signKey = try? base64(device.signKey, length: 32), let boxKey = try? base64(device.boxKey, length: 32),
              let sig = try? base64(device.sig, length: 64), deviceId(of: signKey) == device.id,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signKey) else { return false }
        return key.isValidSignature(sig, for: deviceStatement(userId, boxKey))
    }

    // MARK: Messages

    /// A message's encrypted form, as the API takes, stores and returns it.
    public struct Sealed: Codable, Hashable, Sendable {
        public var v: Int
        /// The sending device's ID.
        public var device: String
        /// The message's ephemeral X25519 public key.
        public var eph: String
        public var nonce: String
        public var body: String
        public var sig: String
        /// The content key wrapped for each device of both people, by device ID.
        public var keys: [String: String]

        public init(v: Int, device: String, eph: String, nonce: String, body: String, sig: String, keys: [String: String]) {
            self.v = v
            self.device = device
            self.eph = eph
            self.nonce = nonce
            self.body = body
            self.sig = sig
            self.keys = keys
        }

        /// A seal this launcher cannot read (another version, or not one): it opens as nothing.
        public static let unreadable = Sealed(v: 0, device: "", eph: "", nonce: "", body: "", sig: "", keys: [:])
    }

    /// A photo, clip or voice note's key and what it takes to show it.
    public struct Attachment: Codable, Equatable, Sendable {
        public struct Poster: Codable, Equatable, Sendable {
            public var key: String
            public var nonce: String
            public var type: String
            public init(key: String, nonce: String, type: String) {
                self.key = key
                self.nonce = nonce
                self.type = type
            }
        }

        public var mediaId: String
        /// "image", "clip" or "voice".
        public var kind: String
        /// Its content type ("image/png", "video/mp4").
        public var type: String
        public var size: Int?
        public var key: String
        public var nonce: String
        public var width: Int?
        public var height: Int?
        public var durationMs: Int?
        public var poster: Poster?

        public init(mediaId: String, kind: String, type: String, size: Int?, key: String, nonce: String, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil, poster: Poster? = nil) {
            self.mediaId = mediaId
            self.kind = kind
            self.type = type
            self.size = size
            self.key = key
            self.nonce = nonce
            self.width = width
            self.height = height
            self.durationMs = durationMs
            self.poster = poster
        }

        enum CodingKeys: String, CodingKey { case mediaId, kind, type, size, key, nonce, width, height, durationMs, poster }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mediaId = try c.decode(String.self, forKey: .mediaId)
            kind = try c.decode(String.self, forKey: .kind)
            guard ["image", "clip", "voice"].contains(kind) else { throw Failure.badPayload }
            type = try c.decode(String.self, forKey: .type)
            key = try c.decode(String.self, forKey: .key)
            nonce = try c.decode(String.self, forKey: .nonce)
            // Sizes only help to show it: one that does not read is left out.
            size = try? c.decodeIfPresent(Int.self, forKey: .size)
            width = try? c.decodeIfPresent(Int.self, forKey: .width)
            height = try? c.decodeIfPresent(Int.self, forKey: .height)
            durationMs = try? c.decodeIfPresent(Int.self, forKey: .durationMs)
            poster = try? c.decodeIfPresent(Poster.self, forKey: .poster)
        }
    }

    /// What a sealed message says: `{"v":1,"text":"…"}` and/or an attachment.
    public struct Payload: Codable, Equatable, Sendable {
        public var v: Int
        public var text: String?
        public var attachment: Attachment?

        public init(text: String? = nil, attachment: Attachment? = nil) {
            v = 1
            self.text = text
            self.attachment = attachment
        }

        enum CodingKeys: String, CodingKey { case v, text, attachment }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decode(Int.self, forKey: .v)
            guard v == 1 else { throw Failure.badPayload }
            text = try c.decodeIfPresent(String.self, forKey: .text)
            attachment = try c.decodeIfPresent(Attachment.self, forKey: .attachment)
        }
    }

    /// What the header binds a message to.
    public struct Context: Equatable, Sendable {
        public var conversationId: String
        public var messageId: String
        public var senderUserId: String
        public var senderDeviceId: String

        public init(conversationId: String, messageId: String, senderUserId: String, senderDeviceId: String) {
            self.conversationId = conversationId
            self.messageId = messageId
            self.senderUserId = senderUserId
            self.senderDeviceId = senderDeviceId
        }
    }

    /// A message as the thread knows it: where it is, its ID and who wrote it.
    public struct MessageMeta: Equatable, Sendable {
        public var conversationId: String
        public var messageId: String
        public var authorId: String

        public init(conversationId: String, messageId: String, authorId: String) {
            self.conversationId = conversationId
            self.messageId = messageId
            self.authorId = authorId
        }
    }

    /// A device a message is sealed for.
    public struct Recipient: Equatable, Sendable {
        public var id: String
        public var boxKey: String

        public init(id: String, boxKey: String) {
            self.id = id
            self.boxKey = boxKey
        }

        public init(_ device: Device) {
            self.init(id: device.id, boxKey: device.boxKey)
        }
    }

    /// Fixed randomness, for the test vectors only.
    public struct SealRandom: Sendable {
        public var contentKey: Data
        public var nonce: Data
        public var ephSecret: Data

        public init(contentKey: Data, nonce: Data, ephSecret: Data) {
            self.contentKey = contentKey
            self.nonce = nonce
            self.ephSecret = ephSecret
        }
    }

    static func header(_ c: Context) -> Data {
        utf8("\(tag)/msg\n\(c.conversationId)\n\(c.messageId)\n\(c.senderUserId)\n\(c.senderDeviceId)")
    }

    static func random(_ count: Int) -> Data {
        // SymmetricKey(size:) draws from the system's secure random source.
        SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
    }

    /// X25519, refusing the all-zero result a small-order point gives.
    static func x25519(_ secret: Data, _ peer: Data) throws -> Data {
        guard let mine = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret),
              let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peer),
              let shared = try? mine.sharedSecretFromKeyAgreement(with: theirs) else { throw Failure.badDevice }
        let bytes = shared.withUnsafeBytes { Data($0) }
        guard bytes.count == 32, bytes.contains(where: { $0 != 0 }) else { throw Failure.badDevice }
        return bytes
    }

    /// HKDF-SHA-256 over X25519(secret, peer), salted with the message's ephemeral key and the
    /// recipient's key.
    static func wrapKey(_ secret: Data, _ peer: Data, eph: Data, recipient: Data) throws -> SymmetricKey {
        let shared = try x25519(secret, peer)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: shared), salt: eph + recipient, info: utf8("\(tag)/wrap"), outputByteCount: 32)
    }

    /// ChaCha20-Poly1305 (RFC 8439): ciphertext || tag.
    static func aeadSeal(_ plain: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plain, using: key, nonce: ChaChaPoly.Nonce(data: nonce), authenticating: aad)
        return box.ciphertext + box.tag
    }

    static func aeadOpen(_ sealed: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        guard sealed.count >= 16 else { throw Failure.badMessage }
        let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce), ciphertext: sealed.prefix(sealed.count - 16), tag: sealed.suffix(16))
        return try ChaChaPoly.open(box, using: key, authenticating: aad)
    }

    static let zeroNonce = Data(count: 12)

    static func signed(_ head: Data, eph: Data, nonce: Data, body: Data) -> Data {
        head + Data([0]) + eph + nonce + Data(SHA256.hash(data: body))
    }

    /// Encrypts `payload` once and wraps its key for each recipient device (the sender's own
    /// devices among them).
    public static func seal(_ payload: Payload, conversationId: String, messageId: String, senderUserId: String, sender: DeviceSecrets,
                            recipients: [Recipient]) throws -> (sealed: Sealed, contentKey: Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try seal(payloadBytes: try encoder.encode(payload), conversationId: conversationId, messageId: messageId, senderUserId: senderUserId,
                        sender: sender, recipients: recipients)
    }

    /// The same with the payload's bytes as they are, and fixed randomness for the vectors.
    public static func seal(payloadBytes plain: Data, conversationId: String, messageId: String, senderUserId: String, sender: DeviceSecrets,
                            recipients: [Recipient], random: SealRandom? = nil) throws -> (sealed: Sealed, contentKey: Data) {
        let head = header(Context(conversationId: conversationId, messageId: messageId, senderUserId: senderUserId, senderDeviceId: sender.deviceId))
        let contentKey = random?.contentKey ?? Self.random(32)
        let nonce = random?.nonce ?? Self.random(12)
        let ephemeral = try random.map { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0.ephSecret) } ?? Curve25519.KeyAgreement.PrivateKey()
        let ephSecret = ephemeral.rawRepresentation
        let eph = ephemeral.publicKey.rawRepresentation
        guard contentKey.count == 32, nonce.count == 12 else { throw Failure.badEncoding }
        let body = try aeadSeal(plain, key: SymmetricKey(data: contentKey), nonce: nonce, aad: head)
        var keys: [String: String] = [:]
        for recipient in recipients {
            let boxKey = try base64(recipient.boxKey, length: 32)
            let wrapping = try wrapKey(ephSecret, boxKey, eph: eph, recipient: boxKey)
            keys[recipient.id] = try aeadSeal(contentKey, key: wrapping, nonce: zeroNonce, aad: head + utf8("\n\(recipient.id)")).base64EncodedString()
        }
        let sig = try sender.sign(signed(head, eph: eph, nonce: nonce, body: body))
        let sealed = Sealed(v: version, device: sender.deviceId, eph: eph.base64EncodedString(), nonce: nonce.base64EncodedString(), body: body.base64EncodedString(),
                            sig: sig.base64EncodedString(), keys: keys)
        return (sealed, contentKey)
    }

    /// The content key of a sealed message, unwrapped with this device's key. Throws noKey when
    /// the message was not sealed for this device (it was sent before the device was added).
    public static func unwrapKey(_ sealed: Sealed, _ context: Context, me: DeviceSecrets) throws -> Data {
        guard let wrapped = sealed.keys[me.deviceId] else { throw Failure.noKey }
        do {
            let eph = try base64(sealed.eph, length: 32)
            let wrapping = try wrapKey(me.boxSecret, eph, eph: eph, recipient: me.boxKey)
            return try aeadOpen(try base64(wrapped, length: 48), key: wrapping, nonce: zeroNonce, aad: header(context) + utf8("\n\(me.deviceId)"))
        } catch {
            throw Failure.badMessage
        }
    }

    /// Decrypts a sealed message with its content key and checks the author device's signature
    /// first. A report sends the content key; the server does the same.
    public static func open(_ sealed: Sealed, _ context: Context, contentKey: Data, authorSignKey: String) throws -> Payload {
        let plain: Data
        do {
            guard sealed.v == version, sealed.device == context.senderDeviceId else { throw Failure.badMessage }
            let head = header(context)
            let eph = try base64(sealed.eph, length: 32)
            let nonce = try base64(sealed.nonce, length: 12)
            let body = try base64(sealed.body)
            let signKey = try base64(authorSignKey, length: 32)
            guard deviceId(of: signKey) == sealed.device else { throw Failure.badMessage }
            let key = try Curve25519.Signing.PublicKey(rawRepresentation: signKey)
            guard key.isValidSignature(try base64(sealed.sig, length: 64), for: signed(head, eph: eph, nonce: nonce, body: body)) else { throw Failure.badMessage }
            guard contentKey.count == 32 else { throw Failure.badMessage }
            plain = try aeadOpen(body, key: SymmetricKey(data: contentKey), nonce: nonce, aad: head)
        } catch {
            throw Failure.badMessage
        }
        return try payload(plain)
    }

    /// A sealed message as this device reads it. `authorDevices` are the author's devices, active
    /// and removed, each already checked with `verify`.
    public static func open(_ sealed: Sealed, _ meta: MessageMeta, me: DeviceSecrets, authorDevices: [Device]) throws -> Payload {
        let context = Context(conversationId: meta.conversationId, messageId: meta.messageId, senderUserId: meta.authorId, senderDeviceId: sealed.device)
        let contentKey = try unwrapKey(sealed, context, me: me)
        guard let author = authorDevices.first(where: { $0.id == sealed.device }) else { throw Failure.badMessage }
        return try open(sealed, context, contentKey: contentKey, authorSignKey: author.signKey)
    }

    static func payload(_ plain: Data) throws -> Payload {
        do {
            return try JSONDecoder().decode(Payload.self, from: plain)
        } catch {
            throw Failure.badPayload
        }
    }

    // MARK: Attachments

    /// What an attachment's bytes are sealed as: the file, or a clip's poster.
    public enum FilePart: String, Codable, Sendable {
        case file, poster
    }

    /// A photo, clip, voice note or poster, encrypted with a key of its own before it goes up.
    public static func sealFile(_ bytes: Data, part: FilePart, random: (key: Data, nonce: Data)? = nil) throws -> (ciphertext: Data, key: String, nonce: String) {
        let key = random?.key ?? Self.random(32)
        let nonce = random?.nonce ?? Self.random(12)
        guard key.count == 32, nonce.count == 12 else { throw Failure.badEncoding }
        let ciphertext = try aeadSeal(bytes, key: SymmetricKey(data: key), nonce: nonce, aad: utf8("\(tag)/\(part.rawValue)"))
        return (ciphertext, key.base64EncodedString(), nonce.base64EncodedString())
    }

    public static func openFile(_ ciphertext: Data, part: FilePart, key: String, nonce: String) throws -> Data {
        do {
            return try aeadOpen(ciphertext, key: SymmetricKey(data: try base64(key, length: 32)), nonce: try base64(nonce, length: 12), aad: utf8("\(tag)/\(part.rawValue)"))
        } catch {
            throw Failure.badMessage
        }
    }

    // MARK: Safety number

    static func digits(_ userId: String, _ signKeys: [String]) throws -> String {
        let keys = try signKeys.map { hex(try base64($0, length: 32)) }.sorted()
        let digest = Array(SHA256.hash(data: utf8("\(tag)/safety\n\(userId)\n\(keys.joined(separator: ","))")))
        var out = ""
        for start in stride(from: 0, to: 30, by: 5) {
            let n = digest[start ..< start + 5].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            out += String(format: "%05llu", n % 100_000)
        }
        return out
    }

    /// The 60 digits both people see, the smaller user ID's half first; nil while either has no
    /// device. `signKeys` are each person's active devices' signing keys (base64).
    public static func safetyNumber(_ a: (userId: String, signKeys: [String]), _ b: (userId: String, signKeys: [String])) -> String? {
        guard !a.signKeys.isEmpty, !b.signKeys.isEmpty else { return nil }
        // JavaScript's `<` on strings: UTF-16 code units in order.
        let (first, second) = a.userId.utf16.lexicographicallyPrecedes(b.userId.utf16) ? (a, b) : (b, a)
        guard let one = try? digits(first.userId, first.signKeys), let two = try? digits(second.userId, second.signKeys) else { return nil }
        return one + two
    }

    /// Twelve groups of five.
    public static func safetyGroups(_ digits: String) -> [String] {
        var groups: [String] = []
        var rest = Substring(digits)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(5)))
            rest = rest.dropFirst(5)
        }
        return groups
    }
}
