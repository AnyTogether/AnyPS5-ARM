import XCTest
@testable import AnyPS5Core

final class IssueDraftTests: XCTestCase {
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

    // MARK: The issue

    func testTheIssueIsPrefilledAndFitsTheLinkLimit() throws {
        let long = (1...400).map { "[gpu] line \($0) " + String(repeating: "x", count: 60) + " /Users/ada/Library" }.joined(separator: "\n") + "\nthe very last line"
        let draft = IssueDraft.crash(report(session: long, crash: ips(pid: 9)))
        XCTAssertLessThanOrEqual(draft.url.absoluteString.count, IssueDraft.maximumLength)
        XCTAssertEqual(draft.title, "Crash: Stray (PPSA01234)")
        let components = try XCTUnwrap(URLComponents(url: draft.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/AnyTogether/AnyPS5-ARM/issues/new")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["template"], "crash.yml")
        XCTAssertEqual(query["title"], "Crash: Stray (PPSA01234)")
        XCTAssertTrue(query["log"]?.hasSuffix("the very last line") == true, "the newest lines are kept")
        XCTAssertLessThanOrEqual(query["log"]?.split(separator: "\n").count ?? 0, 60)
        XCTAssertTrue(query["system"]?.contains("Apple M3 Pro") == true)
        XCTAssertTrue(query["reason"]?.contains("SIGSEGV") == true)
        XCTAssertFalse(draft.url.absoluteString.contains("ada"), "nothing of the user in the link")
        XCTAssertTrue(draft.preview.contains("the very last line"), "the preview shows what the link sends")
    }

    func testTheIssueTemplateHasEveryFieldTheLinkFills() throws {
        // tools/macos/launcher/Tests/AnyPS5CoreTests → the repository root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let template = try String(contentsOf: root.appendingPathComponent(".github/ISSUE_TEMPLATE/crash.yml"), encoding: .utf8)
        for field in IssueDraft.crash(report()).fields {
            XCTAssertTrue(template.contains("id: \(field.id)\n"), "crash.yml has no field \(field.id)")
        }
    }

    func testAPlusInTheLogIsNotASpace() {
        let draft = IssueDraft.crash(report(session: "a+b=c & d#e\n"))
        XCTAssertTrue(draft.url.absoluteString.contains("a%2Bb%3Dc%20%26%20d%23e"))
    }

    func testTheEngineIssueGoesUpstreamWithItsOwnForm() throws {
        let draft = IssueDraft.engine(report())
        let components = try XCTUnwrap(URLComponents(url: draft.url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/boykopovar/AnyPS5/issues/new")
        let names = Set((components.queryItems ?? []).map(\.name))
        // Their form's "title" field is the issue title's parameter too: one value fills both.
        XCTAssertEqual(names, ["template", "title", "summary", "commit", "system", "steps", "log", "notes"])
        XCTAssertEqual(components.queryItems?.first { $0.name == "template" }?.value, "bug_report.yml")
        XCTAssertEqual(draft.title, "Crash: Stray (PPSA01234) 01.000.002")
        XCTAssertLessThanOrEqual(draft.url.absoluteString.count, IssueDraft.maximumLength)
    }
}
