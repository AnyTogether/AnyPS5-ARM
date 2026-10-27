import Foundation
import XCTest
@testable import AnyPS5Core

final class UpdatesTests: XCTestCase {
    func testAReleaseIsNewerOnlyWhenItsNumberIs() {
        XCTAssertTrue(Updates.isNewer("v0.2.6-arm", than: "0.2.5-arm"))
        XCTAssertTrue(Updates.isNewer("v0.3.0-arm", than: "0.2.9-arm"))
        XCTAssertTrue(Updates.isNewer("v0.2.10-arm", than: "0.2.9-arm"))
        XCTAssertFalse(Updates.isNewer("v0.2.5-arm", than: "0.2.5-arm"))
        XCTAssertFalse(Updates.isNewer("v0.2.4-arm", than: "0.2.5-arm"))
    }

    func testADevelopmentBuildIsPastItsTagButBeforeTheNextRelease() {
        XCTAssertFalse(Updates.isNewer("v0.2.4-arm", than: "0.2.4-arm-766-gee1fab911"))
        XCTAssertTrue(Updates.isNewer("v0.2.5-arm", than: "0.2.4-arm-766-gee1fab911"))
    }

    func testAnUnreadableVersionIsNeverOffered() {
        XCTAssertFalse(Updates.isNewer("nightly", than: "0.2.5-arm"))
        XCTAssertFalse(Updates.isNewer("v0.2.6-arm", than: "dev"))
    }

    func testTheLatestReleaseAsGitHubDescribesIt() throws {
        let json = """
        {"tag_name":"v0.2.6-arm","name":"AnyPS5-ARM 0.2.6","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.6-arm","draft":false,"prerelease":false,
         "assets":[{"name":"install.sh","browser_download_url":"https://example.com/install.sh","size":1562},
                   {"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/AnyPS5-macOS.zip","size":47256820}]}
        """
        let release = try XCTUnwrap(Updates.release(from: Data(json.utf8)))
        XCTAssertEqual(release.tag, "v0.2.6-arm")
        XCTAssertEqual(release.version, "0.2.6")
        XCTAssertEqual(release.page.absoluteString, "https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.6-arm")
        XCTAssertEqual(release.download?.absoluteString, "https://example.com/AnyPS5-macOS.zip")
        XCTAssertEqual(release.size, 47256820)
    }

    func testDraftsPrereleasesAndOtherShapesAreIgnored() {
        let draft = #"{"tag_name":"v0.2.6-arm","html_url":"https://x","draft":true,"prerelease":false,"assets":[]}"#
        let pre = #"{"tag_name":"v0.2.6-arm","html_url":"https://x","draft":false,"prerelease":true,"assets":[]}"#
        XCTAssertNil(Updates.release(from: Data(draft.utf8)))
        XCTAssertNil(Updates.release(from: Data(pre.utf8)))
        XCTAssertNil(Updates.release(from: Data(#"{"message":"API rate limit exceeded"}"#.utf8)))
    }

    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("updates-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func app(_ path: String, id: String = "org.anyps5.launcher", version: String, marker: String) throws -> URL {
        let app = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version]
        XCTAssertTrue(info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
        try marker.write(to: app.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
        return app
    }

    func runScript(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()
    }

    func marker(_ app: URL) -> String? { try? String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8) }

    func testTheNewAppTakesTheOldOnesPlaceAndIsOpened() throws {
        let old = try app("Applications/AnyPS5.app", version: "0.2.5-arm", marker: "old")
        let new = try app("update/app/AnyPS5.app", version: "0.2.6-arm", marker: "new")
        let opened = folder.appendingPathComponent("opened")
        try runScript(Updates.replacementScript(old: old, new: new, pid: 999_999, relaunch: "echo > '\(opened.path)'"))
        XCTAssertEqual(marker(old), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path + ".previous"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("update").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: opened.path))
    }

    func testLaterPutsTheUpdateInPlaceWithoutOpeningIt() throws {
        XCTAssertEqual(Updates.relaunchCommand(true), "/usr/bin/open")
        let old = try app("Applications/AnyPS5.app", version: "0.2.5-arm", marker: "old")
        let new = try app("update/app/AnyPS5.app", version: "0.2.6-arm", marker: "new")
        try runScript(Updates.replacementScript(old: old, new: new, pid: 999_999, relaunch: Updates.relaunchCommand(false)))
        XCTAssertEqual(marker(old), "new", "the next launch is the new version")
    }

    func testAFailedCopyKeepsTheOldApp() throws {
        let old = try app("Applications/AnyPS5.app", version: "0.2.5-arm", marker: "old")
        let missing = folder.appendingPathComponent("update/app/AnyPS5.app")
        try runScript(Updates.replacementScript(old: old, new: missing, pid: 999_999, relaunch: "true"))
        XCTAssertEqual(marker(old), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path + ".previous"))
    }

    func testOnlyANewerCopyOfThisAppIsAccepted() throws {
        let newer = try app("a/AnyPS5.app", version: "0.2.6-arm", marker: "x")
        let other = try app("b/AnyPS5.app", id: "com.example.other", version: "0.2.6-arm", marker: "x")
        let older = try app("c/AnyPS5.app", version: "0.2.5-arm", marker: "x")
        XCTAssertNoThrow(try Updates.check(newer, bundleIdentifier: "org.anyps5.launcher", current: "0.2.5-arm"))
        XCTAssertThrowsError(try Updates.check(other, bundleIdentifier: "org.anyps5.launcher", current: "0.2.5-arm"))
        XCTAssertThrowsError(try Updates.check(older, bundleIdentifier: "org.anyps5.launcher", current: "0.2.5-arm"))
        XCTAssertThrowsError(try Updates.check(folder.appendingPathComponent("none.app"), bundleIdentifier: "org.anyps5.launcher", current: "0.2.5-arm"))
    }
}
