import XCTest
@testable import AnyPS5Core

final class CrashReportTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("crash-report-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let privacy = ReportPrivacy(home: "/Users/ada", names: ["ada", "Ada Lovelace"], secrets: ["s3cr3t-refresh-token-value"])
    private let system = SystemInfo(model: "Mac15,7", chip: "Apple M3 Pro", memoryGB: 18, macOS: "15.6 (24G84)", displayHz: 120)

    /// An .ips crash report as macOS writes it: a JSON header line, then the report.
    private func ips(pid: Int32, signal: String = "SIGSEGV") -> String {
        let header = #"{"app_name":"eboot","timestamp":"2026-10-24 21:46:00.00 +0300","bundleID":"org.anyps5.ppsa01234","name":"eboot"}"#
        let body: [String: Any] = [
            "pid": pid,
            "procPath": "/Users/ada/Games/.AnyPS5/Games/PPSA01234-abc.app/Contents/MacOS/eboot",
            "crashReporterKey": "5D3A-4E1F-SECRET-KEY",
            "sleepWakeUUID": "0F0F0F0F-1111-2222-3333-444444444444",
            "bundleInfo": ["CFBundleIdentifier": "org.anyps5.ppsa01234"],
            "exception": ["type": "EXC_BAD_ACCESS", "signal": signal, "subtype": "KERN_INVALID_ADDRESS at 0x0000000000000010"],
            "faultingThread": 1,
            "threads": [
                ["frames": [["imageOffset": 4096, "imageIndex": 0]]],
                ["frames": [["imageOffset": 74565, "imageIndex": 1, "symbol": "Texture::Upload", "symbolLocation": 52],
                            ["imageOffset": 8192, "imageIndex": 0]]],
            ],
            "usedImages": [["name": "eboot", "base": 4_294_967_296], ["name": "libSceAgcDriver.dylib", "base": 4_311_744_512]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        return header + "\n" + String(decoding: data, as: UTF8.self)
    }

    private func report(session: String = "line one\nline two\n", crash: String? = nil, unlock: String? = nil, diagnosis: Diagnosis? = .crashed("EXC_BAD_ACCESS (SIGSEGV)")) -> SessionReport {
        var settings = GameSettings()
        settings.resolution = "1920x1080"
        settings.frameGeneration = true
        settings.overlay = .topRight
        var report = SessionReport(gameName: "Stray", titleID: "PPSA01234", gameVersion: "01.000.002", settings: settings, system: system,
                                   launcherVersion: "0.2.14", session: session, created: Date(timeIntervalSince1970: 1_792_867_560), privacy: privacy)
        report.unlockedWith = "0.2.13-arm-5c0ffee12345"
        report.engineNow = "0.2.14-arm-0badc0de4321"
        report.diagnosis = diagnosis
        report.crashReport = crash
        report.unlockLog = unlock
        report.started = Date(timeIntervalSince1970: 1_792_866_600)
        report.ended = Date(timeIntervalSince1970: 1_792_867_548)
        return report
    }

    // MARK: Why the game stopped

    func testAnAbortAndANonZeroExitAreReasons() {
        XCTAssertEqual(Diagnosis.read(session: "booting\n[libc] abort() called from 0x1234\n"), .aborted)
        XCTAssertEqual(Diagnosis.read(session: "[libc] exit(3) called from 0x99\n"), .exited(3))
        XCTAssertEqual(Diagnosis.read(session: "[libc] _Exit(-1) called from 0x99\n"), .exited(-1))
        XCTAssertNil(Diagnosis.read(session: "[libc] exit(0) called from 0x99\n"), "a clean exit is no reason")
        XCTAssertEqual(Diagnosis.read(session: "[libc] abort() called from 0x1\n", crashReport: ips(pid: 1, signal: "SIGABRT")), .aborted,
                       "the engine's own line says more than the signal")
    }

    func testTheCrashReportIsTheOneOfThatProcess() throws {
        let reports = folder.appendingPathComponent("DiagnosticReports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        try ips(pid: 111).write(to: reports.appendingPathComponent("eboot-2026-10-24-214500.ips"), atomically: true, encoding: .utf8)
        try ips(pid: 222).write(to: reports.appendingPathComponent("eboot-2026-10-24-214600.ips"), atomically: true, encoding: .utf8)
        try ips(pid: 333).write(to: reports.appendingPathComponent("Other-2026-10-24-214600.ips"), atomically: true, encoding: .utf8)
        let since = Date().addingTimeInterval(-60)
        let found = Diagnosis.crashReport(since: since, bundleIdentifier: "org.anyps5.ppsa01234", pid: 111, folder: reports)
        XCTAssertNotNil(found)
        XCTAssertTrue(found?.contains("\"pid\" : 111") == true)
        XCTAssertNil(Diagnosis.crashReport(since: since, bundleIdentifier: "org.anyps5.ppsa01234", pid: 333, folder: reports), "only the game's executable")
        XCTAssertNil(Diagnosis.crashReport(since: Date().addingTimeInterval(60), bundleIdentifier: "org.anyps5.ppsa01234", pid: 111, folder: reports), "only reports since the start")
        XCTAssertNotNil(Diagnosis.crashReport(since: since, bundleIdentifier: "org.anyps5.ppsa01234", folder: reports), "without a pid, the newest")
    }

    func testTheCrashedThreadReadsAsFrames() {
        let frames = Diagnosis.crashFrames(ips(pid: 1))
        XCTAssertEqual(frames, ["0  libSceAgcDriver.dylib  Texture::Upload + 52", "1  eboot  + 0x2000"])
    }

    // MARK: Privacy

    func testTheReportCarriesNothingThatNamesTheUser() {
        let text = """
        dyld[57586]: Library not loaded from /Users/ada/Games/x.app and /Users/someone/else
        saved to /Users/ada/Pictures/AnyPS5/shot.png by Ada Lovelace (ada@example.com), Ada-Lovelace-MacBook
        Authorization: Bearer abcdefghijklmnop.qrstu
        {"accessToken": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2lnbmF0dXJlLXZhbHVl", "refreshToken":"s3cr3t-refresh-token-value"}
        "crashReporterKey" : "5D3A-4E1F-SECRET-KEY",
        joined with token=abcdef123456 at 192.168.1.20 — adapter stays
        """
        let clean = privacy.clean(text)
        for leak in ["/Users/ada", "/Users/someone", "Ada Lovelace", "Ada-Lovelace", "ada@example.com", "abcdefghijklmnop", "eyJhbGci", "s3cr3t", "5D3A-4E1F", "abcdef123456", "192.168.1.20"] {
            XCTAssertFalse(clean.contains(leak), "\(leak) is still in:\n\(clean)")
        }
        XCTAssertTrue(clean.contains("~/Games/x.app"))
        XCTAssertTrue(clean.contains("~/Pictures/AnyPS5/shot.png"))
        XCTAssertTrue(clean.contains("adapter stays"), "a word holding the user name is left alone")
        XCTAssertTrue(clean.contains("Library not loaded"))
    }

    // MARK: The report file

    func testTheReportSaysWhatHappenedOnWhichMac() {
        let text = report(crash: ips(pid: 4242)).text()
        for part in ["Stray (PPSA01234), version 01.000.002", "The game crashed: EXC_BAD_ACCESS (SIGSEGV)", "Mac15,7", "Apple M3 Pro", "18 GB",
                     "macOS 15.6 (24G84)", "120 Hz", "Launcher: 0.2.14", "0.2.13-arm-5c0ffee12345", "0.2.14-arm-0badc0de4321",
                     "Resolution 1920x1080", "Frame generation on", "Overlay top right", "Texture::Upload + 52", "line two"] {
            XCTAssertTrue(text.contains(part), "\(part) is missing from:\n\(text)")
        }
        XCTAssertFalse(text.contains("/Users/ada"))
        XCTAssertFalse(text.contains("5D3A-4E1F"))
    }

    func testTheReportNamesTheUpdateChannel() {
        var nightly = report()
        nightly.launcherVersion = "0.2.17-arm-nightly.20261025.1"
        nightly.updateChannel = "nightly"
        XCTAssertTrue(nightly.text().contains("Launcher: 0.2.17-arm-nightly.20261025.1 (nightly channel)"))
        XCTAssertTrue(nightly.versionsLine.hasPrefix("Launcher 0.2.17-arm-nightly.20261025.1 (nightly channel)"))
        XCTAssertTrue(report().text().contains("Launcher: 0.2.14\n"), "no channel known, none said")
    }

    func testOneFileIsTextAndSeveralAreAZip() throws {
        let plain = report(diagnosis: .engineError("boom"))
        XCTAssertFalse(plain.archived)
        XCTAssertEqual(plain.fileName, "AnyPS5-PPSA01234-\(SessionReport.stamp(plain.created)).txt")
        let text = folder.appendingPathComponent(plain.fileName)
        try plain.write(to: text)
        XCTAssertTrue(try String(contentsOf: text, encoding: .utf8).contains("Engine error: boom"))

        let full = report(session: (1...500).map { "log \($0) /Users/ada/x" }.joined(separator: "\n"), crash: ips(pid: 7), unlock: "relink: 12 modules\n/Users/ada/Games")
        XCTAssertTrue(full.archived)
        XCTAssertTrue(full.fileName.hasSuffix(".zip"))
        let zip = folder.appendingPathComponent(full.fileName)
        try full.write(to: zip)
        let out = folder.appendingPathComponent("out")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, out.path]
        try unzip.run()
        unzip.waitUntilExit()
        let inside = out.appendingPathComponent(full.baseName)
        let names = try FileManager.default.contentsOfDirectory(atPath: inside.path).sorted()
        XCTAssertEqual(names, ["\(full.baseName).txt", "crash-report.ips", "game.log", "settings.json", "unlock.log"])
        let log = try String(contentsOf: inside.appendingPathComponent("game.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("log 1 ~/x"), "the whole log goes in, cleaned")
        XCTAssertFalse(try String(contentsOf: inside.appendingPathComponent("unlock.log"), encoding: .utf8).contains("/Users/ada"))
        XCTAssertFalse(try String(contentsOf: inside.appendingPathComponent("crash-report.ips"), encoding: .utf8).contains("/Users/ada"))
    }

    func testAGameThatNeverShowedAWindowStoppedAbnormally() {
        var clean = report(diagnosis: nil)
        XCTAssertFalse(clean.abnormal)
        XCTAssertEqual(clean.reason, "No error found: the game closed normally")
        clean.startedWithoutWindow = true
        XCTAssertTrue(clean.abnormal)
        XCTAssertEqual(clean.reason, "The game closed before its window appeared")
    }

    func testTheKeptAnyTogetherTokensAreTakenOut() {
        let store = TokenStore(file: folder.appendingPathComponent("session.json"))
        XCTAssertEqual(store.secrets, [])
        store.save(.init(accessToken: "access-123456", accessExpiry: Date(), refreshToken: "refresh-654321",
                         user: TogetherUser(id: "u1", handle: "ada", displayName: "Ada", avatar: nil)))
        XCTAssertEqual(store.secrets, ["access-123456", "refresh-654321"])
        let privacy = ReportPrivacy(home: "/Users/x", secrets: store.secrets)
        XCTAssertEqual(privacy.clean("hello access-123456 and refresh-654321"), "hello <redacted> and <redacted>")
    }
}
