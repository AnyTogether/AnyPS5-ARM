import XCTest
@testable import AnyPS5Core

/// The host kept for the next game, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_host_keeper_test.dart).
@MainActor
final class RetroHostKeeperTests: XCTestCase {
    func testAKeptHostGoesToTheNextGameOfTheSameProgramOnce() {
        let keeper = RetroHostKeeper()
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "/host/anyps5-retro-host")
        XCTAssertTrue(keeper.holding)
        XCTAssertTrue(keeper.keeps(program: "/host/anyps5-retro-host"))
        XCTAssertFalse(keeper.keeps(program: "/other/anyps5-retro-host"))
        XCTAssertTrue(keeper.take(program: "/host/anyps5-retro-host") === session)
        XCTAssertNil(keeper.take(program: "/host/anyps5-retro-host"))
        XCTAssertFalse(session.shutdownAsked)
    }

    func testAHostOfAnotherProgramIsShutDownNotGiven() async {
        let keeper = RetroHostKeeper()
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "/old/anyps5-retro-host")
        XCTAssertNil(keeper.take(program: "/new/anyps5-retro-host"))
        await keeper.shutdown()
        XCTAssertTrue(session.shutdownAsked)
        XCTAssertTrue(session.closed)
    }

    func testASecondHostKeptShutsTheFirstDown() async {
        let keeper = RetroHostKeeper()
        let first = FakeRetroHostSession(), second = FakeRetroHostSession()
        keeper.keep(first, program: "host")
        keeper.keep(second, program: "host")
        await settleRetro({ first.closed })
        XCTAssertTrue(keeper.take(program: "host") === second)
    }

    func testAKeptHostIsShutDownAfterTheIdleLimit() async {
        let keeper = RetroHostKeeper(idleLimit: .milliseconds(10))
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "host")
        await settleRetro({ !keeper.holding })
        await keeper.shutdown()
        XCTAssertTrue(session.shutdownAsked)
        XCTAssertTrue(session.closed)
    }

    func testTakingTheHostStopsItsIdleLimit() async throws {
        let keeper = RetroHostKeeper(idleLimit: .milliseconds(10))
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "host")
        XCTAssertTrue(keeper.take(program: "host") === session)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(session.shutdownAsked)
    }

    func testAKeptHostThatEndsByItselfIsForgottenAndFreed() async {
        let keeper = RetroHostKeeper()
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "host")
        session.end(.hostFailure)
        await settleRetro({ session.closed })
        XCTAssertFalse(keeper.holding)
        XCTAssertFalse(session.shutdownAsked)
        XCTAssertNil(keeper.take(program: "host"))
    }

    func testAHostThatEndsAfterItWasTakenIsTheGamesToFree() async {
        let keeper = RetroHostKeeper()
        let session = FakeRetroHostSession()
        keeper.keep(session, program: "host")
        _ = keeper.take(program: "host")
        session.end(.hostFailure)
        await yieldRetro()
        XCTAssertFalse(session.closed)
    }

    func testShutdownWithNothingKeptDoesNothing() async {
        let keeper = RetroHostKeeper()
        await keeper.shutdown()
        XCTAssertFalse(keeper.holding)
    }
}
