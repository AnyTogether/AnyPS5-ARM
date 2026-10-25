import CryptoKit
import Foundation
import XCTest
@testable import AnyPS5Core

/// Signed releases: SHA256SUMS signed with Ed25519 by tools/release/sign.sh (OpenSSL), checked
/// with CryptoKit. The fixture was made by sign.sh with throwaway keys; AnyPS5 Desktop's tests
/// check the same fixture.
final class ReleaseSigningTests: XCTestCase {
    static let current = "kROA0TId0RtgYOojGyrCoDWfPv4zC6lbwYEhy4ATi88="
    static let next = "eKk4w/0mBtLssFqKbHTbxDiHjsDzGqWjv7HtyQu8hs4="
    static let stray = "wVmRvxWgPu5CoiT02zTCcKvSai4tFo107xYNRLEMb0w="
    static let app = Data("AnyPS5 0.2.17\n".utf8)
    static let toolkit = Data("toolkit\n".utf8)
    static let sums = Data("""
    8c4f364e8a663e1affcb5020608c70ef48b9582fc3fa123f5c89fcb8888ed4ec  AnyPS5-macOS.zip
    61061033c4741ae85f12fc0ddd9b8a0d19660b551f33d8ef1e098b1ff7b15584  AnyPS5-toolkit-macos-0.2.17-arm.zip

    """.utf8)
    static let byCurrent = "ed25519 c7095b742ad5c7a1 S6W2AwDD9sBnWySE1ThvR3AK7b/iyy5v/5loaR2EyBvpV+AYfKvhFEh1aG34Hg0y/cm9JbGVzmTPIJWNobsaAw=="
    static let byNext = "ed25519 a8e2582b8f333670 9S+4Oviq0bbehR1JXDwU6HZg0U8F3Mr8R99r69O42d08GOgujiHQyk4WjS5xgHEbaaOoULxML56ku9lrRvC0Aw=="
    static let byStray = "ed25519 f91ae443c133eeec fvCHYI/l42E8NgUHU6hau5F7Kk6mBzLiirAPnt2Z1p6Ii3RkM8gGhDyB6wmkgiL3KfiRrQzEcZMrjyUdEjuHBw=="

    static func keys(_ lines: String...) -> [ReleaseSigning.Key] {
        ReleaseSigning.keys(from: lines.enumerated().map { "ed25519 \($0.element) key\($0.offset)" }.joined(separator: "\n"))
    }

    func failure(_ body: () throws -> Any) -> String? {
        do {
            _ = try body()
            return nil
        } catch {
            return "\(error)"
        }
    }

    func testOpenSSLSignatureVerifies() throws {
        let sums = try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byCurrent.utf8), keys: Self.keys(Self.current))
        XCTAssertEqual(sums.signer, "key0")
        XCTAssertEqual(sums.digest(for: "AnyPS5-macOS.zip"), "8c4f364e8a663e1affcb5020608c70ef48b9582fc3fa123f5c89fcb8888ed4ec")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("download.zip")
        try Self.app.write(to: app)
        try sums.check(app, as: "AnyPS5-macOS.zip")
        let toolkit = folder.appendingPathComponent("toolkit.zip")
        try Self.toolkit.write(to: toolkit)
        try sums.check(toolkit, as: "AnyPS5-toolkit-macos-0.2.17-arm.zip")
    }

    func testKeyIDsMatchTheScripts() {
        XCTAssertEqual(Self.keys(Self.current, Self.next, Self.stray).map(\.id), ["c7095b742ad5c7a1", "a8e2582b8f333670", "f91ae443c133eeec"])
    }

    func testRoundTripWithCryptoKit() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sums = Data("\(String(repeating: "ab", count: 32))  AnyPS5-macOS.zip\n".utf8)
        let line = "ed25519 \(ReleaseSigning.keyID(of: key.publicKey.rawRepresentation)) \(try key.signature(for: sums).base64EncodedString())"
        let trusted = Self.keys(key.publicKey.rawRepresentation.base64EncodedString())
        XCTAssertEqual(try ReleaseSigning.verify(sums: sums, signature: Data(line.utf8), keys: trusted).digests, ["AnyPS5-macOS.zip": String(repeating: "ab", count: 32)])
    }

    func testTamperedFileIsRefused() throws {
        let sums = try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byCurrent.utf8), keys: Self.keys(Self.current))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("AnyPS5 0.2.17 with something else\n".utf8).write(to: file)
        XCTAssertEqual(failure { try sums.check(file, as: "AnyPS5-macOS.zip") }, "AnyPS5-macOS.zip does not match the signed release (sha256)")
        try Self.app.write(to: file)
        XCTAssertEqual(failure { try sums.check(file, as: "AnyPS5-macOS-other.zip") }, "the signed release does not list AnyPS5-macOS-other.zip")
    }

    func testTamperedSumsAreRefused() {
        var sums = Self.sums
        sums[0] = UInt8(ascii: "9")
        XCTAssertEqual(failure { try ReleaseSigning.verify(sums: sums, signature: Data(Self.byCurrent.utf8), keys: Self.keys(Self.current)) },
                       "the release's signature does not match its SHA256SUMS")
    }

    func testWrongKeyIsRefused() {
        XCTAssertEqual(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byStray.utf8), keys: Self.keys(Self.current)) },
                       "the release is signed with a key this launcher does not trust (f91ae443c133eeec)")
        // A signature by another key under the trusted key's ID.
        let forged = "ed25519 c7095b742ad5c7a1 " + Self.byStray.split(separator: " ")[2]
        XCTAssertEqual(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data(forged.utf8), keys: Self.keys(Self.current)) },
                       "the release's signature does not match its SHA256SUMS")
    }

    func testMissingSignatureIsRefused() {
        XCTAssertEqual(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data(), keys: Self.keys(Self.current)) },
                       "SHA256SUMS.sig holds no signature")
        XCTAssertEqual(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data("not a signature\n".utf8), keys: Self.keys(Self.current)) },
                       "SHA256SUMS.sig holds no signature")
        XCTAssertNil(ReleaseSigning.assets(in: [["name": "AnyPS5-macOS.zip", "browser_download_url": "https://example.com/a"],
                                                ["name": "SHA256SUMS", "browser_download_url": "https://example.com/s"]]))
        XCTAssertEqual(ReleaseSigning.assets(in: [["name": "SHA256SUMS.sig", "browser_download_url": "https://example.com/g"],
                                                  ["name": "SHA256SUMS", "browser_download_url": "https://example.com/s"]]),
                       ReleaseSigning.Assets(sums: URL(string: "https://example.com/s")!, signature: URL(string: "https://example.com/g")!))
    }

    /// A launcher trusting the current key installs an update signed by it whose key list adds
    /// the next key; the update then trusts releases signed by the next key alone.
    func testRotation() throws {
        let running = Self.keys(Self.current)
        let both = Self.byCurrent + "\n" + Self.byNext + "\n"
        XCTAssertEqual(try ReleaseSigning.verify(sums: Self.sums, signature: Data(both.utf8), keys: running).signer, "key0")
        XCTAssertNotNil(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byNext.utf8), keys: running) })
        let updated = ReleaseSigning.keys(from: "# comment\ned25519 \(Self.current) release-2026-10\ned25519 \(Self.next) next-2026-10\n")
        XCTAssertEqual(updated.map(\.name), ["release-2026-10", "next-2026-10"])
        XCTAssertEqual(try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byNext.utf8), keys: updated).signer, "next-2026-10")
        // Once the old key is retired from the list, its signatures no longer count.
        let retired = Self.keys(Self.next)
        XCTAssertNotNil(failure { try ReleaseSigning.verify(sums: Self.sums, signature: Data(Self.byCurrent.utf8), keys: retired) })
    }

    func testSumsFormat() throws {
        let hash = String(repeating: "0", count: 64)
        XCTAssertEqual(try ReleaseSigning.parseSums(Data("\(hash) *a.zip\r\n\(hash.uppercased())  b.zip\n".utf8)), ["a.zip": hash, "b.zip": hash])
        for bad in ["\(hash)  ../a.zip", "\(hash)  dir/a.zip", "\(hash)  a.zip\n\(hash)  a.zip", "nothex  a.zip", "", "\(hash)a.zip"] {
            XCTAssertNotNil(failure { try ReleaseSigning.parseSums(Data(bad.utf8)) }, bad)
        }
    }

    func testUnsignedReleasesBeforeAndAfterSigningBegan() {
        XCTAssertEqual(ReleaseSigning.trust(release: "0.2.15-arm", signed: false), .unsignedOlder)
        XCTAssertEqual(ReleaseSigning.trust(release: "0.2.16-arm", signed: false), .unsignedOlder)
        XCTAssertEqual(ReleaseSigning.trust(release: "0.2.17-arm", signed: false), .unsignedRefused)
        XCTAssertEqual(ReleaseSigning.trust(release: "0.2.17-arm-nightly.20261025.1", signed: false), .unsignedRefused)
        XCTAssertEqual(ReleaseSigning.trust(release: "0.3", signed: false), .unsignedRefused)
        XCTAssertEqual(ReleaseSigning.trust(release: "nonsense", signed: false), .unsignedRefused)
        XCTAssertEqual(ReleaseSigning.trust(release: "0.2.15-arm", signed: true), .signed)
    }

    /// The keys built in are the ones in tools/release/release-signing.pub (when the launcher
    /// sits in the AnyPS5-ARM tree).
    func testBuiltInKeysMatchTheKeyFile() throws {
        XCTAssertFalse(ReleaseSigning.trustedKeys.isEmpty)
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../release/release-signing.pub").standardized
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { throw XCTSkip("no \(file.path)") }
        XCTAssertEqual(ReleaseSigning.trustedKeys, ReleaseSigning.keys(from: text))
    }
}
