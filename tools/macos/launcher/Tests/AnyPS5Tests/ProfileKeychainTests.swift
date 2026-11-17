@testable import AnyPS5
@testable import AnyPS5Core
import AppKit
import XCTest

/// A profile picked in Who's playing? goes to Home at once, while its session is still being read
/// from the Keychain: after an update macOS asks for the Mac's password before the first read
/// (issue 132, the launcher stopped answering for six seconds). The vault here holds every read
/// until the test answers, as that prompt does.
@MainActor
final class ProfileKeychainTests: XCTestCase {
    /// A vault whose reads wait for `answer()` (at most `limit`), then answer as a MemoryVault.
    final class PromptingVault: SecretVault, @unchecked Sendable {
        private let kept = MemoryVault()
        private let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var answered = false
        private var asked = 0
        let limit: TimeInterval = 3

        var reads: Int { lock.withLock { asked } }

        func answer() {
            lock.withLock { answered = true }
            gate.signal()
        }

        func read(_ account: String) -> Data? {
            let waits = lock.withLock { () -> Bool in
                asked += 1
                return !answered
            }
            if waits {
                _ = gate.wait(timeout: .now() + limit)
                gate.signal()
            }
            return kept.read(account)
        }

        func write(_ data: Data?, for account: String) -> Bool { kept.write(data, for: account) }
    }

    private func model(_ vault: PromptingVault) throws -> (AppModel, LauncherProfile) {
        let model = try LauncherFixture.model(vault: vault) { $0.togetherServer = "https://anytogether.invalid" }
        let mira = model.profiles.add(name: "Mira", mode: .online, account: .init(userId: "u7", handle: "mira"))
        model.profilesChanged()
        model.openProfilePicker(atLaunch: true)
        return (model, mira)
    }

    private func waitFor(_ done: () -> Bool) async throws {
        for _ in 0 ..< 150 where !done() { try await Task.sleep(for: .milliseconds(20)) }
    }

    func testPickingAProfileShowsHomeWhileTheKeychainAsks() async throws {
        let vault = PromptingVault()
        let (model, mira) = try model(vault)
        let picked = Date()
        model.switchProfile(to: mira.id)
        XCTAssertLessThan(Date().timeIntervalSince(picked), 1, "the main thread does not wait for the Keychain")
        XCTAssertNil(model.overlay, "Home at once")
        XCTAssertEqual(model.currentProfile?.id, mira.id)
        XCTAssertFalse(model.profileFlow.atLaunch)
        XCTAssertNil(model.togetherUser, "not online before the session is read")

        // No session kept for it: once the Keychain answers, it signs in again, as before.
        try await waitFor { vault.reads > 0 }
        vault.answer()
        try await waitFor { model.overlay == .signIn }
        XCTAssertEqual(model.overlay, .signIn)
        XCTAssertEqual(model.profileFlow.origin, .signingInAgain)
    }

    func testTheSessionReadGoesOnlineWhenTheKeychainAnswers() async throws {
        let vault = PromptingVault()
        let (model, mira) = try model(vault)
        let user = TogetherUser(id: "u7", handle: "mira", displayName: "Mira", avatar: nil)
        XCTAssertTrue(TokenStore(vault: vault, account: ProfileSessions.account(for: mira.id))
            .save(.init(accessToken: "access", accessExpiry: Date().addingTimeInterval(600), refreshToken: "refresh", user: user)))
        model.switchProfile(to: mira.id)
        XCTAssertNil(model.overlay)
        XCTAssertNil(model.togetherUser)
        vault.answer()
        try await waitFor { model.togetherUser != nil }
        XCTAssertEqual(model.togetherUser?.id, "u7", "online as soon as the session is read")
        XCTAssertNil(model.overlay, "no sign-in for a session that is there")
        model.disconnectTogether()
    }

    func testAnAnswerForAProfileLeftMeanwhileChangesNothing() async throws {
        let vault = PromptingVault()
        let (model, mira) = try model(vault)
        let deniz = model.profiles.add(name: "Deniz", mode: .offline)
        model.profilesChanged()
        model.switchProfile(to: mira.id)
        model.switchProfile(to: deniz.id)
        XCTAssertEqual(model.currentProfile?.id, deniz.id)
        vault.answer()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.overlay, "Mira's missing session does not open a sign-in over Deniz")
        XCTAssertNil(model.togetherUser)
    }

    func testEnteringTheProfileInUseReadsItsSessionOffTheMainThread() async throws {
        let vault = PromptingVault()
        let (model, _) = try model(vault)
        let first = try XCTUnwrap(model.currentProfile)
        model.profiles.setMode(first.id, .online)
        model.profilesChanged()
        let picked = Date()
        model.switchProfile(to: first.id)
        XCTAssertLessThan(Date().timeIntervalSince(picked), 1)
        XCTAssertNil(model.overlay)
        vault.answer()
        try await waitFor { model.overlay == .signIn }
        XCTAssertEqual(model.overlay, .signIn, "no session kept: it signs in again")
    }
}
