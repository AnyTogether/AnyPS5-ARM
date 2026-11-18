@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// A fake GitHub for the host's releases in the launcher's tests: the API's list and each file by
/// its address, every request recorded.
final class RetroHostTestGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var asked: [String] = []
    private static let lock = NSLock()
    static let api = URL(string: "https://api.github.example")!

    static func reset() { lock.withLock { files = [:]; asked = [] } }
    static var requests: [String] { lock.withLock { asked } }

    /// The recorded signed release (AnyPS5CoreTests/Fixtures/RetroHostRelease) under v1.0.0, or no
    /// release at all.
    static func publishFixture(_ published: Bool = true) throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../AnyPS5CoreTests/Fixtures/RetroHostRelease").standardized
        var assets: [[String: Any]] = []
        if published {
            let sums = try Data(contentsOf: folder.appendingPathComponent(ReleaseSigning.sumsName))
            for name in try ReleaseSigning.parseSums(sums).keys.sorted() + [ReleaseSigning.sumsName, ReleaseSigning.signatureName] {
                let data = try Data(contentsOf: folder.appendingPathComponent(name))
                let url = "https://github.example/v1.0.0/\(name)"
                lock.withLock { files[url] = data }
                assets.append(["name": name, "browser_download_url": url, "size": data.count])
            }
        }
        let list = published ? [["tag_name": "v1.0.0", "prerelease": false, "draft": false, "assets": assets] as [String: Any]] : []
        let data = try JSONSerialization.data(withJSONObject: list)
        lock.withLock { files["https://api.github.example/repos/\(RetroHostStore.repository)/releases?per_page=100"] = data }
    }

    static var keys: [ReleaseSigning.Key] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../AnyPS5CoreTests/Fixtures/RetroHostRelease").standardized
        return ReleaseSigning.keys(from: (try? String(contentsOf: folder.appendingPathComponent("test-release-signing.pub"), encoding: .utf8)) ?? "")
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetroHostTestGitHub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let address = request.url?.absoluteString ?? ""
        let body: Data? = Self.lock.withLock {
            Self.asked.append(address)
            return Self.files[address]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Settings › Emulators' row for the PS1 emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host_release_play_test.dart): nothing downloaded unasked, the signed release
/// downloaded, checked and installed from a fake GitHub, found up to date, offered again after a
/// failed check, none published yet, and the debug build's unchecked host.
@MainActor
final class RetroHostDownloadTests: XCTestCase {
    private var made: [URL] = []

    override func setUp() { RetroHostTestGitHub.reset() }

    override func tearDown() {
        for url in made { try? FileManager.default.removeItem(at: url) }
        made = []
        RetroHostTestGitHub.reset()
    }

    private func model(releases: Bool = true) throws -> AppModel {
        let model = try LauncherFixture.model(games: 1)
        made.append(contentsOf: model.libraryRoots)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-host-\(UUID().uuidString)")
        made.append(root)
        model.retroHostRoot = root
        model.retroHostKeys = RetroHostTestGitHub.keys
        model.retroHostSession = RetroHostTestGitHub.configuration
        if releases {
            model.retroHostReleases = {
                try await RetroHostStore.releases(session: URLSession(configuration: RetroHostTestGitHub.configuration), api: RetroHostTestGitHub.api)
            }
        }
        model.retroHostUnchecked = nil
        model.setRetroLibrary(true)
        return model
    }

    private func rows(_ model: AppModel) -> [PanelRow] { model.standaloneEmulatorSettings().rows }

    private func hostRow(_ model: AppModel) throws -> PanelRow {
        try XCTUnwrap(rows(model).first { $0.id == "retro-host-download" }, "the download row")
    }

    private func select(_ row: PanelRow) throws {
        guard case .action(_, let run) = row.kind else { return XCTFail("\(row.id) is no action") }
        run()
    }

    private func settle(_ condition: () -> Bool, _ message: String = "") async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
    }

    func testTheRowSitsAmongTheEmulatorsAndDownloadsNothingUnasked() throws {
        try RetroHostTestGitHub.publishFixture()
        let model = try model()
        let ids = rows(model).map(\.id)
        XCTAssertEqual(ids, ["retro-ps1", "retro-ps2", "retro-ps3", "retro-host-download", "retro-show-folders"])
        let row = try hostRow(model)
        XCTAssertEqual(row.title, "Download the PS1 emulator")
        XCTAssertEqual(row.detail, "The AnyPS5 emulator host with SwanStation, to play PS1 games in this window. Its files are signed and checked before every game. Nothing is downloaded until you select this.")
        XCTAssertTrue(RetroHostTestGitHub.requests.isEmpty, "nothing is asked of GitHub until the row is selected")
        XCTAssertNil(model.retroHostDownload.installed)

        let offline = try self.model(releases: false)
        XCTAssertFalse(rows(offline).contains { $0.id == "retro-host-download" }, "no row where no release can be read")
    }

    func testSelectingItDownloadsChecksAndInstallsTheSignedRelease() async throws {
        try RetroHostTestGitHub.publishFixture()
        let model = try model()
        try select(try hostRow(model))
        XCTAssertTrue(model.retroHostDownload.downloading)
        XCTAssertEqual(try hostRow(model).title, "Downloading the PS1 emulator, 0%")
        try await settle({ !model.retroHostDownload.downloading }, "the download ends")
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.0.0 is ready")
        let installed = try XCTUnwrap(model.retroHostDownload.installed)
        XCTAssertTrue(installed.checked)
        XCTAssertEqual(installed.host, model.retroHostRoot.appendingPathComponent("host/anyps5-retro-host").path)
        let row = try hostRow(model)
        XCTAssertEqual(row.title, "PS1 emulator 1.0.0")
        XCTAssertEqual(row.detail, "Signed, and checked before every game. Select to look for an update.")
        XCTAssertTrue(RetroHostTestGitHub.requests.contains { $0.hasSuffix("anyps5-retro-host-1.0.0-macos-arm64.zip") })
        XCTAssertFalse(RetroHostTestGitHub.requests.contains { $0.hasSuffix("windows-x64.zip") || $0.hasSuffix("source.tar.gz") },
                       "only this system's files")

        // Selected again: the same version, whole and passing its checks, is not downloaded again.
        RetroHostTestGitHub.reset()
        try RetroHostTestGitHub.publishFixture()
        try select(row)
        try await settle({ !model.retroHostDownload.downloading })
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.0.0 is up to date")
        XCTAssertFalse(RetroHostTestGitHub.requests.contains { $0.hasSuffix(".zip") })

        // A failed check before a start offers it again, at the same version.
        model.retroHostDownload.failedCheck("swanstation_libretro.dylib does not match the signed release")
        let broken = try hostRow(model)
        XCTAssertEqual(broken.title, "Download the PS1 emulator")
        XCTAssertEqual(broken.detail, "Its files did not pass their check before the last game. Select to download it again.")
        try select(broken)
        try await settle({ !model.retroHostDownload.downloading })
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.0.0 is ready")
        XCTAssertTrue(RetroHostTestGitHub.requests.contains { $0.hasSuffix("macos-arm64.zip") }, "downloaded again")
        XCTAssertEqual(try hostRow(model).title, "PS1 emulator 1.0.0")
    }

    func testWithNoSignedReleaseTheRowSaysNoneIsPublishedYet() async throws {
        try RetroHostTestGitHub.publishFixture(false)
        let model = try model()
        try select(try hostRow(model))
        try await settle({ !model.retroHostDownload.downloading })
        XCTAssertEqual(model.toast?.text, "No signed PS1 emulator has been published yet. Try again later.")
        XCTAssertEqual(try hostRow(model).detail, "No signed PS1 emulator has been published yet. Try again later.")
        XCTAssertNil(model.retroHostDownload.installed)
    }

    func testNoDownloadWhileAGameIsStartingInTheHost() async throws {
        try RetroHostTestGitHub.publishFixture()
        let model = try model()
        XCTAssertTrue(model.retroHostDownload.holdForStart())
        try select(try hostRow(model))
        XCTAssertFalse(model.retroHostDownload.downloading)
        XCTAssertEqual(model.toast?.text, "Close the PS1 game first, then download the emulator")
        model.retroHostDownload.releaseStart()
        try select(try hostRow(model))
        XCTAssertTrue(model.retroHostDownload.downloading)
        model.retroHostDownload.cancel()
        try await settle({ !model.retroHostDownload.downloading }, "stopped")
        XCTAssertNil(model.retroHostDownload.installed)
    }

    func testADebugBuildsUncheckedHostShowsNoDownloadButSaysItIsUnchecked() throws {
        try RetroHostTestGitHub.publishFixture()
        let model = try model()
        model.retroHostUnchecked = RetroHostInstall(host: "/tmp/anyps5-retro-host", core: "/tmp/swanstation_libretro.dylib")
        let all = rows(model)
        XCTAssertFalse(all.contains { $0.id == "retro-host-download" })
        let notice = try XCTUnwrap(all.first { $0.id == "retro-host-unchecked" })
        XCTAssertEqual(notice.title, "Unchecked emulator (test build)")
        XCTAssertEqual(notice.detail, "This build is for testing: it runs the emulator that ANYPS5_RETRO_HOST names without checking its signature or files. Normal releases only run the signed emulator.")
    }
}
