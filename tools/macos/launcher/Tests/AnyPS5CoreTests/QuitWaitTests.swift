import XCTest
@testable import AnyPS5Core

/// A quit waits for what it finishes first (leaving a call), never longer than its limit.
@MainActor
final class QuitWaitTests: XCTestCase {
    func testAQuitGoesOnOnceWhatItWaitsForHasEnded() async throws {
        var replies = 0
        let leaving = Task<Void, Never> {}
        QuitWait.reply(after: leaving, within: .milliseconds(300)) { replies += 1 }
        for _ in 0..<50 where replies == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(replies, 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(replies, 1, "the limit passing later does not reply again")
    }

    func testAQuitGoesOnAtTheLimitWhenWhatItWaitsForHangs() async throws {
        var replies = 0
        let hanging = Task<Void, Never> {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
        }
        defer { hanging.cancel() }
        QuitWait.reply(after: hanging, within: .milliseconds(200)) { replies += 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(replies, 0, "it waits first")
        for _ in 0..<100 where replies == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(replies, 1)
        hanging.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(replies, 1, "the end of what it waited for does not reply again")
    }

    func testTheLimitIsThreeSeconds() {
        XCTAssertEqual(QuitWait.limit, .seconds(3))
    }
}
