import CryptoKit
import XCTest
@testable import AnyPS5Core

/// The last family status the server signed, kept for offline: applied while its signature holds,
/// locked when anyone changed it.
final class FamilyCacheTests: XCTestCase {
    var folder: URL!
    var defaults: UserDefaults!
    var suite: String!
    let server = URL(string: "https://anytogether.test")!
    let key = Curve25519.Signing.PrivateKey()

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("family-\(UUID().uuidString.prefix(8))")
        suite = "family-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    func cache() -> FamilyCache { FamilyCache(folder: folder, defaults: defaults) }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func status(user: String = "u1", restricted: Bool = true, issuedAt: Date) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return ["userId": user, "restricted": restricted, "familyId": restricted ? "f1" : NSNull(), "role": restricted ? "child" : NSNull(),
                "restrictions": restricted ? FamilyRulesTests.restrictions() : NSNull(),
                "today": restricted ? ["date": "2026-10-26", "weekday": "mon", "limitMinutes": NSNull(), "bonusMinutes": 0, "playedSeconds": 0, "from": NSNull(), "until": NSNull(),
                                       "remainingSeconds": NSNull(), "allowed": true, "reason": NSNull()] as [String: Any] : NSNull(),
                "issuedAt": iso.string(from: issuedAt)]
    }

    static func sign(_ family: [String: Any], with key: Curve25519.Signing.PrivateKey, audience: String = "anytogether-family", subject: String? = nil, kid: String = "1") throws -> String {
        let iat = Int((ISO8601DateFormatter().date(from: family["issuedAt"] as! String) ?? Date()).timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "EdDSA", "kid": kid])
        let claims: [String: Any] = ["family": family, "sub": subject ?? family["userId"] as! String, "iss": "https://anytogether.test", "aud": audience, "iat": iat, "exp": iat + 30 * 86_400]
        let payload = try JSONSerialization.data(withJSONObject: claims)
        let input = base64URL(header) + "." + base64URL(payload)
        return input + "." + base64URL(try key.signature(for: Data(input.utf8)))
    }

    var keys: [FamilyKey] { [FamilyKey(kid: "1", x: Self.base64URL(key.publicKey.rawRepresentation))] }

    func testAVerifiedStatusIsKeptForTheNextStart() throws {
        let now = FamilyPolicyTests.noon
        let status = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        XCTAssertTrue(status.restricted)
        guard case .limited(let kept, let stale) = cache().standing(now: now.addingTimeInterval(3600)) else { return XCTFail("not kept") }
        XCTAssertEqual(kept.userId, "u1")
        XCTAssertFalse(stale)
        XCTAssertEqual(kept.effectiveRestrictions?.playTime.timeZone, "Europe/Istanbul")
    }

    func testNothingKeptMeansNoLimits() {
        XCTAssertEqual(cache().standing(now: Date()), .free)
    }

    func testAWrongSignatureIsRefusedAndNothingIsKept() throws {
        let other = Curve25519.Signing.PrivateKey()
        XCTAssertThrowsError(try cache().accept(signed: Self.sign(Self.status(issuedAt: Date()), with: other), keys: keys, server: server, now: Date())) {
            XCTAssertEqual($0 as? FamilyCacheError, .signature)
        }
        XCTAssertThrowsError(try cache().accept(signed: Self.sign(Self.status(issuedAt: Date()), with: key, audience: "anytogether"), keys: keys, server: server, now: Date())) {
            XCTAssertEqual($0 as? FamilyCacheError, .claims, "an access token is not a family status")
        }
        XCTAssertThrowsError(try cache().accept(signed: Self.sign(Self.status(issuedAt: Date()), with: key, subject: "u9"), keys: keys, server: server, now: Date())) {
            XCTAssertEqual($0 as? FamilyCacheError, .claims, "someone else's")
        }
        XCTAssertThrowsError(try cache().accept(signed: "not.a-jws", keys: keys, server: server, now: Date()))
        XCTAssertEqual(cache().standing(now: Date()), .free)
    }

    func testAChangedFileLocks() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        let file = folder.appendingPathComponent("family.json")
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        // The child's own status, as unrestricted, signed with a key of their own.
        let mine = Curve25519.Signing.PrivateKey()
        saved["signed"] = try Self.sign(Self.status(restricted: false, issuedAt: now), with: mine)
        saved["key"] = Self.base64URL(mine.publicKey.rawRepresentation)
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        XCTAssertEqual(cache().standing(now: now), .locked)
    }

    func testAnEditedPayloadLocks() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        let file = folder.appendingPathComponent("family.json")
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let parts = (saved["signed"] as! String).split(separator: ".").map(String.init)
        let payload = Self.base64URL(try JSONSerialization.data(withJSONObject: ["family": Self.status(restricted: false, issuedAt: now), "sub": "u1", "aud": "anytogether-family"]))
        saved["signed"] = [parts[0], payload, parts[2]].joined(separator: ".")
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        XCTAssertEqual(cache().standing(now: now), .locked)
    }

    func testADeletedFileLocksWhereLimitsWere() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        try FileManager.default.removeItem(at: folder)
        XCTAssertEqual(cache().standing(now: now), .locked)
    }

    func testAnOldStatusStillAppliesAndAsksToConnect() throws {
        let then = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: then), with: key), keys: keys, server: server, now: then)
        guard case .limited(_, let week) = cache().standing(now: then.addingTimeInterval(6 * 86_400)) else { return XCTFail() }
        XCTAssertFalse(week)
        guard case .limited(_, let stale) = cache().standing(now: then.addingTimeInterval(40 * 86_400)) else { return XCTFail("past its exp: still applies") }
        XCTAssertTrue(stale)
    }

    func testAParentSigningInClearsTheLimits() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        _ = try cache().accept(signed: Self.sign(Self.status(user: "parent", restricted: false, issuedAt: now.addingTimeInterval(60)), with: key), keys: keys, server: server, now: now)
        XCTAssertEqual(cache().standing(now: now), .free)
    }

    func testAFreshStatusUnlocks() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        try "{}".write(to: folder.appendingPathComponent("family.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(cache().standing(now: now), .locked)
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now.addingTimeInterval(60)), with: key), keys: keys, server: server, now: now)
        guard case .limited = cache().standing(now: now) else { return XCTFail("a fresh one from the same server applies") }
    }

    func testAnotherServerCannotLiftTheLimits() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        let own = Curve25519.Signing.PrivateKey()
        let ownKeys = [FamilyKey(kid: "1", x: Self.base64URL(own.publicKey.rawRepresentation))]
        XCTAssertThrowsError(try cache().accept(signed: Self.sign(Self.status(restricted: false, issuedAt: now), with: own), keys: ownKeys, server: URL(string: "https://my-own.test")!, now: now)) {
            XCTAssertEqual($0 as? FamilyCacheError, .otherServer)
        }
        guard case .limited = cache().standing(now: now) else { return XCTFail("still limited") }
    }

    func testAnOlderStatusDoesNotReplaceANewerOne() throws {
        let now = FamilyPolicyTests.noon
        _ = try cache().accept(signed: Self.sign(Self.status(issuedAt: now), with: key), keys: keys, server: server, now: now)
        XCTAssertThrowsError(try cache().accept(signed: Self.sign(Self.status(restricted: false, issuedAt: now.addingTimeInterval(-3600)), with: key), keys: keys, server: server, now: now)) {
            XCTAssertEqual($0 as? FamilyCacheError, .older)
        }
    }

    func testPlayOnThisMacIsKeptAWhile() throws {
        let now = FamilyPolicyTests.noon
        cache().record(FamilyPlayRecord(id: "a", titleId: "PPSA01234", startedAt: now.addingTimeInterval(-3 * 86_400), endedAt: now.addingTimeInterval(-3 * 86_400 + 60), queued: true), now: now)
        cache().record(FamilyPlayRecord(id: "b", titleId: "PPSA01234", startedAt: now.addingTimeInterval(-600), endedAt: now, queued: false), now: now)
        XCTAssertEqual(cache().records.map(\.id), ["b"], "older than two days is no longer needed")
    }
}
