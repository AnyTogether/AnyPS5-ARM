import CryptoKit
import Foundation
import XCTest
@testable import AnyPS5Core

/// A toolkit folder as tools/macos/toolkit_layout.sh makes it, with made-up contents.
enum FakeToolkit {
    static func make(in parent: URL, name: String = "toolkit", version: String? = "0.2.15-arm-0123456789ab", manifest: Bool = true,
                     minimumLauncher: String = "0.2.15") throws -> URL {
        let folder = parent.appendingPathComponent(name)
        let fileManager = FileManager.default
        for sub in ["libs", "vulkan", "patches"] { try fileManager.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true) }
        try Data("#!/bin/sh\necho relinker\n".utf8).write(to: folder.appendingPathComponent("relinker"))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("relinker").path)
        try Data("libSceAgc".utf8).write(to: folder.appendingPathComponent("libs/libSceAgc.prx"))
        try Data("libSceAudioOut".utf8).write(to: folder.appendingPathComponent("libs/libSceAudioOut.prx"))
        try Data("loader".utf8).write(to: folder.appendingPathComponent("vulkan/libvulkan.1.dylib"))
        try Data("moltenvk".utf8).write(to: folder.appendingPathComponent("vulkan/libMoltenVK.dylib"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("vulkan/MoltenVK_icd.json"))
        try Data(#"{"titleId":"PPSA02100"}"#.utf8).write(to: folder.appendingPathComponent("patches/PPSA02100.json"))
        if let version { try Data((version + "\n").utf8).write(to: folder.appendingPathComponent("version.txt")) }
        if manifest, let version { try writeManifest(folder, version: version, minimumLauncher: minimumLauncher) }
        return folder
    }

    static func writeManifest(_ folder: URL, version: String, minimumLauncher: String = "0.2.15") throws {
        var files: [String: String] = [:]
        let base = folder.standardizedFileURL.path
        for case let file as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])! {
            guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count + 1))
            guard relative != "toolkit.json" else { continue }
            files[relative] = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        }
        let manifest: [String: Any] = ["format": 1, "version": version, "engineCommit": "4129291e129a290e95da911a06f6d1fa6320bb13", "upstreamBase": NSNull(),
                                       "buildDate": "2026-10-24T19:33:39Z", "minimumLauncher": minimumLauncher, "files": files]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("toolkit.json"))
    }

    /// The folder zipped as package_toolkit.sh zips it: one folder of the asset's name.
    static func zip(_ folder: URL, to file: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", folder.path, file.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    static func sha256(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }
}

final class EngineToolkitTests: XCTestCase {
    var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: Layout and verification

    func testACompleteToolkitHasNoLayoutProblem() throws {
        let folder = try FakeToolkit.make(in: scratch)
        XCTAssertNil(Toolkit.layoutProblem(at: folder))
        XCTAssertEqual(Toolkit(root: folder).version, "0.2.15-arm-0123456789ab")
        XCTAssertEqual(Toolkit(root: folder).manifest?.engineCommit, "4129291e129a290e95da911a06f6d1fa6320bb13")
    }

    func testAFolderMissingAPartIsNotAToolkit() throws {
        let folder = try FakeToolkit.make(in: scratch)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("vulkan/libMoltenVK.dylib"))
        XCTAssertNotNil(Toolkit.layoutProblem(at: folder))
        let empty = try FakeToolkit.make(in: scratch, name: "nolibs")
        for library in try FileManager.default.contentsOfDirectory(at: empty.appendingPathComponent("libs"), includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: library)
        }
        XCTAssertNotNil(Toolkit.layoutProblem(at: empty))
        let plain = try FakeToolkit.make(in: scratch, name: "noexec")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.appendingPathComponent("relinker").path)
        XCTAssertNotNil(Toolkit.layoutProblem(at: plain))
        XCTAssertNotNil(Toolkit.layoutProblem(at: scratch.appendingPathComponent("nothing")))
    }

    /// A folder someone built without version.txt is named by the same fingerprint the build
    /// script writes: sha256 of the relinker, the libraries and the patches, in that order.
    func testAFolderWithoutVersionIsNamedByItsFingerprint() throws {
        let folder = try FakeToolkit.make(in: scratch, version: nil)
        var data = try Data(contentsOf: folder.appendingPathComponent("relinker"))
        data += try Data(contentsOf: folder.appendingPathComponent("libs/libSceAgc.prx"))
        data += try Data(contentsOf: folder.appendingPathComponent("libs/libSceAudioOut.prx"))
        data += try Data(contentsOf: folder.appendingPathComponent("patches/PPSA02100.json"))
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12)
        XCTAssertEqual(Toolkit(root: folder).version, "local-" + expected)
    }

    func testTheShortVersionKeepsTheReleaseAndAPieceOfTheFingerprint() {
        XCTAssertEqual(Toolkit.shortVersion("0.2.15-arm-f5a134ca6b11"), "0.2.15-arm · f5a134")
        // Between releases, git describe's commits since the tag stay, its hash goes.
        XCTAssertEqual(Toolkit.shortVersion("0.2.14-arm-20-g4129291e1-f5a134ca6b11"), "0.2.14-arm+20 · f5a134")
        XCTAssertEqual(Toolkit.shortVersion("local-f5a134ca6b11"), "local · f5a134")
        XCTAssertEqual(Toolkit.shortVersion("unknown"), "unknown")
    }

    func testAMatchingFolderVerifies() throws {
        let folder = try FakeToolkit.make(in: scratch)
        let manifest = try XCTUnwrap(Toolkit(root: folder).manifest)
        XCTAssertNoThrow(try ToolkitVerifier.verify(folder, manifest: manifest))
    }

    func testAChangedFileFailsVerification() throws {
        let folder = try FakeToolkit.make(in: scratch)
        try Data("#!/bin/sh\nrm -rf ~\n".utf8).write(to: folder.appendingPathComponent("relinker"))
        let manifest = try XCTUnwrap(Toolkit(root: folder).manifest)
        XCTAssertThrowsError(try ToolkitVerifier.verify(folder, manifest: manifest))
    }

    func testAnExtraOrMissingFileFailsVerification() throws {
        let extra = try FakeToolkit.make(in: scratch, name: "extra")
        try Data("surprise".utf8).write(to: extra.appendingPathComponent("libs/libSceExtra.prx"))
        XCTAssertThrowsError(try ToolkitVerifier.verify(extra, manifest: XCTUnwrap(Toolkit(root: extra).manifest)))
        let hidden = try FakeToolkit.make(in: scratch, name: "hidden")
        try Data("surprise".utf8).write(to: hidden.appendingPathComponent(".run.sh"))
        XCTAssertThrowsError(try ToolkitVerifier.verify(hidden, manifest: XCTUnwrap(Toolkit(root: hidden).manifest)))
        let missing = try FakeToolkit.make(in: scratch, name: "missing")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("patches/PPSA02100.json"))
        XCTAssertThrowsError(try ToolkitVerifier.verify(missing, manifest: XCTUnwrap(Toolkit(root: missing).manifest)))
    }

    func testALinkFailsVerification() throws {
        let folder = try FakeToolkit.make(in: scratch)
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("libs/libSceLink.prx").path, withDestinationPath: "/bin/sh")
        XCTAssertThrowsError(try ToolkitVerifier.verify(folder, manifest: XCTUnwrap(Toolkit(root: folder).manifest)))
    }

    func testAManifestNamingAPathOutsideTheFolderFails() throws {
        let folder = try FakeToolkit.make(in: scratch)
        var manifest = try XCTUnwrap(Toolkit(root: folder).manifest)
        manifest.files["../outside"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try ToolkitVerifier.verify(folder, manifest: manifest))
    }

    // MARK: Catalogue

    static let releases = """
    [
     {"tag_name":"v0.2.16-arm","name":"AnyPS5-ARM 0.2.16","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.16-arm","draft":false,"prerelease":false,
      "published_at":"2026-11-02T10:00:00Z","body":"## What's new\\r\\n\\r\\n- **Faster** shader cache\\r\\n- Stray runs at 60 FPS\\r\\n",
      "assets":[{"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/AnyPS5-macOS.zip","size":47256820},
                {"name":"AnyPS5-toolkit-macos-0.2.16-arm.zip","browser_download_url":"https://example.com/AnyPS5-toolkit-macos-0.2.16-arm.zip","size":39024826,
                 "digest":"sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"}]},
     {"tag_name":"v0.2.17-arm","name":"Draft","html_url":"https://x","draft":true,"prerelease":false,"published_at":null,"body":"",
      "assets":[{"name":"AnyPS5-toolkit-macos-0.2.17-arm.zip","browser_download_url":"https://example.com/t.zip","size":1}]},
     {"tag_name":"v0.2.15-arm","name":"AnyPS5-ARM 0.2.15","html_url":"https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.2.15-arm","draft":false,"prerelease":true,
      "published_at":"2026-10-25T10:00:00Z","body":"Engine picker. See [the notes](https://example.com) for more.",
      "assets":[{"name":"AnyPS5-toolkit-macos-0.2.15-arm.zip","browser_download_url":"https://example.com/AnyPS5-toolkit-macos-0.2.15-arm.zip","size":38000000,"digest":null}]},
     {"tag_name":"v0.2.14-arm","name":"AnyPS5-ARM 0.2.14","html_url":"https://x","draft":false,"prerelease":false,"published_at":"2026-10-20T10:00:00Z","body":"Old",
      "assets":[{"name":"AnyPS5-macOS.zip","browser_download_url":"https://example.com/AnyPS5-macOS.zip","size":47256820}]}
    ]
    """

    func testTheCatalogueListsEveryPublishedReleaseWithAToolkit() throws {
        let entries = try XCTUnwrap(EngineCatalogue.entries(from: Data(Self.releases.utf8)))
        XCTAssertEqual(entries.map(\.release), ["0.2.16-arm", "0.2.15-arm"])
        let newest = entries[0]
        XCTAssertEqual(newest.tag, "v0.2.16-arm")
        XCTAssertEqual(newest.download.absoluteString, "https://example.com/AnyPS5-toolkit-macos-0.2.16-arm.zip")
        XCTAssertEqual(newest.size, 39024826)
        XCTAssertEqual(newest.digest, "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
        XCTAssertEqual(newest.summary, "Faster shader cache · Stray runs at 60 FPS")
        XCTAssertEqual(newest.date, ISO8601DateFormatter().date(from: "2026-11-02T10:00:00Z"))
        XCTAssertFalse(newest.prerelease)
        XCTAssertNil(entries[1].digest)
        XCTAssertTrue(entries[1].prerelease)
        XCTAssertEqual(entries[1].summary, "Engine picker. See the notes for more.")
    }

    func testAnAnswerThatIsNotAListIsNoCatalogue() {
        XCTAssertNil(EngineCatalogue.entries(from: Data(#"{"message":"API rate limit exceeded"}"#.utf8)))
        XCTAssertNil(EngineCatalogue.entries(from: Data("nonsense".utf8)))
    }

    func testTheSummaryIsShort() {
        let long = String(repeating: "word ", count: 80)
        XCTAssertLessThanOrEqual(EngineCatalogue.summary(of: long).count, 141)
        XCTAssertEqual(EngineCatalogue.summary(of: ""), "")
    }

    func testTheCatalogueIsCachedForOfflineUse() throws {
        let entries = try XCTUnwrap(EngineCatalogue.entries(from: Data(Self.releases.utf8)))
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        XCTAssertNil(store.cachedCatalogue())
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.saveCatalogue(entries, checked: date)
        let cached = try XCTUnwrap(store.cachedCatalogue())
        XCTAssertEqual(cached.entries, entries)
        XCTAssertEqual(cached.checked, date)
    }

    // MARK: Store

    func zipOf(version: String, release: String, minimumLauncher: String = "0.2.15", change: ((URL) throws -> Void)? = nil) throws -> URL {
        let source = scratch.appendingPathComponent("src-\(UUID().uuidString)")
        let folder = try FakeToolkit.make(in: source, name: "AnyPS5-toolkit-macos-\(release)", version: version, minimumLauncher: minimumLauncher)
        try change?(folder)
        let zip = scratch.appendingPathComponent("AnyPS5-toolkit-macos-\(release)-\(UUID().uuidString).zip")
        try FakeToolkit.zip(folder, to: zip)
        return zip
    }

    func testAVerifiedDownloadIsInstalledUnderItsVersion() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm")
        let installed = try store.install(zip: zip, digest: FakeToolkit.sha256(zip), release: "0.2.16-arm", launcherVersion: "0.2.16-arm")
        XCTAssertEqual(installed.version, "0.2.16-arm-0123456789ab")
        XCTAssertEqual(installed.folder.lastPathComponent, "0.2.16-arm-0123456789ab")
        XCTAssertNil(Toolkit.layoutProblem(at: installed.folder))
        XCTAssertEqual(store.installed().map(\.version), ["0.2.16-arm-0123456789ab"])
        XCTAssertNotNil(try store.verifiedToolkit(version: "0.2.16-arm-0123456789ab"))
        // Nothing of the unpacking stays behind (.verified holds the notes of the checks).
        let left = try FileManager.default.contentsOfDirectory(atPath: store.folder.path).filter { $0 != "0.2.16-arm-0123456789ab" && $0 != ".verified" }
        XCTAssertEqual(left, [])
    }

    func testADownloadThatDoesNotMatchItsReleaseDigestIsRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm")
        XCTAssertThrowsError(try store.install(zip: zip, digest: String(repeating: "0", count: 64), release: "0.2.16-arm", launcherVersion: "0.2.16-arm"))
        XCTAssertEqual(store.installed().count, 0)
    }

    func testADownloadWhoseFilesDoNotMatchItsManifestIsRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm") { folder in
            try Data("tampered".utf8).write(to: folder.appendingPathComponent("libs/libSceAgc.prx"))
        }
        XCTAssertThrowsError(try store.install(zip: zip, digest: nil, release: "0.2.16-arm", launcherVersion: "0.2.16-arm"))
        XCTAssertEqual(store.installed().count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.folder.path), [])
    }

    func testADownloadOfAnotherReleaseThanItsNameIsRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.10-arm-0123456789ab", release: "0.2.16-arm")
        XCTAssertThrowsError(try store.install(zip: zip, digest: nil, release: "0.2.16-arm", launcherVersion: "0.2.16-arm"))
    }

    func testAToolkitForANewerLauncherIsRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.3.0-arm-0123456789ab", release: "0.3.0-arm", minimumLauncher: "0.3.0")
        XCTAssertThrowsError(try store.install(zip: zip, digest: nil, release: "0.3.0-arm", launcherVersion: "0.2.16-arm")) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("0.3.0"), "\(error.localizedDescription)")
        }
    }

    func testADownloadWithALinkIsRefused() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm") { folder in
            try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("libs/libSceLink.prx").path, withDestinationPath: "/etc")
        }
        XCTAssertThrowsError(try store.install(zip: zip, digest: nil, release: "0.2.16-arm", launcherVersion: "0.2.16-arm"))
    }

    func testAnInstalledToolkitChangedLaterIsNotUsed() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm")
        let installed = try store.install(zip: zip, digest: nil, release: "0.2.16-arm", launcherVersion: "dev")
        try Data("#!/bin/sh\necho other\n".utf8).write(to: installed.folder.appendingPathComponent("relinker"))
        XCTAssertThrowsError(try store.verifiedToolkit(version: installed.version))
    }

    func testSeveralToolkitsAreKeptAndUnusedOnesRemoved() throws {
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        for release in ["0.2.15-arm", "0.2.16-arm", "0.2.17-arm"] {
            _ = try store.install(zip: zipOf(version: "\(release)-0123456789ab", release: release), digest: nil, release: release, launcherVersion: "dev")
        }
        XCTAssertEqual(Set(store.installed().map(\.version)), ["0.2.15-arm-0123456789ab", "0.2.16-arm-0123456789ab", "0.2.17-arm-0123456789ab"])
        let removed = store.removeUnused(keeping: ["0.2.16-arm-0123456789ab"])
        XCTAssertEqual(Set(removed), ["0.2.15-arm-0123456789ab", "0.2.17-arm-0123456789ab"])
        XCTAssertEqual(store.installed().map(\.version), ["0.2.16-arm-0123456789ab"])
        try store.remove(version: "0.2.16-arm-0123456789ab")
        XCTAssertEqual(store.installed().count, 0)
        XCTAssertThrowsError(try store.remove(version: "../Themes"))
    }

    func testTheCatalogueEntryIsDownloadedWithProgress() async throws {
        let zip = try zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm")
        let body = try Data(contentsOf: zip)
        let server = try SlowServer(body: body)
        defer { server.listener.cancel() }
        let entry = EngineCatalogue.Entry(release: "0.2.16-arm", tag: "v0.2.16-arm", title: "AnyPS5-ARM 0.2.16", summary: "", date: nil,
                                          page: URL(string: "https://example.com")!, download: server.url, size: body.count,
                                          digest: try FakeToolkit.sha256(zip), prerelease: false)
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let seen = Locked<[Double]>([])
        // 0.2.16 came out before releases were signed: downloaded on the user's OK, checked with GitHub's sha256.
        let installed = try await store.download(entry, launcherVersion: "0.2.16-arm", allowUnsigned: true) { seen.value.append($0) }
        XCTAssertEqual(installed.version, "0.2.16-arm-0123456789ab")
        XCTAssertEqual(seen.value.last, 1)
        XCTAssertEqual(store.installed(release: "0.2.16-arm")?.version, "0.2.16-arm-0123456789ab")
    }

    // MARK: Choosing

    func testTheGameChoiceWinsOverTheDefault() {
        XCTAssertEqual(EngineChoice.resolve(game: nil, default: nil), .builtIn)
        XCTAssertEqual(EngineChoice.resolve(game: nil, default: "0.2.16-arm-0123456789ab"), .downloaded("0.2.16-arm-0123456789ab"))
        XCTAssertEqual(EngineChoice.resolve(game: "builtin", default: "0.2.16-arm-0123456789ab"), .builtIn)
        XCTAssertEqual(EngineChoice.resolve(game: "custom", default: nil), .custom)
        XCTAssertEqual(EngineChoice.resolve(game: "0.2.15-arm-0123456789ab", default: "custom"), .downloaded("0.2.15-arm-0123456789ab"))
        for choice in [EngineChoice.builtIn, .custom, .downloaded("0.2.15-arm-0123456789ab")] {
            XCTAssertEqual(EngineChoice(stored: choice.stored), choice)
        }
        XCTAssertNil(EngineChoice.builtIn.stored)
    }

    func testAMissingChoiceFallsBackToTheBuiltInToolkit() throws {
        let builtIn = Toolkit(root: try FakeToolkit.make(in: scratch, name: "builtin", version: "0.2.15-arm-aaaaaaaaaaaa", manifest: false))
        let custom = Toolkit(root: try FakeToolkit.make(in: scratch, name: "custom", version: "local-bbbbbbbbbbbb", manifest: false))
        let store = ToolkitStore(folder: scratch.appendingPathComponent("Toolkits"))
        let installed = try store.install(zip: zipOf(version: "0.2.16-arm-0123456789ab", release: "0.2.16-arm"), digest: nil, release: "0.2.16-arm", launcherVersion: "dev")
        XCTAssertEqual(EngineChoice.builtIn.toolkit(builtIn: builtIn, custom: custom, store: store)?.version, "0.2.15-arm-aaaaaaaaaaaa")
        XCTAssertEqual(EngineChoice.custom.toolkit(builtIn: builtIn, custom: custom, store: store)?.version, "local-bbbbbbbbbbbb")
        XCTAssertEqual(EngineChoice.custom.toolkit(builtIn: builtIn, custom: nil, store: store)?.version, "0.2.15-arm-aaaaaaaaaaaa")
        XCTAssertEqual(EngineChoice.downloaded(installed.version).toolkit(builtIn: builtIn, custom: custom, store: store)?.version, installed.version)
        XCTAssertEqual(EngineChoice.downloaded("0.1.0-arm-cccccccccccc").toolkit(builtIn: builtIn, custom: custom, store: store)?.version, "0.2.15-arm-aaaaaaaaaaaa")
    }

    func testAGameSettingSavedBeforeTheEngineChoiceStillDecodes() throws {
        let old = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"fullscreen":true,"windowSize":75,"vsync":true,"overlay":"off"}"#.utf8))
        XCTAssertNil(old.engine)
        var settings = GameSettings()
        settings.engine = "0.2.16-arm-0123456789ab"
        XCTAssertEqual(try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(settings)).engine, "0.2.16-arm-0123456789ab")
        XCTAssertNil(settings.environment(launcherLanguage: 1)["ANYPS5_ENGINE"])
    }
}
