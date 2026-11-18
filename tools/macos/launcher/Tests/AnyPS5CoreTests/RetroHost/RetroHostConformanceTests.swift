import Darwin
import XCTest
@testable import AnyPS5Core

/// The launcher's conformance test (anyps5-retro-host docs/protocol.md "Fixtures"), as on Windows and
/// Linux (AnyPS5 Desktop's test/core/retro_host/retro_host_fixtures_test.dart): every session whose
/// `tests` includes `launcher` is played by the host repository's fake host (tests/fake_host.py),
/// which the client starts through its real start path (posix_spawn, descriptor 3) as if it were the
/// host. The test does what the launcher's UI would (the calls, `input`, `shutdown`, `stopGame()`,
/// reading frames and what the client reports) and checks the outcome; the fake checks every message
/// the client sends and writes a report, which must pass.
///
/// ANYPS5_RETRO_HOST_CHECKOUT names a checkout of anyps5-retro-host; without it every test here is
/// skipped. Python 3 must be on PATH. CI fetches the commit its workflow pins.
final class RetroHostConformanceTests: XCTestCase {
    func testBodyDuplicateKey() async throws { try await play("body-duplicate-key") }
    func testBodyLoneSurrogate() async throws { try await play("body-lone-surrogate") }
    func testBodyNotJSON() async throws { try await play("body-not-json") }
    func testBodyNotObject() async throws { try await play("body-not-object") }
    func testBodyNotUTF8() async throws { try await play("body-not-utf8") }
    func testBodyTooShort() async throws { try await play("body-too-short") }
    func testBodyWithoutType() async throws { try await play("body-without-type") }
    func testExitDuringCall() async throws { try await play("exit-during-call") }
    func testFirstMessageNotWelcome() async throws { try await play("first-message-not-welcome") }
    func testFrameBeforeRing() async throws { try await play("frame-before-ring") }
    func testFrameLargerThanSlot() async throws { try await play("frame-larger-than-slot") }
    func testHostUnsupported() async throws { try await play("host-unsupported") }
    func testHungCall() async throws { try await play("hung-call") }
    func testMissedPong() async throws { try await play("missed-pong") }
    func testNoWelcome() async throws { try await play("no-welcome") }
    func testOldEpochFrame() async throws { try await play("old-epoch-frame") }
    func testOlderHostWithoutCore() async throws { try await play("older-host-without-core") }
    func testOversizedFrame() async throws { try await play("oversized-frame") }
    func testOversizedMessage() async throws { try await play("oversized-message") }
    func testPlayAndQuit() async throws { try await play("play-and-quit") }
    func testPongWrongID() async throws { try await play("pong-wrong-id") }
    func testReplyWrongID() async throws { try await play("reply-wrong-id") }
    func testRingBadGeometry() async throws { try await play("ring-bad-geometry") }
    func testRingGrows() async throws { try await play("ring-grows") }
    func testRingNotGrown() async throws { try await play("ring-not-grown") }
    func testRingSizeMismatch() async throws { try await play("ring-size-mismatch") }
    func testRingUnsealed() async throws { try await play("ring-unsealed") }
    func testRingWithoutDescriptor() async throws { try await play("ring-without-descriptor") }
    func testShutdownDeadline() async throws { try await play("shutdown-deadline") }
    func testStopDeadline() async throws { try await play("stop-deadline") }
    func testStrayDescriptor() async throws { try await play("stray-descriptor") }
    func testUnknownFromHost() async throws { try await play("unknown-from-host") }
    func testUnknownValuesFromHost() async throws { try await play("unknown-values-from-host") }
    func testWelcomeNotOffered() async throws { try await play("welcome-not-offered") }
    func testWelcomeWrongPid() async throws { try await play("welcome-wrong-pid") }

    /// Every launcher session at the pinned commit has a test above, so a session the host repository
    /// adds is not silently left out when the pin moves.
    func testEveryLauncherSessionIsPlayed() throws {
        let checkout = try Self.checkout()
        let named = Set(Self.played)
        for name in try Self.sessionNames(checkout) {
            let session = try RetroHostFixtures.read(Self.sessionURL(checkout, name))
            guard session.objectValue?["tests"]?.arrayValue?.contains(.string("launcher")) == true else { continue }
            XCTAssertTrue(named.contains(name), "the launcher session \(name) has no test here")
        }
    }

    // MARK: Sessions of the launcher's own

    func testAReplyWithAWrongResultStillAnswersItsCall() async throws {
        try await playOwn("The host answers pause with true instead of null.", outcome: "protocolError", steps: [
            .object(["from": .string("launcher"), "message": Self.callMessage(2, "pause", .bool(true)), "anyValueFor": .array([.string("id")])]),
            .object(["from": .string("host"), "message": Self.replyMessage(2, .bool(true)), "anyValueFor": .array([.string("id")]),
                     "invalid": .string("pause returns null")]),
        ])
    }

    func testAPs2GameGoesOnlyToAHostThatListsPs2() async throws {
        try await playOwn("A host without ps2 is sent no start.console: the client refuses it before it is sent, and the "
                          + "next call is answered in order.", outcome: "clean", steps: [
                              .object(["from": .string("launcher"), "message": Self.callMessage(2, "status", .null),
                                       "anyValueFor": .array([.string("id")])]),
                              .object(["from": .string("host"), "message": Self.replyMessage(2, .null),
                                       "anyValueFor": .array([.string("id")])]),
                          ], afterReady: { client in
                              XCTAssertFalse(client.canPlayPs2)
                              for console in [RetroConsole.ps2, RetroConsole.ps1] {
                                  do {
                                      _ = try await client.call("start", Self.ps2Start(console: console))
                                      XCTFail("a start with console \(console) went to a host without ps2")
                                  } catch {
                                      XCTAssertEqual(error as? RetroHostClientError, .noPs2Capability)
                                  }
                              }
                          })
    }

    func testAPs2GamesStartAndItsMissingBiosPassTheClientsChecks() async throws {
        let checkout = try Self.checkout()
        func message(_ name: String, _ key: String, id: Int) throws -> RetroJSON {
            let file = try RetroHostFixtures.read(checkout.appendingPathComponent("fixtures/v1/messages/\(name)"))
            guard var map = file.objectValue?[key]?.objectValue else { throw XCTSkip("\(name) has changed") }
            map["id"] = .int(id)
            return .object(map)
        }
        func step(_ from: String, _ message: RetroJSON) -> RetroJSON {
            .object(["from": .string(from), "message": message, "anyValueFor": .array([.string("id")])])
        }
        try await playOwn("A host that lists ps2: start with console ps2, the status LRPS2 gives without a BIOS, "
                          + "then release.", outcome: "clean", steps: [
                              step("launcher", Self.callMessage(2, "start", Self.ps2Start(console: RetroConsole.ps2))),
                              step("host", try message("call-start-ps2.json", "reply", id: 2)),
                              step("launcher", Self.callMessage(3, "status", .null)),
                              step("host", try message("call-status-ps2-no-bios.json", "reply", id: 3)),
                              step("launcher", Self.callMessage(4, "release", .null)),
                              step("host", Self.replyMessage(4, .null)),
                          ], capabilities: [RetroProtocol.ps1Capability, "coreIdentity", "gameTiming", RetroProtocol.ps2Capability],
                          afterReady: { client in
                              XCTAssertTrue(client.canPlayPs2)
                              var withPlaylist = Self.ps2Start(console: RetroConsole.ps2).objectValue ?? [:]
                              withPlaylist["initialDisc"] = .int(0)
                              do {
                                  _ = try await client.call("start", .object(withPlaylist))
                                  XCTFail("a PS2 start with initialDisc was sent")
                              } catch {
                                  XCTAssertEqual(error as? RetroHostClientError, .ps2HasNoPlaylist)
                              }
                          })
    }

    /// A `start` naming `console`, with the session's placeholder paths.
    static func ps2Start(console: String) -> RetroJSON {
        .object(["console": .string(console), "core": .string("${core}"), "disc": .string("${disc}"),
                 "system": .string("${system}"), "saves": .string("${saves}")])
    }

    func testAFrameOfAnotherGameTakesAwayTheFrameShown() async throws {
        let checkout = try Self.checkout()
        try await playOwn("A drawn frame, then a frame of another epoch in the same ring.", outcome: "clean",
                          steps: try Self.startedGame(checkout) + [
                              .object(["launcherDraws": .bool(true)]),
                              .object(["from": .string("host"), "message": .object(["type": .string("frame")]),
                                       "publish": .object(["latest": .int(1), "slot": .object([
                                           "width": .int(320), "height": .int(240), "visible": .int(1), "epoch": .int(7),
                                           "sequence": .int(2),
                                       ])])]),
                              .object(["launcherDraws": .bool(false)]),
                              .object(["from": .string("launcher"), "message": .object(["type": .string("shutdown")])]),
                              .object(["hostExits": .int(0)]),
                          ])
    }

    func testStartAfterAHostFailureThrowsHostGoneAndKeepsTheFailedGameReported() async throws {
        let checkout = try Self.checkout()
        try await playOwn("A game runs, then the host exits unasked.", outcome: "hostFailure",
                          steps: Array(try Self.startedGame(checkout).prefix(2)) + [.object(["hostExits": .int(1)])]) { player in
            do {
                _ = try await player.client.startGame(.object([:]))
                XCTFail("start after a host failure did not throw")
            } catch {
                XCTAssertTrue(error is RetroHostGone, "\(error)")
            }
            let status = try await player.client.status()
            XCTAssertEqual(status?.ended, true)
            XCTAssertEqual(status?.errorCode, RetroErrorCode.hostExited)
            let changed = try await player.client.call("changeDisc", .int(1))
            XCTAssertEqual(changed, .bool(false))
            let released = try await player.client.call("release")
            XCTAssertEqual(released, .null)
            do {
                _ = try await player.client.status()
                XCTFail("status after release of the failed game did not throw")
            } catch {
                XCTAssertTrue(error is RetroHostGone, "\(error)")
            }
        }
    }

    // MARK: Playing

    static let played = [
        "body-duplicate-key", "body-lone-surrogate", "body-not-json", "body-not-object", "body-not-utf8", "body-too-short",
        "body-without-type", "exit-during-call", "first-message-not-welcome", "frame-before-ring", "frame-larger-than-slot",
        "host-unsupported", "hung-call", "missed-pong", "no-welcome", "old-epoch-frame", "older-host-without-core",
        "oversized-frame", "oversized-message", "play-and-quit", "pong-wrong-id", "reply-wrong-id", "ring-bad-geometry", "ring-grows",
        "ring-not-grown", "ring-size-mismatch", "ring-unsealed", "ring-without-descriptor", "shutdown-deadline",
        "stop-deadline", "stray-descriptor", "unknown-from-host", "unknown-values-from-host", "welcome-not-offered",
        "welcome-wrong-pid",
    ]

    static func checkout() throws -> URL {
        guard let checkout = RetroHostFixtures.checkout else { throw XCTSkip("ANYPS5_RETRO_HOST_CHECKOUT is not set") }
        return checkout
    }

    static func sessionURL(_ checkout: URL, _ name: String) -> URL {
        checkout.appendingPathComponent("fixtures/v1/sessions/\(name).json")
    }

    static func sessionNames(_ checkout: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: checkout.appendingPathComponent("fixtures/v1/sessions").path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    static func python() throws -> String {
        for folder in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(folder)/python3"
            if folder.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw XCTSkip("python3 is not on PATH")
    }

    static func callMessage(_ id: Int, _ method: String, _ args: RetroJSON) -> RetroJSON {
        .object(["type": .string("call"), "id": .int(id), "method": .string(method), "args": args])
    }

    static func replyMessage(_ id: Int, _ result: RetroJSON) -> RetroJSON {
        .object(["type": .string("reply"), "id": .int(id), "result": result])
    }

    /// Steps 4 to 7 of ring-grows: `start`, its reply, a ring, and a frame of the game.
    static func startedGame(_ checkout: URL) throws -> [RetroJSON] {
        let steps = try RetroHostFixtures.read(sessionURL(checkout, "ring-grows")).objectValue?["steps"]?.arrayValue ?? []
        guard steps.count > 7 else { throw XCTSkip("ring-grows has changed") }
        return Array(steps[4...7])
    }

    /// The start of a session: hello, welcome (listing `capabilities`) and the first volume call.
    static func greeting(capabilities: [String]) -> [RetroJSON] { [
        .object(["from": .string("launcher"), "message": .object([
            "type": .string("hello"), "minVersion": .int(1), "maxVersion": .int(1),
            "pixelFormats": .array([.string("rgba8"), .string("bgra8")]),
        ]), "anyValueFor": .array([.string("pixelFormats")])]),
        .object(["from": .string("host"), "message": .object([
            "type": .string("welcome"), "version": .int(1), "pid": .int(1), "hostVersion": .string("1.0.0"),
            "capabilities": .array(capabilities.map { .string($0) }), "pixelFormat": .string("rgba8"),
        ]), "anyValueFor": .array([.string("pid"), .string("hostVersion"), .string("pixelFormat")])]),
        .object(["from": .string("launcher"), "message": callMessage(1, "volume", .object(["level": .int(1), "muted": .bool(false)])),
                 "anyValueFor": .array([.string("id"), .string("args")])]),
        .object(["from": .string("host"), "message": replyMessage(1, .null), "anyValueFor": .array([.string("id")])]),
    ] }

    private func play(_ name: String) async throws {
        let checkout = try Self.checkout()
        let file = Self.sessionURL(checkout, name)
        let session = try RetroHostFixtures.read(file)
        let os = session.objectValue?["os"]?.stringValue
        guard os == nil || os == "macos" || os == "posix" else { throw XCTSkip("\(name) runs only on \(os ?? "")") }
        try await RetroSessionPlayer(checkout: checkout, python: try Self.python(), file: file, session: session).play()
    }

    private func playOwn(_ description: String, outcome: String, steps: [RetroJSON],
                         capabilities: [String] = [RetroProtocol.ps1Capability],
                         afterReady: ((RetroHostClient) async throws -> Void)? = nil,
                         check: ((RetroSessionPlayer) async throws -> Void)? = nil) async throws {
        let checkout = try Self.checkout()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("retro-host-own-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session: RetroJSON = .object([
            "description": .string(description), "tests": .array([.string("launcher")]), "outcome": .string(outcome),
            "steps": .array(Self.greeting(capabilities: capabilities) + steps),
        ])
        let file = folder.appendingPathComponent("own.json")
        try Data(try session.encoded()).write(to: file)
        try await RetroSessionPlayer(checkout: checkout, python: try Self.python(), file: file, session: session,
                                     afterReady: afterReady, check: check).play()
    }
}

/// Something one side of the test waits for, with a time limit on each wait.
final class RetroWaiter<Value>: @unchecked Sendable {
    struct TimedOut: Error, CustomStringConvertible {
        let description: String
    }

    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var observers: [(Result<Value, Error>) -> Void] = []

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func finish(_ outcome: Result<Value, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        let waiting = observers
        observers = []
        lock.unlock()
        for observer in waiting { observer(outcome) }
    }

    func value(within seconds: Double, _ what: String) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            let once = NSLock()
            var resumed = false
            let resume: (Result<Value, Error>) -> Void = { outcome in
                once.lock()
                let first = !resumed
                resumed = true
                once.unlock()
                if first { continuation.resume(with: outcome) }
            }
            lock.lock()
            if let result {
                lock.unlock()
                resume(result)
                return
            }
            observers.append(resume)
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                resume(.failure(TimedOut(description: "timed out after \(seconds) s waiting for \(what)")))
            }
        }
    }
}

/// One session played against the fake host, the way protocol.md "Fixtures" describes.
final class RetroSessionPlayer: @unchecked Sendable {
    let checkout: URL
    let python: String
    let file: URL
    let session: [String: RetroJSON]
    let afterReady: ((RetroHostClient) async throws -> Void)?
    let check: ((RetroSessionPlayer) async throws -> Void)?
    private(set) var client: RetroHostClient!
    private var work: URL!
    private var paths: [String: String] = [:]
    private var resume: URL!
    private var report: URL!
    private var calls: [RetroWaiter<RetroJSON>] = []
    /// The calls answered by a status the client made itself from the host's (`stopGame()`): it has
    /// only the fields this client reads, so `core` and `timing` (capabilities `coreIdentity` and
    /// `gameTiming`, which it does not read yet) are not compared, as on Windows and Linux.
    private var clientStatuses: Set<ObjectIdentifier> = []
    private let lock = NSLock()
    private var drawnFlags: [Bool] = []
    private var rumbleLog: [RetroRumble] = []

    init(checkout: URL, python: String, file: URL, session: RetroJSON,
         afterReady: ((RetroHostClient) async throws -> Void)? = nil,
         check: ((RetroSessionPlayer) async throws -> Void)? = nil) {
        self.checkout = checkout
        self.python = python
        self.file = file
        self.session = session.objectValue ?? [:]
        self.afterReady = afterReady
        self.check = check
    }

    var rumbles: [RetroRumble] {
        lock.lock()
        defer { lock.unlock() }
        return rumbleLog
    }

    private var frames: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return drawnFlags
    }

    private var outcome: String { session["outcome"]?.stringValue ?? "" }

    func play() async throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("retro-host-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try makePlaceholders()
        let pathsFile = work.appendingPathComponent("paths.json")
        try Data(try RetroJSON.object(paths.mapValues { .string($0) }).encoded()).write(to: pathsFile)
        report = work.appendingPathComponent("report.json")
        resume = work.appendingPathComponent("resume")
        try Data("-1".utf8).write(to: resume)
        client = try await RetroHostClient.start(
            command: [python, "-I", checkout.appendingPathComponent("tests/fake_host.py").path, "--session", file.path,
                      "--report", report.path, "--paths", pathsFile.path, "--resume", resume.path],
            onFrame: { [weak self] event in
                guard let self else { return }
                self.lock.lock()
                self.drawnFlags.append(event.drawn)
                self.lock.unlock()
            },
            onRumble: { [weak self] rumble in
                guard let self else { return }
                self.lock.lock()
                self.rumbleLog.append(rumble)
                self.lock.unlock()
            })
        do {
            try await steps()
            let end = try await wait(40, "the end of the connection") { await $0.ended() }
            let exit = try await wait(20, "the host's exit") { await $0.exited() }
            try await check?(self)
            XCTAssertEqual(end.rawValue, outcome, "outcome (\(client.failureReason ?? "no reason"))")
            if outcome == "clean" { XCTAssertEqual(exit, .code(0), "exit code") }
        } catch {
            await client.close()
            throw error
        }
        await client.close()
        let result = try RetroHostFixtures.read(report).objectValue ?? [:]
        XCTAssertEqual(result["failures"], .array([]), "the fake host's report: \(result)")
        XCTAssertEqual(result["passed"], .bool(true), "the fake host's report: \(result)")
    }

    private func wait<T>(_ seconds: Double, _ what: String, _ body: @escaping (RetroHostClient) async -> T) async throws -> T {
        let waiter = RetroWaiter<T>()
        let client = self.client!
        Task { waiter.finish(.success(await body(client))) }
        return try await waiter.value(within: seconds, what)
    }

    private func makePlaceholders() throws {
        for name in ["core", "disc", "playlist", "disc1", "disc2"] {
            let suffix = name == "core" ? ".dylib" : name == "playlist" ? ".m3u" : ".cue"
            let url = work.appendingPathComponent(name + suffix)
            try Data().write(to: url)
            paths[name] = url.path
        }
        for name in ["system", "saves"] {
            let url = work.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            paths[name] = url.path
        }
    }

    private func fill(_ value: RetroJSON) -> RetroJSON {
        switch value {
        case .string(let text):
            var out = text
            for (name, path) in paths { out = out.replacingOccurrences(of: "${\(name)}", with: path) }
            return .string(out)
        case .array(let items): return .array(items.map(fill))
        case .object(let map): return .object(map.mapValues(fill))
        default: return value
        }
    }

    private func steps() async throws {
        let steps = session["steps"]?.arrayValue ?? []
        let clean = outcome == "clean"
        var welcomed = false
        var shutdown = false
        var stopping: RetroWaiter<RetroStatus?>?
        var frameSteps = 0
        for (index, entry) in steps.enumerated() {
            let step = entry.objectValue ?? [:]
            let from = step["from"]?.stringValue
            if step["invalid"] != nil, from == "host" {
                for pending in calls { _ = try? await pending.value(within: 15, "a call to be answered") }
                return
            }
            let message = step["message"]?.objectValue
            if from == "launcher", let message {
                switch message["type"]?.stringValue {
                case "call":
                    let method = message["method"]?.stringValue ?? ""
                    let waiter = RetroWaiter<RetroJSON>()
                    if method == "volume", !welcomed {
                        welcomed = true
                        let client = self.client!
                        let afterReady = self.afterReady
                        Task {
                            do {
                                try await client.ready()
                                try await afterReady?(client)
                                waiter.finish(.success(.null))
                            } catch {
                                waiter.finish(.failure(error))
                            }
                        }
                    } else if method == "stop" {
                        let stop = RetroWaiter<RetroStatus?>()
                        stopping = stop
                        let client = self.client!
                        let stopTask = Task {
                            do { stop.finish(.success(try await client.stopGame())) } catch { stop.finish(.failure(error)) }
                        }
                        // The screen that asked may be gone: a cancelled caller still sees the stop
                        // through, so the stop deadline is cleared and no hung host is reported.
                        stopTask.cancel()
                        waiter.finish(.success(.null))
                    } else if method == "status", let stop = stopping {
                        stopping = nil
                        clientStatuses.insert(ObjectIdentifier(waiter))
                        Task {
                            do {
                                let status = try await stop.value(within: 30, "stopGame")
                                waiter.finish(.success(status?.json ?? .null))
                            } catch {
                                waiter.finish(.failure(error))
                            }
                        }
                    } else {
                        client.call(method, fill(message["args"] ?? .null)) { waiter.finish($0) }
                    }
                    calls.append(waiter)
                case "input":
                    try client.input(port: message["port"]?.intValue ?? 0, buttons: message["buttons"]?.intValue ?? 0,
                                     leftX: message["leftX"]?.intValue ?? 0, leftY: message["leftY"]?.intValue ?? 0,
                                     rightX: message["rightX"]?.intValue ?? 0, rightY: message["rightY"]?.intValue ?? 0)
                case "shutdown":
                    shutdown = true
                    client.shutdown()
                default:
                    break
                }
            } else if from == "host", let message {
                switch message["type"]?.stringValue {
                case "reply":
                    guard !calls.isEmpty else { return XCTFail("step \(index): a reply with no call waiting") }
                    let pending = calls.removeFirst()
                    var anyValueFor = step["anyValueFor"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    if clientStatuses.remove(ObjectIdentifier(pending)) != nil { anyValueFor += ["result.core", "result.timing"] }
                    try await checkReply(pending, message, anyValueFor)
                case "frame":
                    frameSteps += 1
                    let wanted = frameSteps
                    try await until("frame \(wanted)") { $0.frames.count >= wanted }
                default:
                    break
                }
            } else if let draws = step["launcherDraws"]?.boolValue {
                let wanted = frameSteps
                try await until("frame \(wanted)") { $0.frames.count >= wanted }
                XCTAssertEqual(frames[wanted - 1], draws, "step \(index) launcherDraws")
                XCTAssertEqual(client.frame != nil, draws, "step \(index) frame")
                try await resumeFake(past: index)
            } else if let reports = step["launcherReports"]?.objectValue {
                if !clean { _ = try await wait(30, "the end of the connection") { await $0.ended() } }
                let method = reports["method"]?.stringValue ?? ""
                let expected = reports["result"] ?? .null
                if method == "status" {
                    let status = try await client.status()
                    XCTAssertEqual(status?.failureJSON ?? .null, expected, "step \(index) launcherReports")
                } else {
                    let reported = try await client.call(method)
                    XCTAssertEqual(reported, expected, "step \(index) launcherReports")
                }
                try await resumeFake(past: index)
            }
        }
        if clean, !shutdown { client.shutdown() }
    }

    /// Lets the fake host go on past the step at `index`, where `--resume` holds it, and waits until
    /// its report shows it has (or it has exited), so the next message the client sends meets the next
    /// step.
    private func resumeFake(past index: Int) async throws {
        try Data("\(index)".utf8).write(to: resume)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if client.exit != nil { return }
            if let step = (try? RetroHostFixtures.read(report))?.objectValue?["step"]?.intValue, step > index { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("the fake host did not go past step \(index)")
    }

    private func checkReply(_ pending: RetroWaiter<RetroJSON>, _ reply: [String: RetroJSON], _ anyValueFor: [String]) async throws {
        let ignore = Set(anyValueFor)
        if let error = reply["error"]?.objectValue {
            do {
                _ = try await pending.value(within: 10, "an error reply")
                XCTFail("a call answered with an error gave a result")
            } catch let failure as RetroCallError {
                XCTAssertEqual(failure.code, error["code"]?.stringValue)
            }
            return
        }
        let result: RetroJSON
        do {
            result = try await pending.value(within: 10, "a reply")
        } catch is RetroHostGone {
            return
        }
        compare(reply["result"] ?? .null, result, ignore, "result")
    }

    private func compare(_ expected: RetroJSON, _ actual: RetroJSON, _ ignore: Set<String>, _ place: String) {
        if ignore.contains(place) { return }
        if case .object(let wanted) = expected, case .object(let got) = actual {
            for (key, value) in wanted where !ignore.contains("\(place).\(key)") {
                guard let item = got[key] else {
                    XCTFail("\(place).\(key) is missing")
                    continue
                }
                compare(value, item, ignore, "\(place).\(key)")
            }
            return
        }
        XCTAssertEqual(actual, fill(expected), place)
    }

    private func until(_ what: String, _ done: @escaping (RetroSessionPlayer) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !done(self) {
            if Date() > deadline { throw RetroWaiter<Void>.TimedOut(description: "timed out waiting for \(what)") }
            if client.end != nil {
                try await Task.sleep(nanoseconds: 50_000_000)
                if !done(self) { throw RetroWaiter<Void>.TimedOut(description: "the connection ended while waiting for \(what)") }
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
