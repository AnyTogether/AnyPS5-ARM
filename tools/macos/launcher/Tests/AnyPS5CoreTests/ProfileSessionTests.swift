import Foundation
import Security
import XCTest
@testable import AnyPS5Core

/// Each profile's AnyTogether session in its own Keychain item: one never signs another in or out.
final class ProfileSessionTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString.prefix(8))")
        FakeTogether.requests = []
    }

    override func tearDown() {
        FakeTogether.handler = nil
        try? FileManager.default.removeItem(at: folder)
    }

    func client(_ store: TokenStore) -> TogetherClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        return TogetherClient(base: URL(string: "https://anytogether.test")!, store: store, session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
    }

    static func tokens(_ user: String, access: String) -> [String: Any] {
        ["accessToken": access, "expiresIn": 900, "refreshToken": "refresh-\(user)",
         "user": ["id": user, "handle": user, "displayName": user.capitalized, "avatar": NSNull()]]
    }

    func testTwoProfilesKeepTwoSessions() async throws {
        let vault = MemoryVault()
        let utku = client(TokenStore(vault: vault, account: ProfileSessions.account(for: "p1")))
        let selin = client(TokenStore(vault: vault, account: ProfileSessions.account(for: "p2")))
        FakeTogether.handler = { _, body in
            let email = (try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: String])?["email"] ?? ""
            return (200, Self.tokens(email.hasPrefix("utku") ? "utku" : "selin", access: "access-\(email)"))
        }
        _ = try await utku.verifyEmail("utku@example.com", code: "111111")
        XCTAssertNil(selin.user, "signing one profile in signs no other in")
        _ = try await selin.verifyEmail("selin@example.com", code: "222222")
        XCTAssertEqual(utku.user?.handle, "utku")
        XCTAssertEqual(selin.user?.handle, "selin")

        // Each call goes with its own profile's token.
        FakeTogether.handler = { _, _ in (200, ["account": ["id": "x"], "profile": ["handle": "x", "displayName": "X"]]) }
        _ = try await selin.me()
        XCTAssertEqual(FakeTogether.requests.last?.0.value(forHTTPHeaderField: "Authorization"), "Bearer access-selin@example.com")

        FakeTogether.handler = { _, _ in (204, [:]) }
        await selin.signOut()
        XCTAssertNil(selin.user)
        XCTAssertEqual(utku.user?.handle, "utku", "signing one out keeps the other")
        // A new launch finds the session where it was left.
        XCTAssertEqual(client(TokenStore(vault: vault, account: ProfileSessions.account(for: "p1"))).user?.handle, "utku")
    }

    func testASessionFromBeforeProfilesMovesIntoTheFirstProfilesItem() throws {
        let file = folder.appendingPathComponent("session.json")
        let old = TokenStore(file: file)
        old.save(.init(accessToken: "a", accessExpiry: Date().addingTimeInterval(600), refreshToken: "r", user: TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)))
        let vault = MemoryVault()
        XCTAssertTrue(TokenStore.migrate(file: file, into: vault, account: ProfileSessions.account(for: LauncherProfile.legacyID)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "no copy of the tokens left in the file")
        XCTAssertEqual(TokenStore(vault: vault, account: ProfileSessions.account(for: LauncherProfile.legacyID)).load()?.user.handle, "utku")
        XCTAssertFalse(TokenStore.migrate(file: file, into: vault, account: ProfileSessions.account(for: LauncherProfile.legacyID)), "once")
    }

    func testAFailingVaultKeepsTheFile() throws {
        let file = folder.appendingPathComponent("session.json")
        TokenStore(file: file).save(.init(accessToken: "a", accessExpiry: Date(), refreshToken: "r", user: TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)))
        let vault = MemoryVault()
        vault.refuses = true
        XCTAssertFalse(TokenStore.migrate(file: file, into: vault, account: "x"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the session is not lost")
    }

    func testTheSecretsOfEveryProfileAreKnownToTheCrashReport() {
        let vault = MemoryVault()
        TokenStore(vault: vault, account: "a").save(.init(accessToken: "t1", accessExpiry: Date(), refreshToken: "r1", user: TogetherUser(id: "u", handle: "u", displayName: "U", avatar: nil)))
        TokenStore(vault: vault, account: "b").save(.init(accessToken: "t2", accessExpiry: Date(), refreshToken: "r2", user: TogetherUser(id: "v", handle: "v", displayName: "V", avatar: nil)))
        XCTAssertEqual(Set(ProfileSessions.secrets(in: vault, accounts: ["a", "b"])), ["t1", "r1", "t2", "r2"])
    }

    /// The real Keychain, in a keychain file of the test's own (never the user's login keychain),
    /// with prompts turned off: an item another build of the launcher can still read.
    func testTheKeychainKeepsReplacesAndForgetsASession() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("test.keychain").path
        var keychain: SecKeychain?
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(true) }
        guard SecKeychainCreate(path, 4, "test", false, nil, &keychain) == errSecSuccess, let keychain else { throw XCTSkip("no keychain can be made here") }
        defer { SecKeychainDelete(keychain) }
        let vault = KeychainVault(service: "AnyPS5 test \(UUID().uuidString)", keychain: keychain)
        XCTAssertNil(vault.read("p1"))
        XCTAssertTrue(vault.write(Data("one".utf8), for: "p1"))
        XCTAssertTrue(vault.write(Data("two".utf8), for: "p2"))
        XCTAssertEqual(vault.read("p1"), Data("one".utf8))
        XCTAssertTrue(vault.write(Data("three".utf8), for: "p1"))
        XCTAssertEqual(vault.read("p1"), Data("three".utf8), "replaced, not added twice")
        XCTAssertTrue(vault.write(nil, for: "p1"))
        XCTAssertNil(vault.read("p1"))
        XCTAssertEqual(vault.read("p2"), Data("two".utf8), "the other profile's item stays")
    }
}
