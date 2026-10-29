@testable import AnyPS5
import AnyPS5Core
import XCTest

/// After the launcher's own crash or a long stall, the next start offers Send Report: one press
/// opens the filled-in issue, and nothing opens before it.
@MainActor
final class LauncherReportTests: XCTestCase {
    var opened: [URL] = []
    var forgotten = 0

    func model() throws -> AppModel {
        let model = try LauncherFixture.model()
        model.openLink = { [weak self] in self?.opened.append($0) }
        return model
    }

    func found(_ model: AppModel, _ problem: LauncherProblem) async {
        model.launcherProblemFound(problem) { [weak self] in self?.forgotten += 1 }
        let end = Date().addingTimeInterval(5)
        while model.launcherReport?.issue == nil && Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(20))
    }

    let crash = LauncherProblem(kind: .crash, at: Date(), version: "0.2.26", platform: "macOS", error: "Fatal signal SIGSEGV (a bad memory access)")

    func testAfterACrashSendReportOpensTheIssueInOneStep() async throws {
        let model = try model()
        await found(model, crash)
        XCTAssertEqual(model.overlay, .launcherReport)
        XCTAssertEqual(model.menuIndex, 0, "Send Report first")
        XCTAssertEqual(model.launcherReport?.headline, "AnyPS5 closed unexpectedly")
        XCTAssertEqual(opened, [], "nothing opens before the user presses it")
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened.first?.absoluteString.contains("template=launcher_crash.yml") == true)
        XCTAssertTrue(opened.first?.absoluteString.contains("SIGSEGV") == true)
        XCTAssertNil(model.overlay)
        XCTAssertEqual(forgotten, 1, "not offered again")
    }

    func testAStallShowsItsLength() async throws {
        let model = try model()
        await found(model, LauncherProblem(kind: .hang, at: Date(), version: "0.2.26", platform: "macOS", stalledMs: 12_300, recovered: true))
        XCTAssertEqual(model.launcherReport?.headline, "AnyPS5 froze for 12 seconds")
        let stuck = try self.model()
        await found(stuck, LauncherProblem(kind: .hang, at: Date(), version: "0.2.26", platform: "macOS", stalledMs: 6_000))
        XCTAssertEqual(stuck.launcherReport?.headline, "AnyPS5 froze and was closed")
    }

    func testNotNowPutsItAsideAndEscJustCloses() async throws {
        let model = try model()
        await found(model, crash)
        XCTAssertTrue(model.handle(.down))
        XCTAssertTrue(model.handle(.select))
        XCTAssertNil(model.overlay)
        XCTAssertEqual(forgotten, 1)
        XCTAssertEqual(opened, [])
        let other = try self.model()
        await found(other, crash)
        XCTAssertTrue(other.handle(.back))
        XCTAssertNil(other.overlay)
        XCTAssertEqual(forgotten, 1, "Esc keeps it for the next start")
        XCTAssertEqual(opened, [])
    }

    func testNothingIsOfferedOverAScreenTheUserOpened() async throws {
        let model = try model()
        model.open(.settings)
        await found(model, crash)
        XCTAssertEqual(model.overlay, .settings)
        model.closeOverlay()
        let end = Date().addingTimeInterval(2)
        while model.overlay == nil && Date() < end { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.overlay, .launcherReport, "once the home screen is free")
        XCTAssertTrue(model.handle(.back))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(model.overlay, "offered once a run")
    }
}
