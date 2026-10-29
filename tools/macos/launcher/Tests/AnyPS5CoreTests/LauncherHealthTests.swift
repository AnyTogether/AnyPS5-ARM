import XCTest
@testable import AnyPS5Core

/// The launcher's own crashes and long stalls, offered as a report at the next start (as AnyPS5
/// Desktop's launcher_health_test checks its own).
final class LauncherHealthTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-health-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func health(pid: Int32, alive: @escaping @Sendable (Int32) -> Bool = { _ in false }) -> LauncherHealth {
        LauncherHealth(folder: folder, version: "0.2.26", pid: pid, alive: alive)
    }

    func testACleanRunReportsNothing() {
        let first = health(pid: 100)
        XCTAssertNil(first.start())
        first.closed()
        XCTAssertNil(health(pid: 101).start())
    }

    func testAMarkerLeftByAProcessThatIsGoneIsACrash() throws {
        let first = health(pid: 100)
        _ = first.start(now: Date(timeIntervalSince1970: 1_000))
        first.writeMarker(started: Date(timeIntervalSince1970: 1_000), alive: Date(timeIntervalSince1970: 1_050), lines: ["20:00:01 Home"], error: nil)
        try Data("Fatal signal SIGSEGV (a bad memory access)\n0 AnyPS5 0x1 main + 4\n".utf8).write(to: first.fatalFile)
        let problem = try XCTUnwrap(health(pid: 200).start())
        XCTAssertEqual(problem.kind, .crash)
        XCTAssertEqual(problem.at, Date(timeIntervalSince1970: 1_050), "last seen alive")
        XCTAssertEqual(problem.lines, ["20:00:01 Home"])
        XCTAssertTrue(problem.error?.contains("SIGSEGV") == true, "the signal the crash handler wrote")
        XCTAssertEqual(problem.platform, "macOS")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fatalFile.path))
        let again = health(pid: 201)
        XCTAssertEqual(again.start(), problem, "kept until sent or put aside")
        again.closed()
        health(pid: 202).forget()
        XCTAssertNil(health(pid: 203).start())
    }

    func testASecondLauncherStillRunningIsNoCrash() {
        _ = health(pid: 100).start()
        XCTAssertNil(health(pid: 200, alive: { $0 == 100 }).start())
        XCTAssertTrue(LauncherHealth.processAlive(getpid()))
        XCTAssertFalse(LauncherHealth.processAlive(0))
    }

    func testTheDetectorReportsFiveSecondsWithoutAPingAndNotASleep() {
        var detector = StallDetector()
        XCTAssertNil(detector.ping(0))
        for time in stride(from: 0.5, through: 4.5, by: 0.5) { XCTAssertFalse(detector.tick(time), "\(time)") }
        XCTAssertTrue(detector.tick(5.0), "5 s without the interface")
        XCTAssertFalse(detector.tick(5.5), "reported once")
        XCTAssertEqual(detector.ping(7.25), 7.25, "the stall's length when it ends")
        // The watchdog's own ticks stopped too: the Mac slept or the process was stopped.
        var asleep = StallDetector()
        _ = asleep.ping(0)
        XCTAssertFalse(asleep.tick(0.5))
        XCTAssertFalse(asleep.tick(60), "a gap in the watchdog's ticks is no stall")
        XCTAssertFalse(asleep.tick(60.5))
    }

    func testTheDetectorRestsWhileTheLauncherIsBehind() {
        var detector = StallDetector()
        _ = detector.ping(0)
        detector.watching = false
        for time in stride(from: 0.5, through: 10, by: 0.5) { XCTAssertFalse(detector.tick(time)) }
        detector.watching = true
        for time in stride(from: 10.5, through: 14.5, by: 0.5) { XCTAssertFalse(detector.tick(time), "\(time)") }
        XCTAssertTrue(detector.tick(15), "5 s after it came to the front without an answer")
    }

    func testTheWatchdogWritesAStallThatNeverEndsThenItsLength() throws {
        let health = health(pid: 100)
        _ = health.start()
        let watch = StallWatch(health: health, started: Date(), limit: 0.3, interval: 0.05)
        watch.ping(watching: true, lines: ["20:00:01 Home"], error: nil)
        let file = health.problemFile
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: file.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let stuck = try JSONDecoder.health.decode(LauncherProblem.self, from: Data(contentsOf: file))
        XCTAssertEqual(stuck.kind, .hang)
        XCTAssertNotEqual(stuck.recovered, true, "written while the interface is still stuck")
        XCTAssertEqual(stuck.lines, ["20:00:01 Home"])
        Thread.sleep(forTimeInterval: 0.2)
        watch.ping(watching: true, lines: nil, error: nil)
        var ended = stuck
        let until = Date().addingTimeInterval(5)
        while ended.recovered != true && Date() < until {
            Thread.sleep(forTimeInterval: 0.02)
            ended = try JSONDecoder.health.decode(LauncherProblem.self, from: Data(contentsOf: file))
        }
        XCTAssertEqual(ended.recovered, true)
        XCTAssertGreaterThanOrEqual(ended.stalledFor ?? 0, 0.3)
        watch.closing()
    }

    func testAFatalSignalIsWrittenWithItsStack() throws {
        let health = health(pid: 100)
        _ = health.start()
        CrashCatcher.install(health: health)
        CrashCatcher.exitInstead = true
        // Swift hides fork(); the child only raises the signal, whose handler allocates nothing.
        typealias Fork = @convention(c) () -> pid_t
        let fork = unsafeBitCast(try XCTUnwrap(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fork")), to: Fork.self)
        let child = fork()
        if child == 0 {
            raise(SIGSEGV)
            _exit(0)
        }
        XCTAssertGreaterThan(child, 0)
        var status: Int32 = 0
        let deadline = Date().addingTimeInterval(10)
        while waitpid(child, &status, WNOHANG) == 0 {
            if Date() > deadline {
                kill(child, SIGKILL)
                return XCTFail("the child did not end")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual((status >> 8) & 0xFF, 70, "the handler ran")
        let written = try String(contentsOf: health.fatalFile, encoding: .utf8)
        XCTAssertTrue(written.hasPrefix("Fatal signal SIGSEGV (a bad memory access)\n"), written)
        XCTAssertGreaterThan(written.components(separatedBy: "\n").count, 3, "with the stack")
    }

    func testTheIssueIsFilledInWithoutAnythingPersonalAndStaysShort() throws {
        let problem = LauncherProblem(kind: .hang, at: Date(timeIntervalSince1970: 1_790_000_000), version: "0.2.26", platform: "macOS", stalledMs: 12_400, recovered: true,
                                      error: "Uncaught exception NSRangeException in /Users/ada/Games/x", lines: (0..<400).map { "20:00:\($0) Home · ada's Mac · \(String(repeating: "x", count: 40))" })
        let system = SystemInfo(model: "Mac15,7", chip: "Apple M3 Pro", memoryGB: 18, macOS: "15.6 (24G84)", displayHz: 120)
        let draft = IssueDraft.launcherProblem(problem, system: system, privacy: ReportPrivacy(home: "/Users/ada", names: ["ada", "ada's Mac"]))
        XCTAssertEqual(draft.title, "Launcher stopped responding (12s)")
        XCTAssertTrue(draft.url.absoluteString.hasPrefix("https://github.com/\(IssueDraft.launcherRepository)/issues/new?template=launcher_crash.yml"))
        XCTAssertLessThanOrEqual(draft.url.absoluteString.count, IssueDraft.maximumLength)
        XCTAssertFalse(draft.url.absoluteString.contains("ada"), "nothing of the user in the link")
        let fields = Dictionary(uniqueKeysWithValues: draft.fields.map { ($0.id, $0.value) })
        XCTAssertTrue(fields["system"]?.contains("Apple M3 Pro") == true)
        XCTAssertEqual(fields["versions"], "Launcher 0.2.26 (macOS)")
        XCTAssertTrue(fields["log"]?.hasSuffix("x") == true, "the newest lines kept")
        XCTAssertTrue(fields["error"]?.contains("NSRangeException") == true)
        let crash = IssueDraft.launcherProblem(LauncherProblem(kind: .crash, at: Date(), version: "0.2.26", platform: "macOS"), system: system, privacy: ReportPrivacy(home: "/Users/ada"))
        XCTAssertEqual(crash.title, "Launcher crash")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: crash.fields.map { ($0.id, $0.value) })["error"], "None caught.")
    }

    func testTheIssueTemplateHasEveryFieldTheLinkFills() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent(".github/ISSUE_TEMPLATE/launcher_crash.yml")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("no .github/ISSUE_TEMPLATE/launcher_crash.yml: run this in AnyPS5-ARM's tools/macos/launcher")
        }
        let template = try String(contentsOf: file, encoding: .utf8)
        let draft = IssueDraft.launcherProblem(LauncherProblem(kind: .crash, at: Date(), version: "1", platform: "macOS"), system: .current(displayHz: nil), privacy: .current())
        for field in draft.fields { XCTAssertTrue(template.contains("id: \(field.id)\n"), "launcher_crash.yml has no field \(field.id)") }
    }
}
