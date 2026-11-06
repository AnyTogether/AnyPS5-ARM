import CryptoKit
import XCTest
@testable import AnyPS5Core

/// End-to-end encryption, protocol v1, against the shared vectors (Fixtures/E2EE/e2ee-v1.json,
/// copied from AnyTogether's packages/e2ee/test): every device ID, public key, key wrap, body,
/// file and the safety number byte for byte. CryptoKit's Ed25519 signatures are randomised, so
/// signatures are verified rather than compared.
final class TogetherE2EETests: XCTestCase {
    typealias E = TogetherE2EE

    struct Vectors: Decodable {
        struct X: Decodable { let aliceSecretHex, alicePublicHex, bobPublicHex, sharedHex: String }
        struct Ed: Decodable { let seedHex, publicHex, messageHex, signatureHex: String }
        struct Chacha: Decodable { let keyHex, nonceHex, aadHex, plaintext, ciphertextHex, tagHex: String }
        struct RFC: Decodable { let x25519: X; let ed25519: Ed; let chacha20poly1305: Chacha }
        struct Device: Decodable { let userId, signSeed, boxSecret: String; let `public`: E.Device }
        struct Random: Decodable { let contentKey, nonce, ephSecret: String }
        struct Message: Decodable { let name, messageId, authorId, payload: String; let random: Random; let sealed: E.Sealed }
        struct File: Decodable { let part: E.FilePart; let plaintext, key, nonce, ciphertext: String }
        struct Safety: Decodable { let alice, bob: [String]; let digits: String }
        let rfc: RFC
        let users: [String: String]
        let conversationId: String
        let devices: [String: Device]
        let messages: [Message]
        let files: [File]
        let safetyNumber: Safety
    }

    static let vectors: Vectors = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/E2EE/e2ee-v1.json")
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()

    var v: Vectors { Self.vectors }

    static func hex(_ text: String) -> Data {
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            data.append(UInt8(text[index ..< next], radix: 16)!)
            index = next
        }
        return data
    }

    static func hexText(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    func secrets(_ name: String) throws -> E.DeviceSecrets {
        let d = try XCTUnwrap(v.devices[name])
        return try E.DeviceSecrets(signSeed: Self.hex(d.signSeed), boxSecret: Self.hex(d.boxSecret))
    }

    func devices(of user: String) -> [E.Device] {
        v.devices.values.filter { $0.userId == user }.map(\.public)
    }

    func meta(_ m: Vectors.Message) -> E.MessageMeta {
        E.MessageMeta(conversationId: v.conversationId, messageId: m.messageId, authorId: m.authorId)
    }

    // MARK: The RFCs' answers for CryptoKit

    func testCryptoKitGivesTheRFCAnswers() throws {
        let x = v.rfc.x25519
        let alice = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Self.hex(x.aliceSecretHex))
        XCTAssertEqual(Self.hexText(alice.publicKey.rawRepresentation), x.alicePublicHex)
        XCTAssertEqual(Self.hexText(try E.x25519(Self.hex(x.aliceSecretHex), Self.hex(x.bobPublicHex))), x.sharedHex)

        let e = v.rfc.ed25519
        let signer = try Curve25519.Signing.PrivateKey(rawRepresentation: Self.hex(e.seedHex))
        XCTAssertEqual(Self.hexText(signer.publicKey.rawRepresentation), e.publicHex)
        XCTAssertTrue(signer.publicKey.isValidSignature(Self.hex(e.signatureHex), for: Self.hex(e.messageHex)), "RFC 8032's signature verifies")
        let ours = try signer.signature(for: Self.hex(e.messageHex))
        XCTAssertTrue(signer.publicKey.isValidSignature(ours, for: Self.hex(e.messageHex)), "and CryptoKit's own (randomised) one too")

        let c = v.rfc.chacha20poly1305
        let box = try ChaChaPoly.seal(Data(c.plaintext.utf8), using: SymmetricKey(data: Self.hex(c.keyHex)), nonce: ChaChaPoly.Nonce(data: Self.hex(c.nonceHex)),
                                      authenticating: Self.hex(c.aadHex))
        XCTAssertEqual(Self.hexText(box.ciphertext), c.ciphertextHex)
        XCTAssertEqual(Self.hexText(box.tag), c.tagHex)
    }

    func testAnAllZeroSharedSecretIsRefused() throws {
        // A point of small order (here the all-zero public key): X25519 with it gives all zeros.
        let secret = Self.hex(v.rfc.x25519.aliceSecretHex)
        XCTAssertThrowsError(try E.x25519(secret, Data(count: 32)))
        var order8 = Data(count: 32)
        order8[0] = 1
        XCTAssertThrowsError(try E.x25519(secret, order8), "the point 1 has small order too")
    }

    // MARK: Devices

    func testEveryVectorDeviceFromItsSeeds() throws {
        for (name, d) in v.devices {
            let device = try secrets(name)
            XCTAssertEqual(device.deviceId, d.public.id, name)
            XCTAssertEqual(device.signKey.base64EncodedString(), d.public.signKey, name)
            XCTAssertEqual(device.boxKey.base64EncodedString(), d.public.boxKey, name)
            XCTAssertTrue(E.verify(d.public, for: d.userId), "\(name)'s own signature verifies")
            let ours = try device.publicDevice(for: d.userId)
            XCTAssertEqual(ours.id, d.public.id)
            XCTAssertEqual(ours.signKey, d.public.signKey)
            XCTAssertEqual(ours.boxKey, d.public.boxKey)
            XCTAssertTrue(E.verify(ours, for: d.userId), "\(name) signed by CryptoKit verifies")
        }
    }

    func testADeviceVerifiesOnlyForItsUserWithItsOwnKeys() throws {
        let alice = v.users["alice"]!, bob = v.users["bob"]!
        let mac = v.devices["aliceMac"]!.public
        XCTAssertFalse(E.verify(mac, for: bob), "signed for another user")
        XCTAssertFalse(E.verify(mac.with(id: String(repeating: "0", count: 32)), for: alice), "an ID that is not its key's")
        XCTAssertFalse(E.verify(mac.with(boxKey: v.devices["alicePhone"]!.public.boxKey), for: alice), "another X25519 key")
        XCTAssertFalse(E.verify(mac.with(sig: "nope"), for: alice))
        XCTAssertFalse(E.verify(mac.with(sig: v.devices["alicePhone"]!.public.sig), for: alice))
    }

    // MARK: Messages

    func testBothVectorMessagesOpenOnEveryDeviceAndVerify() throws {
        for m in v.messages {
            for name in v.devices.keys {
                let payload = try E.open(m.sealed, meta(m), me: try secrets(name), authorDevices: devices(of: m.authorId))
                XCTAssertEqual(payload, try JSONDecoder().decode(E.Payload.self, from: Data(m.payload.utf8)), "\(m.name) on \(name)")
            }
        }
        let clip = try E.open(v.messages[1].sealed, meta(v.messages[1]), me: try secrets("aliceMac"), authorDevices: devices(of: v.messages[1].authorId))
        XCTAssertEqual(clip.text, "a caption")
        XCTAssertEqual(clip.attachment?.kind, "clip")
        XCTAssertEqual(clip.attachment?.mediaId, "0190f1a2-0000-7000-8000-00000000f11e")
        XCTAssertEqual(clip.attachment?.durationMs, 4200)
        XCTAssertEqual(clip.attachment?.poster?.type, "image/jpeg")
        XCTAssertEqual(try E.open(v.messages[0].sealed, meta(v.messages[0]), me: try secrets("bobDesktop"), authorDevices: devices(of: v.users["alice"]!)).text, "Merhaba Bob 👋 GG?")
    }

    func testResealingWithTheVectorsRandomnessGivesTheSameBytes() throws {
        let senders = ["31a297aa4dd09c0576a7171c1f54a373": "aliceMac", "afa3faabc8b0b2f351a87026d75ebb8f": "bobDesktop"]
        let recipients = v.devices.values.map { E.Recipient(id: $0.public.id, boxKey: $0.public.boxKey) }
        for m in v.messages {
            let sender = try secrets(try XCTUnwrap(senders[m.sealed.device]))
            let random = E.SealRandom(contentKey: Data(base64Encoded: m.random.contentKey)!, nonce: Data(base64Encoded: m.random.nonce)!, ephSecret: Data(base64Encoded: m.random.ephSecret)!)
            let made = try E.seal(payloadBytes: Data(m.payload.utf8), conversationId: v.conversationId, messageId: m.messageId, senderUserId: m.authorId, sender: sender,
                                  recipients: recipients, random: random)
            XCTAssertEqual(made.sealed.v, 1)
            XCTAssertEqual(made.sealed.device, m.sealed.device)
            XCTAssertEqual(made.sealed.eph, m.sealed.eph, m.name)
            XCTAssertEqual(made.sealed.nonce, m.sealed.nonce, m.name)
            XCTAssertEqual(made.sealed.body, m.sealed.body, m.name)
            XCTAssertEqual(made.sealed.keys, m.sealed.keys, m.name)
            XCTAssertEqual(made.contentKey.base64EncodedString(), m.random.contentKey)
            XCTAssertNotEqual(made.sealed.sig, m.sealed.sig, "CryptoKit signs with fresh randomness")
            // Its own signature verifies where the vector's does: open it on another device.
            XCTAssertNoThrow(try E.open(made.sealed, meta(m), me: try secrets("alicePhone"), authorDevices: devices(of: m.authorId)))
        }
    }

    func testBothVectorFilesOpen() throws {
        for f in v.files {
            let plain = try E.openFile(Data(base64Encoded: f.ciphertext)!, part: f.part, key: f.key, nonce: f.nonce)
            XCTAssertEqual(plain.base64EncodedString(), f.plaintext)
            let again = try E.sealFile(Data(base64Encoded: f.plaintext)!, part: f.part, random: (Data(base64Encoded: f.key)!, Data(base64Encoded: f.nonce)!))
            XCTAssertEqual(again.ciphertext.base64EncodedString(), f.ciphertext, "sealed again with the same key and nonce: the same bytes")
            XCTAssertThrowsError(try E.openFile(Data(base64Encoded: f.ciphertext)!, part: f.part == .file ? .poster : .file, key: f.key, nonce: f.nonce), "only as the part it was sealed as")
        }
    }

    func testTheSafetyNumber() throws {
        let s = v.safetyNumber
        let alice = v.users["alice"]!, bob = v.users["bob"]!
        XCTAssertEqual(E.safetyNumber((alice, s.alice), (bob, s.bob)), s.digits)
        XCTAssertEqual(E.safetyNumber((bob, s.bob), (alice, s.alice)), s.digits, "the same on both sides")
        XCTAssertEqual(E.safetyNumber((alice, s.alice.reversed()), (bob, s.bob)), s.digits, "whatever the order of the devices")
        XCTAssertNotEqual(E.safetyNumber((alice, Array(s.alice.prefix(1))), (bob, s.bob)), s.digits, "a device less changes it")
        XCTAssertNil(E.safetyNumber((alice, s.alice), (bob, [])))
        let groups = E.safetyGroups(s.digits)
        XCTAssertEqual(groups.count, 12)
        XCTAssertTrue(groups.allSatisfy { $0.count == 5 })
        XCTAssertEqual(groups.joined(), s.digits)
    }

    // MARK: Tampering

    static func flip(_ base64: String, at index: Int = 0) -> String {
        var bytes = Data(base64Encoded: base64)!
        bytes[index] ^= 1
        return bytes.base64EncodedString()
    }

    func code(_ work: () throws -> Any) -> E.Failure? {
        do {
            _ = try work()
            return nil
        } catch let failure as E.Failure {
            return failure
        } catch {
            XCTFail("not an E2EE failure: \(error)")
            return nil
        }
    }

    func testAnythingChangedOrMovedIsRefused() throws {
        let m = v.messages[0]
        let bob = try secrets("bobDesktop")
        let authors = devices(of: m.authorId)
        let open = { (sealed: E.Sealed, meta: E.MessageMeta) in try E.open(sealed, meta, me: bob, authorDevices: authors) }
        var s = m.sealed
        s.body = Self.flip(m.sealed.body)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "a changed body")
        s = m.sealed
        s.body = Self.flip(m.sealed.body, at: Data(base64Encoded: m.sealed.body)!.count - 1)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "a changed tag")
        s = m.sealed
        s.sig = Self.flip(m.sealed.sig)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "a changed signature")
        s = m.sealed
        s.nonce = Self.flip(m.sealed.nonce)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "a changed nonce")
        s = m.sealed
        s.eph = Self.flip(m.sealed.eph)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "a changed ephemeral key")
        // The header: another conversation, message ID or author.
        XCTAssertEqual(code { try open(m.sealed, E.MessageMeta(conversationId: m.messageId, messageId: m.messageId, authorId: m.authorId)) }, .badMessage)
        XCTAssertEqual(code { try open(m.sealed, E.MessageMeta(conversationId: self.v.conversationId, messageId: self.v.conversationId, authorId: m.authorId)) }, .badMessage)
        XCTAssertEqual(code { try E.open(m.sealed, E.MessageMeta(conversationId: self.v.conversationId, messageId: m.messageId, authorId: self.v.users["bob"]!), me: bob,
                                         authorDevices: self.devices(of: self.v.users["bob"]!)) }, .badMessage, "claimed by the other person")
        // Signed by a device that is not the author's.
        XCTAssertEqual(code { try E.open(m.sealed, self.meta(m), me: bob, authorDevices: self.devices(of: self.v.users["bob"]!)) }, .badMessage)
        s = m.sealed
        s.device = v.devices["alicePhone"]!.public.id
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "said to come from another of the author's devices")
        // A key wrapped for one device does not open for another.
        s = m.sealed
        s.keys[bob.deviceId] = m.sealed.keys[v.devices["alicePhone"]!.public.id]
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage)
        s = m.sealed
        s.keys[bob.deviceId] = Self.flip(m.sealed.keys[bob.deviceId]!)
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage)
        s = m.sealed
        s.v = 2
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage, "another version")
        s = m.sealed
        s.body = "not base64!"
        XCTAssertEqual(code { try open(s, self.meta(m)) }, .badMessage)
    }

    func testADeviceAddedLaterHasNoKey() throws {
        let m = v.messages[0]
        let later = E.DeviceSecrets.generate()
        XCTAssertEqual(code { try E.open(m.sealed, self.meta(m), me: later, authorDevices: self.devices(of: m.authorId)) }, .noKey)
    }

    func testAPayloadThatIsNotOneIsRefused() throws {
        let mac = try secrets("aliceMac"), phone = try secrets("alicePhone")
        let alice = v.users["alice"]!
        let recipients = [mac, phone].map { E.Recipient(id: $0.deviceId, boxKey: $0.boxKey.base64EncodedString()) }
        let authors = devices(of: alice)
        for bad in ["not json", #"{"v":2,"text":"hi"}"#, #"{"v":1,"text":5}"#, #"{"v":1,"attachment":{"mediaId":"m","kind":"gif","type":"image/gif","key":"k","nonce":"n"}}"#, "[1]"] {
            let made = try E.seal(payloadBytes: Data(bad.utf8), conversationId: "c", messageId: "m", senderUserId: alice, sender: mac, recipients: recipients)
            XCTAssertEqual(code { try E.open(made.sealed, E.MessageMeta(conversationId: "c", messageId: "m", authorId: alice), me: phone, authorDevices: authors) }, .badPayload, bad)
        }
    }

    // MARK: Round trip

    func testSealThenOpenOnEveryDeviceOfBothPeople() throws {
        let alice = "0190f1a2-0000-7000-8000-00000000a11c", bob = "0190f1a2-0000-7000-8000-000000000b0b"
        let mac = E.DeviceSecrets.generate(), phone = E.DeviceSecrets.generate(), desktop = E.DeviceSecrets.generate()
        let aliceDevices = try [mac.publicDevice(for: alice), phone.publicDevice(for: alice)]
        let all = aliceDevices + [try desktop.publicDevice(for: bob)]
        let payload = E.Payload(text: "GG 🔥 \"quoted\" / slashes \n new line")
        let made = try E.seal(payload, conversationId: "conv", messageId: "msg", senderUserId: alice, sender: mac, recipients: all.map(E.Recipient.init))
        XCTAssertEqual(Set(made.sealed.keys.keys), Set(all.map(\.id)))
        XCTAssertEqual(made.contentKey.count, 32)
        for device in [mac, phone, desktop] {
            XCTAssertEqual(try E.open(made.sealed, E.MessageMeta(conversationId: "conv", messageId: "msg", authorId: alice), me: device, authorDevices: aliceDevices), payload)
        }
        // As a report does: the content key alone, checked against the author's device.
        let context = E.Context(conversationId: "conv", messageId: "msg", senderUserId: alice, senderDeviceId: mac.deviceId)
        let key = try E.unwrapKey(made.sealed, context, me: desktop)
        XCTAssertEqual(key, made.contentKey)
        XCTAssertEqual(try E.open(made.sealed, context, contentKey: key, authorSignKey: aliceDevices[0].signKey).text, payload.text)
        XCTAssertEqual(code { try E.open(made.sealed, context, contentKey: Data(count: 32), authorSignKey: aliceDevices[0].signKey) }, .badMessage)
        XCTAssertEqual(code { try E.open(made.sealed, context, contentKey: key, authorSignKey: aliceDevices[1].signKey) }, .badMessage)
        // Two seals of the same thing share nothing.
        let again = try E.seal(payload, conversationId: "conv", messageId: "msg", senderUserId: alice, sender: mac, recipients: all.map(E.Recipient.init))
        XCTAssertNotEqual(again.sealed.body, made.sealed.body)
        XCTAssertNotEqual(again.sealed.eph, made.sealed.eph)
        XCTAssertNotEqual(again.contentKey, made.contentKey)
    }

    func testASealedMessageEncodesAsTheAPITakesIt() throws {
        let m = v.messages[0]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(m.sealed)) as? [String: Any]
        XCTAssertEqual(Set(json?.keys ?? [:].keys), ["v", "device", "eph", "nonce", "body", "sig", "keys"])
        XCTAssertEqual(json?["v"] as? Int, 1)
        XCTAssertEqual(json?["keys"] as? [String: String], m.sealed.keys)
    }

    func testBigFilesRoundTrip() throws {
        let bytes = Data((0 ..< 70_000).map { UInt8($0 % 251) })
        let sealed = try E.sealFile(bytes, part: .file)
        XCTAssertEqual(sealed.ciphertext.count, bytes.count + 16)
        XCTAssertEqual(try E.openFile(sealed.ciphertext, part: .file, key: sealed.key, nonce: sealed.nonce), bytes)
        var changed = sealed.ciphertext
        changed[100] ^= 1
        XCTAssertThrowsError(try E.openFile(changed, part: .file, key: sealed.key, nonce: sealed.nonce))
    }

    /// A message sealed here for the other platforms to open (noble, OpenSSL, Dart): alice's Mac
    /// to all three vector devices. With E2EE_INTEROP_OUT set, it is written there as
    /// {"messageId","authorId","conversationId","payload","sealed"}.
    func testAMessageSealedByCryptoKitForTheOtherPlatforms() throws {
        let alice = v.users["alice"]!
        let messageId = "0190f1a2-0000-7000-8000-0000000c4c01"
        let payload = #"{"v":1,"text":"sealed by CryptoKit"}"#
        let made = try E.seal(payloadBytes: Data(payload.utf8), conversationId: v.conversationId, messageId: messageId, senderUserId: alice, sender: try secrets("aliceMac"),
                              recipients: v.devices.values.map { E.Recipient($0.public) })
        let meta = E.MessageMeta(conversationId: v.conversationId, messageId: messageId, authorId: alice)
        for name in v.devices.keys {
            XCTAssertEqual(try E.open(made.sealed, meta, me: try secrets(name), authorDevices: devices(of: alice)).text, "sealed by CryptoKit", name)
        }
        guard let out = ProcessInfo.processInfo.environment["E2EE_INTEROP_OUT"] else { return }
        let sealed = try JSONSerialization.jsonObject(with: JSONEncoder().encode(made.sealed))
        let object: [String: Any] = ["messageId": messageId, "authorId": alice, "conversationId": v.conversationId, "payload": payload, "sealed": sealed]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: out))
    }

    func testStrictBase64() {
        XCTAssertEqual(try E.base64("AAEC", length: 3), Data([0, 1, 2]))
        XCTAssertThrowsError(try E.base64("AAEC", length: 4))
        XCTAssertThrowsError(try E.base64("AAE"))
        XCTAssertThrowsError(try E.base64("AA EC"))
        XCTAssertThrowsError(try E.base64("AA-_"))
    }
}

extension TogetherE2EE.Device {
    func with(id: String? = nil, boxKey: String? = nil, sig: String? = nil) -> Self {
        var copy = self
        if let id { copy.id = id }
        if let boxKey { copy.boxKey = boxKey }
        if let sig { copy.sig = sig }
        return copy
    }
}
