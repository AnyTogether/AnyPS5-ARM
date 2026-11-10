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

    func testTheHeartbeatCountsOnlyTheTimeBeyondItsOwnBeat() {
        // Issues 91 and 93: an idle launcher read "longest main-thread gap 253-298 ms" every
        // second, which was the 250 ms timer and its 50 ms leeway, not the main thread.
        var heartbeat = Heartbeat(now: 0)
        var said: [Int] = []
        var time: TimeInterval = 0
        for late in [0.003, 0.016, 0.048, 0.016, 0.03, 0.0, 0.016, 0.048] {
            time += Heartbeat.beat + late
            if let stall = heartbeat.ping(time) { said.append(stall) }
        }
        XCTAssertEqual(said, [0, 0], "an idle launcher says 0 ms")
        time += 0.829
        let held = heartbeat.ping(time)
        XCTAssertNil(held, "not a second yet since the last line")
        time += Heartbeat.beat
        XCTAssertEqual(heartbeat.ping(time), 529, "a ping 829 ms after the last: the main thread was held 529 ms beyond the beat and its leeway")
        let line = Heartbeat.line(time: "09:41:15", onScreen: "Home (tiles) · 0 games, #0", stallMs: 529, footprintMB: 412, front: false)
        XCTAssertEqual(line, "09:41:15 Home (tiles) · 0 games, #0 · longest main-thread stall 529 ms · 412 MB · behind")
        XCTAssertGreaterThan(LauncherHealth.footprintMB ?? 0, 0, "this process's own footprint")
    }

    /// An .ips crash report of the launcher as macOS writes it: a JSON header line, then the report.
    func launcherIPS(pid: Int32) -> String {
        let header = #"{"app_name":"AnyPS5","timestamp":"2026-11-09 09:41:30.00 +0530","bundleID":"org.anyps5.launcher","name":"AnyPS5"}"#
        let body: [String: Any] = [
            "pid": pid,
            "procPath": "/Applications/AnyPS5.app/Contents/MacOS/AnyPS5",
            "exception": ["type": "EXC_BREAKPOINT", "signal": "SIGTRAP", "codes": "0x0000000000000001, 0x00000001a2b3c4d5"],
            "termination": ["namespace": "SIGNAL", "code": 5, "indicator": "Trace/BPT trap: 5", "byProc": "exc handler"],
            "asi": ["libswiftCore.dylib": ["Fatal error: Index out of range"]],
            "faultingThread": 0,
            "threads": [["frames": [["imageOffset": 4096, "imageIndex": 0, "symbol": "AppModel.select(_:)", "symbolLocation": 40]]]],
            "usedImages": [["name": "AnyPS5"]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return header + "\n" + String(decoding: data, as: UTF8.self)
    }

    /// A low-memory event in which macOS ended `pid`.
    func jetsamIPS(pid: Int32) -> String {
        let header = #"{"bug_type":"298","timestamp":"2026-11-09 09:41:30.00 +0530"}"#
        let body: [String: Any] = [
            "date": "2026-11-09 09:41:30.12 +0530",
            "memoryStatus": ["pageSize": 16384],
            "processes": [["pid": 77, "name": "Other", "rpages": 100], ["pid": pid, "name": "AnyPS5", "rpages": 204_800, "reason": "per-process-limit"]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return header + "\n" + String(decoding: data, as: UTF8.self)
    }

    func testMacOSsReportOfTheRunIsFoundByItsProcess() throws {
        let reports = folder.appendingPathComponent("DiagnosticReports"), system = folder.appendingPathComponent("System")
        try FileManager.default.createDirectory(at: reports.appendingPathComponent("Retired"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        let since = Date().addingTimeInterval(-60)
        let folders = [reports, reports.appendingPathComponent("Retired")]
        func look(_ pid: Int32) -> String? {
            LauncherHealth.macOSReport(since: since, pid: pid, bundleIdentifier: "org.anyps5.launcher", folders: folders, memoryFolder: system)
        }
        XCTAssertNil(look(4242), "nothing written: nothing to say")
        try launcherIPS(pid: 4242).write(to: reports.appendingPathComponent("Retired/AnyPS5-2026-11-09-094130.ips"), atomically: true, encoding: .utf8)
        let crash = try XCTUnwrap(look(4242), "moved aside to Retired, still found")
        XCTAssertTrue(crash.hasPrefix("macOS crash report ("), crash)
        XCTAssertTrue(crash.components(separatedBy: "\n")[0].hasSuffix("/Retired/AnyPS5-2026-11-09-094130.ips, attach it to the issue):"), crash)
        XCTAssertTrue(crash.contains("Exception: EXC_BREAKPOINT (SIGTRAP), codes 0x0000000000000001, 0x00000001a2b3c4d5"), crash)
        XCTAssertTrue(crash.contains("Termination: SIGNAL 5 Trace/BPT trap: 5 by exc handler"), crash)
        XCTAssertTrue(crash.contains("libswiftCore.dylib: Fatal error: Index out of range"), crash)
        XCTAssertTrue(crash.contains("0  AnyPS5  AppModel.select(_:) + 40"), crash)
        XCTAssertNil(look(5151), "another process's report is not this run's")
        try jetsamIPS(pid: 5151).write(to: system.appendingPathComponent("JetsamEvent-2026-11-09-094130.ips"), atomically: true, encoding: .utf8)
        let memory = try XCTUnwrap(look(5151))
        XCTAssertTrue(memory.contains("macOS ended it for memory at 2026-11-09 09:41:30.12 +0530 (per-process-limit, 3200 MB in use)"), memory)
        XCTAssertNil(look(6161), "a low-memory event that did not end this run says nothing of it")
    }

    func testACrashWithoutMacOSsReportAtStartLooksAgainThenSaysThereIsNone() throws {
        let first = health(pid: 100)
        _ = first.start(now: Date(timeIntervalSince1970: 1_000))
        first.writeMarker(started: Date(timeIntervalSince1970: 1_000), alive: Date(timeIntervalSince1970: 1_050), lines: [], error: nil)
        let problem = try XCTUnwrap(health(pid: 200).start())
        XCTAssertEqual(problem.pid, 100)
        XCTAssertEqual(problem.started, Date(timeIntervalSince1970: 1_000))
        XCTAssertNil(problem.error)
        XCTAssertTrue(LauncherHealth.needsMacOSReport(problem))
        // Written late, after this start: found the second time.
        let late = LauncherHealth(folder: folder, version: "0.2.26", pid: 300, alive: { _ in false }, macOSReport: { since, pid in
            since == Date(timeIntervalSince1970: 1_000) && pid == 100 ? "macOS crash report:\n  Exception: EXC_BAD_ACCESS (SIGSEGV)" : nil
        })
        let found = late.lookAgain(problem)
        XCTAssertTrue(found.error?.hasPrefix("macOS crash report:\n  Exception: EXC_BAD_ACCESS") == true)
        XCTAssertFalse(LauncherHealth.needsMacOSReport(found))
        XCTAssertEqual(late.lookAgain(found), found, "looked for once")
        XCTAssertEqual(health(pid: 301).start(), found, "kept for the next start")
        // Nothing ever written: the report says so.
        let none = health(pid: 400).lookAgain(problem)
        XCTAssertTrue(none.error?.contains("none for this run") == true)
        XCTAssertTrue(none.error?.contains("Force Quit or a kill signal leave none") == true)
        let recovered = LauncherProblem(kind: .hang, at: Date(), version: "0.2.26", platform: "macOS", stalledMs: 6_000, recovered: true, pid: 100, started: Date())
        XCTAssertEqual(health(pid: 401).lookAgain(recovered), recovered, "a stall it came out of ended no run")
    }

    func testAStallTheRunNeverCameOutOfKeepsItsProcess() throws {
        let first = health(pid: 100)
        _ = first.start(now: Date(timeIntervalSince1970: 1_000))
        first.writeStall(since: Date(timeIntervalSince1970: 1_040), length: 8, recovered: false, error: nil, lines: [])
        let problem = try XCTUnwrap(health(pid: 200).start())
        XCTAssertEqual(problem.kind, .hang)
        XCTAssertEqual(problem.pid, 100, "for macOS's report of how it ended (Force Quit leaves none)")
        XCTAssertTrue(LauncherHealth.needsMacOSReport(problem))
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
