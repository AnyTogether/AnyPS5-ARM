import CryptoKit
@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// The recorded host releases the launcher's tests publish on the fake GitHub: the 1.0.0 release
/// (AnyPS5CoreTests/Fixtures/RetroHostRelease) and the 1.1.0 release with its LRPS2 package
/// (Fixtures/RetroHostReleaseLrps2), each optionally named for another version and signed again by
/// the fixture's throwaway key, as the host repository would publish a newer release of them.
enum RetroHostTestRelease {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../AnyPS5CoreTests/Fixtures/RetroHostRelease").standardized
    static let lrps2Folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../AnyPS5CoreTests/Fixtures/RetroHostReleaseLrps2").standardized

    static func files(version: String? = nil, ps2: Bool = false) throws -> [String: Data] {
        let source = ps2 ? lrps2Folder : folder
        let recorded = ps2 ? "1.1.0" : "1.0.0"
        let version = version ?? recorded
        let sums = try Data(contentsOf: source.appendingPathComponent(ReleaseSigning.sumsName))
        var files: [String: Data] = [:]
        for name in try ReleaseSigning.parseSums(sums).keys {
            files[name.replacingOccurrences(of: "anyps5-retro-host-\(recorded)-", with: "anyps5-retro-host-\(version)-")] =
                try Data(contentsOf: source.appendingPathComponent(name))
        }
        guard version != recorded else {
            files[ReleaseSigning.sumsName] = sums
            files[ReleaseSigning.signatureName] = try Data(contentsOf: source.appendingPathComponent(ReleaseSigning.signatureName))
            return files
        }
        let signed = Data(files.keys.sorted().map { "\(RetroHostRelease.sha256(files[$0]!))  \($0)\n" }.joined().utf8)
        files[ReleaseSigning.sumsName] = signed
        files[ReleaseSigning.signatureName] = try signature(signed)
        return files
    }

    /// SHA256SUMS.sig for `sums`, signed by the fixture key: the last 32 bytes of its PKCS #8 form
    /// are the Ed25519 seed.
    private static func signature(_ sums: Data) throws -> Data {
        let text = try String(contentsOf: folder.appendingPathComponent("test-release-signing.key"), encoding: .utf8)
        let body = text.components(separatedBy: "-----BEGIN PRIVATE KEY-----").last?
            .components(separatedBy: "-----END PRIVATE KEY-----").first?.filter { !$0.isWhitespace } ?? ""
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: try XCTUnwrap(Data(base64Encoded: body)).suffix(32))
        let id = ReleaseSigning.keyID(of: key.publicKey.rawRepresentation)
        return Data("ed25519 \(id) \(try key.signature(for: sums).base64EncodedString())\n".utf8)
    }
}

extension RetroHostTestGitHub {
    /// `releases` (tag and files, newest first) as the fake GitHub's whole list.
    static func publish(_ releases: [(tag: String, files: [String: Data])]) throws {
        var list: [[String: Any]] = []
        for release in releases {
            var assets: [[String: Any]] = []
            for name in release.files.keys.sorted() {
                let url = "https://github.example/\(release.tag)/\(name)"
                let data = release.files[name]!
                RetroHostTestGitHub.store(data, at: url)
                assets.append(["name": name, "browser_download_url": url, "size": data.count])
            }
            list.append(["tag_name": release.tag, "prerelease": false, "draft": false, "assets": assets])
        }
        RetroHostTestGitHub.store(try JSONSerialization.data(withJSONObject: list),
                                  at: "https://api.github.example/repos/\(RetroHostStore.repository)/releases?per_page=100")
    }

    /// The names of the files asked for after the first `seen` requests.
    static func fetched(since seen: Int) -> [String] {
        requests.dropFirst(seen).compactMap { URL(string: $0)?.lastPathComponent }.filter { $0.hasPrefix("anyps5-") }
    }
}

/// The releases a launcher under test reads, held back while `hold` is closed: a game can start
/// while a download looks for its release.
final class ReleaseHold: @unchecked Sendable {
    private let lock = NSLock()
    private var gate: PlayGate?
    var next: PlayGate? {
        get { lock.withLock { gate } }
        set { lock.withLock { gate = newValue } }
    }
}

/// The PS2 emulator, LRPS2, as a download of its own beside the signed host, as on Windows and
/// Linux (AnyPS5 Desktop's test/ui/retro_host_ps2_test.dart, "the signed release"): no PS2 rows on
/// 1.0.0, the offer right under the host's row on 1.1.0, added, moved with an update and gone with
/// a release without it, removed again, and neither added nor removed while a game plays.
@MainActor
final class RetroHostPs2DownloadTests: XCTestCase {
    private var made: [URL] = []

    override func setUp() { RetroHostTestGitHub.reset() }

    override func tearDown() {
        for url in made { try? FileManager.default.removeItem(at: url) }
        made = []
        RetroHostTestGitHub.reset()
    }

    private enum Installed { case none, release100, lrps2Host, lrps2 }

    private struct Launcher {
        let model: AppModel
        let ps1: Game
        let opened: () -> [(FakePlayHost, RetroHostChecked?)]
        let hold: ReleaseHold
    }

    private func write(_ data: Data, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A launcher with a PS1 disc, a PS2 disc and a PS2 cue sheet (Cue Racer), the host releases
    /// read from the fake GitHub, and in its storage the host `installed` says.
    private func launcher(_ installed: Installed) async throws -> Launcher {
        let model = try LauncherFixture.model(games: 1)
        made.append(contentsOf: model.libraryRoots)
        let root = try XCTUnwrap(model.libraryRoots.first)
        try write(Data(), root.appendingPathComponent("Night Racer/game.cue"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps1", "titleId": "SLUS00001", "name": "Night Racer", "disc": "game.cue"]),
                  root.appendingPathComponent("Night Racer/retro.json"))
        try write(Data(), root.appendingPathComponent("Street Kings/game.iso"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps2", "titleId": "SLUS20001", "name": "Street Kings", "disc": "game.iso"]),
                  root.appendingPathComponent("Street Kings/retro.json"))
        try write(Data(count: 16), root.appendingPathComponent("PS2/Cue Racer.bin"))
        try write(Data("FILE \"Cue Racer.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), root.appendingPathComponent("PS2/Cue Racer.cue"))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-ps2-\(UUID().uuidString)")
        made.append(scratch)
        model.retroHostRoot = scratch.appendingPathComponent("RetroHost")
        model.retroFolder = scratch.appendingPathComponent("retro")
        model.retroHostKeys = RetroHostTestGitHub.keys
        model.retroHostSession = RetroHostTestGitHub.configuration
        let hold = ReleaseHold()
        model.retroHostReleases = {
            if let gate = hold.next { await gate.wait() }
            return try await RetroHostStore.releases(session: URLSession(configuration: RetroHostTestGitHub.configuration), api: RetroHostTestGitHub.api)
        }
        model.retroHostUnchecked = nil
        model.retroStatusEvery = .seconds(3600)
        model.retroPads = RetroPadReader(pads: { [] }, state: { _ in nil })
        let host = model.retroHostRoot.appendingPathComponent("host")
        switch installed {
        case .none:
            break
        case .release100:
            _ = try await RetroHostRelease.install(RetroHostTestRelease.folder, into: host, tag: "v1.0.0", keys: RetroHostTestGitHub.keys,
                                                   system: .macosArm64)
        case .lrps2Host, .lrps2:
            _ = try await RetroHostRelease.install(RetroHostTestRelease.lrps2Folder, into: host, tag: "v1.1.0", keys: RetroHostTestGitHub.keys,
                                                   system: .macosArm64, cores: installed == .lrps2 ? [.lrps2] : [])
        }
        if installed != .none { model.preferences.retroHostPs1 = true }
        model.setRetroLibrary(true)
        let ps1 = try XCTUnwrap(model.games.first { $0.retro?.platform == .ps1 })
        var opened: [(FakePlayHost, RetroHostChecked?)] = []
        model.openRetroHost = { _, checked, _, _ in
            let fake = FakePlayHost()
            fake.canPlayPs2 = true
            opened.append((fake, checked))
            return fake
        }
        return Launcher(model: model, ps1: ps1, opened: { opened }, hold: hold)
    }

    private func row(_ model: AppModel, _ id: String) -> PanelRow? { model.standaloneEmulatorSettings().rows.first { $0.id == id } }

    private func select(_ row: PanelRow?) throws {
        guard case .action(_, let run) = try XCTUnwrap(row).kind else { return XCTFail("no action") }
        run()
    }

    private func settle(_ condition: () -> Bool, _ message: String = "") async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
    }

    private func lists(_ model: AppModel, _ file: String) -> Bool {
        model.games.contains { $0.retro?.path.lastPathComponent == file }
    }

    private func downloadHost(_ model: AppModel) async throws {
        model.retroHostDownload.download()
        try await settle({ !model.retroHostDownload.downloading }, "the host downloaded")
    }

    private func addPs2(_ model: AppModel) async throws {
        model.retroHostDownload.ps2.add()
        try await settle({ !model.retroHostDownload.ps2.downloading }, "the PS2 emulator added")
    }

    /// The PS1 disc as the library lists it now.
    private func ps1(_ model: AppModel) throws -> Game { try XCTUnwrap(model.games.first { $0.retro?.platform == .ps1 }) }

    /// Starts the PS1 disc and waits for its first status.
    private func startPs1(_ launcher: Launcher) async throws -> FakePlayHost {
        let before = launcher.opened().count
        let game = try ps1(launcher.model)
        launcher.model.selected = try XCTUnwrap(launcher.model.games.firstIndex(of: game))
        launcher.model.play(game)
        try await settle({ launcher.opened().count > before && launcher.opened().last?.0.started.isEmpty == false }, "the game starts")
        try await settle({ launcher.model.retroPlay?.host.loaded == true && launcher.model.retroPlay?.host.status != nil }, "its first status in")
        return try XCTUnwrap(launcher.opened().last?.0)
    }

    /// A PS2 BIOS, memory card and save state, which neither Remove nor an update may touch.
    private func keptFiles(_ model: AppModel) throws -> [URL] {
        let ps2 = try XCTUnwrap(model.games.first { $0.retro?.platform == .ps2 })
        var kept: [URL] = []
        for (folder, name) in [(model.retroPs2BiosFolder, "kept-bios.bin"), (model.retroPs2SavesFolder, "kept-card.ps2"),
                               (model.retroStatesFolder(ps2, ps2: true), "kept.state")] {
            let file = folder.appendingPathComponent(name)
            try write(Data(name.utf8), file)
            kept.append(file)
        }
        return kept
    }

    private func assertKept(_ files: [URL]) {
        for file in files { XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), file.lastPathComponent, file.path) }
    }

    // MARK: The signed release

    func test100WithoutAnLrps2PackageShowsNoPs2RowsAndIsCheckedForSwanStationAlone() async throws {
        let launcher = try await launcher(.release100)
        let model = launcher.model
        model.setRetroHostPs2(true)
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        for id in ["retro-host-ps2-download", "retro-host-ps2", "retro-host-ps2-bios", "retro-host-ps2-remove"] {
            XCTAssertNil(row(model, id), id)
        }
        let checked = try await model.retroHostDownload.store.check()
        defer { checked.release() }
        XCTAssertNil(checked.ps2Core)
    }

    func testOneWithLrps2PlaysAPs2DiscOnItsCheckedLrps2() async throws {
        let launcher = try await launcher(.lrps2)
        let model = launcher.model
        model.setRetroHostPs2(true)
        let install = try XCTUnwrap(model.retroHostInstall)
        XCTAssertTrue(install.checked)
        XCTAssertEqual(install.ps2Core, model.retroHostRoot.appendingPathComponent("host/pcsx2_libretro.dylib").path)
        XCTAssertNotNil(row(model, "retro-host-ps2"))
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.title, "PS2 emulator 1.1.0")
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.detail,
                       "Signed, and checked before every game. It updates with the PS1 emulator. Select to look for an update.")
        XCTAssertNotNil(row(model, "retro-host-ps2-remove"))
        let game = try XCTUnwrap(model.games.first { $0.retro?.platform == .ps2 })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        model.play(game)
        try await settle({ launcher.opened().first?.0.started.isEmpty == false }, "the PS2 game starts")
        let (fake, check) = try XCTUnwrap(launcher.opened().first)
        let checked = try XCTUnwrap(check)
        XCTAssertTrue(checked.held)
        XCTAssertEqual(checked.ps2Core, install.ps2Core)
        XCTAssertEqual(fake.started.first?.objectValue?["core"], .string(try XCTUnwrap(install.ps2Core)))
        XCTAssertEqual(fake.started.first?.objectValue?["console"], .string("ps2"))
        XCTAssertEqual(model.retroPlay?.unchecked, false)
    }

    func testOneWhoseLrps2WasChangedFailsItsCheckForAPs1GameToo() async throws {
        let launcher = try await launcher(.lrps2)
        let model = launcher.model
        model.setRetroHostPs2(true)
        try Data("changed".utf8).write(to: URL(fileURLWithPath: try XCTUnwrap(model.retroHostInstall?.ps2Core)))
        let game = try ps1(model)
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        model.play(game)
        try await settle({ model.toast != nil }, "the player is told")
        XCTAssertEqual(model.toast?.text, "The PS1 emulator did not pass its check. Download it again in Settings › Emulators")
        XCTAssertTrue(launcher.opened().isEmpty)
    }

    func testOneWhoseLrps2PackageIsNotAddedOffersItBesideTheHostAndShowsNoOtherPs2Row() async throws {
        let launcher = try await launcher(.lrps2Host)
        let model = launcher.model
        model.setRetroHostPs2(true)
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        let ids = model.standaloneEmulatorSettings().rows.map(\.id)
        XCTAssertEqual(ids.firstIndex(of: "retro-host-ps2-download"), ids.firstIndex(of: "retro-host-download").map { $0 + 1 })
        let offer = try XCTUnwrap(row(model, "retro-host-ps2-download"))
        XCTAssertEqual(offer.title, "Download the PS2 emulator")
        XCTAssertEqual(offer.detail, "Plays PS2 games in this window with LRPS2. It comes from the same signed release as the PS1 emulator, updates with it and is checked before every game. Nothing downloads until you select this.")
        for id in ["retro-host-ps2", "retro-host-ps2-bios", "retro-host-ps2-remove"] {
            XCTAssertNil(row(model, id), id)
        }
        XCTAssertFalse(model.playsInHost(.ps2))
        XCTAssertTrue(RetroHostTestGitHub.requests.isEmpty, "nothing downloaded unasked")
    }

    // MARK: Downloaded

    func testThePs2EmulatorIsAddedOnItsOwnMovesWithTheHostAndGoesWithAReleaseWithoutIt() async throws {
        var published: [(tag: String, files: [String: Data])] = [("v1.1.0", try RetroHostTestRelease.files(ps2: true))]
        try RetroHostTestGitHub.publish(published)
        let launcher = try await launcher(.none)
        let model = launcher.model
        XCTAssertNil(row(model, "retro-host-ps2-download"), "no host yet")

        try await downloadHost(model)
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.1.0 is ready")
        XCTAssertTrue(RetroHostTestGitHub.fetched(since: 0).filter { $0.contains("lrps2") }.isEmpty, "never downloaded unasked")
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        XCTAssertFalse(lists(model, "Cue Racer.cue"))

        var seen = RetroHostTestGitHub.requests.count
        try await addPs2(model)
        XCTAssertEqual(model.toast?.text, "PS2 emulator 1.1.0 is ready")
        XCTAssertEqual(Set(RetroHostTestGitHub.fetched(since: seen)),
                       ["anyps5-retro-host-1.1.0-macos-arm64-lrps2.files", "anyps5-retro-host-1.1.0-macos-arm64-lrps2.zip"])
        XCTAssertEqual(model.preferences.retroHostPs2, true, "the first PS2 emulator turns its games on")
        XCTAssertTrue(model.playsInHost(.ps2))
        XCTAssertTrue(lists(model, "Cue Racer.cue"), "scanned again once the host gained LRPS2")
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.detail,
                       "Signed, and checked before every game. It updates with the PS1 emulator. Select to look for an update.")
        for id in ["retro-host-ps2", "retro-host-ps2-bios", "retro-host-ps2-remove"] {
            XCTAssertNotNil(row(model, id), id)
        }

        published.insert(("v1.1.1", try RetroHostTestRelease.files(version: "1.1.1", ps2: true)), at: 0)
        try RetroHostTestGitHub.publish(published)
        seen = RetroHostTestGitHub.requests.count
        try await downloadHost(model)
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.1.1 is ready")
        XCTAssertTrue(RetroHostTestGitHub.fetched(since: seen).contains("anyps5-retro-host-1.1.1-macos-arm64-lrps2.zip"))
        XCTAssertEqual(model.retroHostDownload.installedCores, [.lrps2])
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.title, "PS2 emulator 1.1.1")
        try await model.retroHostDownload.store.check().release()

        let kept = try keptFiles(model)
        published.insert(("v1.2.0", try RetroHostTestRelease.files(version: "1.2.0")), at: 0)
        try RetroHostTestGitHub.publish(published)
        try await downloadHost(model)
        XCTAssertEqual(model.toast?.text,
                       "PS1 emulator 1.2.0 is ready. This release has no PS2 emulator, so it was removed. Your PS2 BIOS, memory cards and save states stay.",
                       "the player is told why")
        assertKept(kept)
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        XCTAssertNil(row(model, "retro-host-ps2-download"), "the new release has no PS2 emulator")
        XCTAssertEqual(model.preferences.retroHostPs2, true, "the setting is kept for a later host")
        XCTAssertFalse(lists(model, "Cue Racer.cue"), "scanned again once the host lost LRPS2")
    }

    func testThePs2EmulatorIsRemovedAgainAndPs1GamesStillPlay() async throws {
        try RetroHostTestGitHub.publish([("v1.1.0", try RetroHostTestRelease.files(ps2: true))])
        let launcher = try await launcher(.none)
        let model = launcher.model
        try await downloadHost(model)
        try await addPs2(model)
        let ps2Core = try XCTUnwrap(model.retroHostInstall?.ps2Core)
        let kept = try keptFiles(model)
        model.retroHostDownload.installing = true
        XCTAssertNil(row(model, "retro-host-ps2-remove"), "Remove would do nothing while the host is put in place")
        model.retroHostDownload.installing = false

        let remove = try XCTUnwrap(row(model, "retro-host-ps2-remove"))
        XCTAssertEqual(remove.title, "Remove the PS2 emulator")
        XCTAssertEqual(remove.detail, "Deletes LRPS2. Your PS2 BIOS, memory cards and save states stay.")
        try select(remove)
        try await settle({ model.toast?.text == "The PS2 emulator was removed" }, "removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ps2Core))
        assertKept(kept)
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        XCTAssertFalse(lists(model, "Cue Racer.cue"))
        for id in ["retro-host-ps2", "retro-host-ps2-bios", "retro-host-ps2-remove"] {
            XCTAssertNil(row(model, id), id)
        }
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.title, "Download the PS2 emulator", "offered again")

        _ = try await startPs1(launcher)
        XCTAssertNil(try XCTUnwrap(launcher.opened().last?.1).ps2Core)
    }

    func testThePs2EmulatorIsNotAddedWhileAGamePlays() async throws {
        try RetroHostTestGitHub.publish([("v1.1.0", try RetroHostTestRelease.files(ps2: true))])
        let launcher = try await launcher(.none)
        let model = launcher.model
        try await downloadHost(model)
        _ = try await startPs1(launcher)
        let seen = RetroHostTestGitHub.requests.count
        model.retroHostDownload.ps2.add()
        XCTAssertFalse(model.retroHostDownload.ps2.downloading)
        XCTAssertEqual(model.toast?.text, "Close the game first, then add or remove the PS2 emulator")
        XCTAssertEqual(RetroHostTestGitHub.requests.count, seen)
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        await model.closeRetroGame()
    }

    func testThePs2EmulatorIsNotRemovedWhileAGamePlays() async throws {
        try RetroHostTestGitHub.publish([("v1.1.0", try RetroHostTestRelease.files(ps2: true))])
        let launcher = try await launcher(.none)
        let model = launcher.model
        try await downloadHost(model)
        try await addPs2(model)
        let ps2Core = try XCTUnwrap(model.retroHostInstall?.ps2Core)
        _ = try await startPs1(launcher)
        XCTAssertNil(model.retroHostDownload.ps2.remove())
        XCTAssertEqual(model.toast?.text, "Close the game first, then add or remove the PS2 emulator")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ps2Core))
        await model.closeRetroGame()
    }

    func testNoGameStartsWhileTheKeptHostShutsDownForRemoveAndTheRowIsHiddenMeanwhile() async throws {
        try RetroHostTestGitHub.publish([("v1.1.0", try RetroHostTestRelease.files(ps2: true))])
        let launcher = try await launcher(.none)
        let model = launcher.model
        try await downloadHost(model)
        try await addPs2(model)
        let ps2Core = try XCTUnwrap(model.retroHostInstall?.ps2Core)
        let fake = try await startPs1(launcher)
        fake.gameStatus = try RetroHostPlayTests.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertTrue(model.retroHostKeeper.holding)
        fake.exitsOnShutdown = false
        let removing = try XCTUnwrap(model.retroHostDownload.ps2.remove())
        try await settle({ fake.shutdowns == 1 }, "the kept host is asked to shut down")
        XCTAssertNil(row(model, "retro-host-ps2-remove"), "nothing to select while the host changes")

        model.play(try ps1(model))
        XCTAssertEqual(model.toast?.text, "The PS1 emulator is being updated. Try again in a moment")
        XCTAssertEqual(launcher.opened().count, 1, "no new host started")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ps2Core), "still waiting for the kept host")

        fake.finish(.clean)
        await removing.value
        XCTAssertEqual(model.toast?.text, "The PS2 emulator was removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ps2Core))
    }

    func testAGameStartedWhileThePs2EmulatorDownloadsKeepsItFromBeingAdded() async throws {
        try RetroHostTestGitHub.publish([("v1.1.0", try RetroHostTestRelease.files(ps2: true))])
        let launcher = try await launcher(.none)
        let model = launcher.model
        try await downloadHost(model)
        let gate = PlayGate()
        launcher.hold.next = gate
        model.retroHostDownload.ps2.add()
        XCTAssertTrue(model.retroHostDownload.ps2.downloading)
        _ = try await startPs1(launcher)
        XCTAssertEqual(launcher.opened().count, 1, "a game may start while the package only downloads")
        gate.open()
        try await settle({ !model.retroHostDownload.ps2.downloading }, "the download ends")
        XCTAssertEqual(model.toast?.text,
                       "The PS2 emulator could not be downloaded: Close the game first, then add or remove the PS2 emulator",
                       "checked again once the download is done")
        XCTAssertNil(model.retroHostInstall?.ps2Core)
        XCTAssertFalse(model.retroHostDownload.installing)
        await model.closeRetroGame()
    }

    func testWithoutTheReleaseOfItsHostOnGitHubThePs2EmulatorIsNotAvailable() async throws {
        let launcher = try await launcher(.lrps2Host)
        let model = launcher.model
        try RetroHostTestGitHub.publish([("v1.1.1", try RetroHostTestRelease.files(version: "1.1.1", ps2: true))])
        try await addPs2(model)
        XCTAssertEqual(model.toast?.text, "The PS2 emulator for this version was not found. Update the PS1 emulator, then try again.")
        XCTAssertEqual(row(model, "retro-host-ps2-download")?.detail,
                       "The PS2 emulator for this version was not found. Update the PS1 emulator, then try again.")
        XCTAssertNil(model.retroHostInstall?.ps2Core)
    }
}
