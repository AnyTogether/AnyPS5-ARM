@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// Players: the launcher sometimes stalls with fast input. Moving fast through the games must not
/// start disk work for every game passed, nor a full-screen fade per game (AnyPS5 Desktop's
/// fast_input_test does the same for its launcher).
@MainActor
final class FastInputTests: XCTestCase {
    /// The folder walks the model asked for: which, on which thread, how many at once.
    final class Walks: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var folders: [String] = []
        private(set) var mostAtOnce = 0
        private(set) var onMain = 0

        func walk(_ url: URL, taking seconds: Double) -> Int64 {
            lock.withLock {
                folders.append(url.lastPathComponent)
                running += 1
                mostAtOnce = max(mostAtOnce, running)
                if Thread.isMainThread { onMain += 1 }
            }
            Thread.sleep(forTimeInterval: seconds)
            lock.withLock { running -= 1 }
            return 1 << 30
        }

        var count: Int { lock.withLock { folders.count } }
    }

    func model(games: Int, walks: Walks, taking seconds: Double = 0.05) throws -> AppModel {
        let model = try LauncherFixture.model(games: games)
        model.forgetMeasurements()
        model.folderSize = { url in walks.walk(url, taking: seconds) }
        return model
    }

    func wait(_ what: String, timeout: Double = 5, until done: @escaping () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if done() { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let finished = done()
        XCTAssertTrue(finished, what)
    }

    func testRapidMovesWalkOneFolderAtATimeThenTheGameTheSelectionRestsOn() async throws {
        let walks = Walks()
        let model = try model(games: 30, walks: walks)
        for _ in 0..<20 { model.moveSelection(1) }
        let resting = try XCTUnwrap(model.selectedGame)
        await wait("the resting game is measured") { (model.sizes[resting.id] ?? -1) > 0 }
        XCTAssertEqual(walks.count, 2, "the first game passed, then the one the selection rests on: \(walks.folders)")
        XCTAssertEqual(walks.folders.last, resting.titleID)
        XCTAssertEqual(walks.mostAtOnce, 1, "one walk at a time")
        XCTAssertEqual(walks.onMain, 0, "nothing walked on the main thread")
    }

    func testAMeasuredGameIsNotWalkedAgain() async throws {
        let walks = Walks()
        let model = try model(games: 5, walks: walks, taking: 0.001)
        model.moveSelection(1)
        let first = try XCTUnwrap(model.selectedGame)
        await wait("measured") { (model.sizes[first.id] ?? -1) > 0 }
        model.moveSelection(1)
        await wait("the next measured") { (model.sizes[model.selectedGame!.id] ?? -1) > 0 }
        let before = walks.count
        model.moveSelection(-1)
        model.moveSelection(1)
        model.moveSelection(-1)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(walks.count, before)
    }

    func testTheBackdropFadesOnlyToTheGameTheSelectionRestsOn() async throws {
        let model = try LauncherFixture.model(games: 30)
        model.settlesSelection = true
        let start = model.backdropGame?.id
        var shown: Set<String?> = [start]
        for _ in 0..<20 {
            model.moveSelection(1)
            shown.insert(model.backdropGame?.id)
            try await Task.sleep(for: .milliseconds(Int(KeyRepeat.fastInterval * 1000)))
        }
        XCTAssertEqual(shown, [start], "a held direction starts no artwork fade per game passed")
        let resting = model.selectedGame?.id
        await wait("the backdrop follows once the selection rests") { model.backdropGame?.id == resting }
        model.moveSelection(1)
        XCTAssertEqual(model.backdropGame?.id, resting, "a single move changes it after a moment")
        await wait("…a moment") { model.backdropGame?.id == model.selectedGame?.id }
    }

    func testTrophiesAreReadForTheRestingGameNotForEveryGamePassed() async throws {
        let model = try LauncherFixture.model(games: 30)
        model.forgetMeasurements()
        for _ in 0..<20 { model.moveSelection(1) }
        XCTAssertLessThanOrEqual(model.trophiesRead.count, 1, "\(model.trophiesRead.count) games' trophies read while passing")
        let resting = try XCTUnwrap(model.selectedGame)
        await wait("the resting game's trophies are read") { model.trophiesRead.contains(resting.id) }
    }

    /// `ANYPS5_BENCH=1 swift test --filter FastInputTests/testBenchmark`: 25 rapid moves at the
    /// pace of a held arrow (one every 60 ms) over 30 games whose folder walk takes 0.4 s each,
    /// about what a PS5 dump of 30 000 files takes on an SSD.
    func testBenchmarkRapidMoves() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ANYPS5_BENCH"] == "1", "set ANYPS5_BENCH=1")
        let walks = Walks()
        let model = try model(games: 30, walks: walks, taking: 0.4)
        model.settlesSelection = true
        var mainTime: Double = 0
        var backdrops: Set<String?> = [model.backdropGame?.id]
        let moves = 25
        for _ in 0..<moves {
            let start = Date()
            _ = model.handle(.right)
            mainTime += Date().timeIntervalSince(start)
            backdrops.insert(model.backdropGame?.id)
            try await Task.sleep(for: .milliseconds(Int(KeyRepeat.fastInterval * 1000)))
        }
        let stopped = Date()
        let resting = try XCTUnwrap(model.selectedGame)
        await wait("measured", timeout: 60) { (model.sizes[resting.id] ?? -1) > 0 }
        let sized = Date().timeIntervalSince(stopped)
        let walked = walks.count
        try await Task.sleep(for: .milliseconds(500))
        print(String(format: "fast input: %d moves, %.2f ms per move on the main thread; %d folder walks (%d at once at most, %d by 0.5 s later); the resting game's size %.0f ms after the last move; %d trophy reads; %d backdrop fades started while moving",
                     moves, mainTime * 1000 / Double(moves), walked, walks.mostAtOnce, walks.count, sized * 1000, model.trophiesRead.count, backdrops.count - 1))
    }
}
