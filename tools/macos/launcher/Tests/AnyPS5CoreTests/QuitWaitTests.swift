import XCTest
@testable import AnyPS5Core

/// A quit waits for what it finishes first (the game closing, leaving a call), never longer than
/// its limits.
@MainActor
final class QuitWaitTests: XCTestCase {
    /// A game the test closes from another task.
    @MainActor
    private final class Closing {
        var gone = false
    }

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

    // MARK: The game playing, as on Windows and Linux (AnyPS5-Desktop's endChildProcesses)

    func testASlowGameGetsItsWholeGraceOnQuit() async throws {
        var asks = 0, ends = 0
        let game = Closing()
        let clock = ContinuousClock()
        let start = clock.now
        let saving = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            game.gone = true
        }
        await QuitWait.closeGame(grace: .milliseconds(600), afterEnd: .milliseconds(100), poll: .milliseconds(10),
                                 ask: { asks += 1 }, gone: { game.gone }, end: { ends += 1 })
        await saving.value
        XCTAssertEqual(asks, 1, "asked to close once")
        XCTAssertEqual(ends, 0, "a game that closes within the grace is never ended")
        XCTAssertGreaterThanOrEqual(clock.now - start, .milliseconds(400), "the quit waited while it saved")
    }

    func testAGameThatIgnoresTheCloseIsEndedAfterTheGrace() async throws {
        var asks = 0, ends = 0, gone = false
        let clock = ContinuousClock()
        let start = clock.now
        var endedAt: Duration?
        await QuitWait.closeGame(grace: .milliseconds(300), afterEnd: .milliseconds(500), poll: .milliseconds(10),
                                 ask: { asks += 1 }, gone: { gone }, end: { ends += 1; endedAt = clock.now - start; gone = true })
        XCTAssertEqual(asks, 1)
        XCTAssertEqual(ends, 1, "ended once")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(endedAt), .milliseconds(300), "not before the grace was over")
        XCTAssertLessThan(clock.now - start, .milliseconds(700), "once ended and gone, the quit goes on")
    }

    func testAGameThatStaysAfterItsEndHoldsTheQuitOnlyAMomentMore() async throws {
        var ends = 0
        let clock = ContinuousClock()
        let start = clock.now
        await QuitWait.closeGame(grace: .milliseconds(100), afterEnd: .milliseconds(200), poll: .milliseconds(10),
                                 ask: {}, gone: { false }, end: { ends += 1 })
        XCTAssertEqual(ends, 1)
        XCTAssertGreaterThanOrEqual(clock.now - start, .milliseconds(300))
    }

    func testTheQuitGoesOnOnceEveryStepIsDone() async throws {
        var replies = 0
        let short = Task<Void, Never> {}
        let longer = Task<Void, Never> { try? await Task.sleep(for: .milliseconds(150)) }
        QuitWait.reply(afterAll: [short, longer], within: .seconds(2)) { replies += 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(replies, 0, "it waits for the longer one too")
        for _ in 0..<100 where replies == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(replies, 1)
    }

    func testAQuitNothingAnswersGoesOnAtTheOverallCapOnce() async throws {
        var replies = 0
        let hanging = Task<Void, Never> {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
        }
        defer { hanging.cancel() }
        QuitWait.reply(afterAll: [Task<Void, Never> {}, hanging], within: .milliseconds(300)) { replies += 1 }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(replies, 0)
        for _ in 0..<100 where replies == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(replies, 1, "the cap lets the quit go on")
        hanging.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(replies, 1, "and only once")
    }

    func testLeavingACallIsBoundedOnItsOwn() async throws {
        let hanging = Task<Void, Never> {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(20)) }
        }
        defer { hanging.cancel() }
        let clock = ContinuousClock()
        let start = clock.now
        await QuitWait.bounded(hanging, within: .milliseconds(200)).value
        XCTAssertGreaterThanOrEqual(clock.now - start, .milliseconds(200))
        XCTAssertLessThan(clock.now - start, .seconds(2))
    }

    func testTheCapIsTwentySecondsAndLongerThanWhatAQuitWaitsFor() {
        XCTAssertEqual(QuitWait.unanswered, .seconds(20), "as AnyPS5-Desktop's LauncherShutdown.defaultUnansweredAfter")
        XCTAssertGreaterThan(QuitWait.unanswered, .seconds(8) + QuitWait.afterEnd, "a game's eight seconds of grace and its end")
        XCTAssertGreaterThan(QuitWait.unanswered, QuitWait.limit)
    }
}
