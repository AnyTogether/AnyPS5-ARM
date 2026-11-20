@testable import AnyPS5
@testable import AnyPS5Core
import XCTest

/// A PS1 disc played the release way, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host_release_play_test.dart): the recorded signed release
/// (AnyPS5CoreTests/Fixtures/RetroHostRelease) installed in the launcher's own storage and no
/// unchecked host. The host is started with a check whose files are still held, a host whose file
/// changed is not started and is offered again, a kept host is checked again before its next game,
/// nothing starts while a download puts a new host in place, a download first shuts the kept host
/// down, and the first host downloaded turns PS1 games in the host on.
@MainActor
final class RetroHostReleasePlayTests: XCTestCase {
    private var made: [URL] = []
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../AnyPS5CoreTests/Fixtures/RetroHostRelease").standardized

    override func setUp() { RetroHostTestGitHub.reset() }

    override func tearDown() {
        for url in made { try? FileManager.default.removeItem(at: url) }
        made = []
        RetroHostTestGitHub.reset()
    }

    private func write(_ data: Data, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A launcher with one PS1 disc and, with `installed`, the signed release in its storage; the
    /// fake hosts it opens and the checks it opened them with.
    private func launcher(installed: Bool = true) async throws -> (AppModel, Game, () -> [(FakePlayHost, RetroHostChecked?)]) {
        let model = try LauncherFixture.model(games: 1)
        made.append(contentsOf: model.libraryRoots)
        let root = try XCTUnwrap(model.libraryRoots.first)
        let folder = root.appendingPathComponent("Night Racer")
        try write(Data(), folder.appendingPathComponent("game.cue"))
        try write(try JSONSerialization.data(withJSONObject: ["platform": "ps1", "titleId": "SLUS00001", "name": "Night Racer", "disc": "game.cue"]),
                  folder.appendingPathComponent("retro.json"))
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-release-\(UUID().uuidString)")
        made.append(scratch)
        model.retroHostRoot = scratch.appendingPathComponent("RetroHost")
        model.retroFolder = scratch.appendingPathComponent("retro")
        model.retroHostKeys = RetroHostTestGitHub.keys
        model.retroHostSession = RetroHostTestGitHub.configuration
        model.retroHostReleases = {
            try await RetroHostStore.releases(session: URLSession(configuration: RetroHostTestGitHub.configuration), api: RetroHostTestGitHub.api)
        }
        model.retroHostUnchecked = nil
        model.retroStatusEvery = .seconds(3600)
        model.retroPads = RetroPadReader(pads: { [] }, state: { _ in nil })
        if installed {
            _ = try await RetroHostRelease.install(Self.fixture, into: model.retroHostRoot.appendingPathComponent("host"), tag: "v1.0.0",
                                                   keys: RetroHostTestGitHub.keys, system: .macosArm64)
            model.preferences.retroHostPs1 = true
        }
        model.setRetroLibrary(true)
        let game = try XCTUnwrap(model.games.first { $0.retro != nil })
        model.selected = try XCTUnwrap(model.games.firstIndex(of: game))
        var opened: [(FakePlayHost, RetroHostChecked?)] = []
        model.openRetroHost = { _, checked, _, _ in
            let fake = FakePlayHost()
            opened.append((fake, checked))
            return fake
        }
        return (model, game, { opened })
    }

    private func settle(_ condition: () -> Bool, _ message: String = "") async throws {
        for _ in 0..<300 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), message)
    }

    /// Waits for the first `status` the game's start asks: a `refresh()` asked while it is out is
    /// let go (`RetroHostGame.refresh`), so the status a test sets would not be taken.
    private func loaded(_ model: AppModel) async throws {
        try await settle({ model.retroPlay?.host.loaded == true && model.retroPlay?.host.status != nil }, "the game is loading, its first status in")
    }

    func testTheSignedHostStartsWithACheckWhoseFilesAreHeldAndItsOwnSwanStation() async throws {
        let (model, game, opened) = try await launcher()
        let folder = model.retroHostRoot.appendingPathComponent("host")
        let install = try XCTUnwrap(model.retroHostInstall)
        XCTAssertTrue(install.checked)
        XCTAssertEqual(install.host, folder.appendingPathComponent("anyps5-retro-host").path)
        model.play(game)
        try await settle({ opened().first?.0.started.isEmpty == false }, "the game starts")
        let (fake, check) = try XCTUnwrap(opened().first)
        let checked = try XCTUnwrap(check, "a signed host is started through its check")
        XCTAssertTrue(checked.held, "its files stay held while the host runs")
        XCTAssertEqual(checked.executable, folder.appendingPathComponent("anyps5-retro-host").path)
        XCTAssertEqual(fake.started.first?.objectValue?["core"], .string(folder.appendingPathComponent("swanstation_libretro.dylib").path),
                       "only the release's SwanStation")
        XCTAssertEqual(model.retroPlay?.unchecked, false, "a checked host's game is not marked unchecked")
    }

    func testAHostWhoseFileChangedIsNotStartedAndIsOfferedAgain() async throws {
        let (model, game, opened) = try await launcher()
        try Data("changed".utf8).write(to: model.retroHostRoot.appendingPathComponent("host/swanstation_libretro.dylib"))
        model.play(game)
        try await settle({ model.toast != nil }, "the player is told")
        XCTAssertEqual(model.toast?.text, "The PS1 emulator did not pass its check. Download it again in Settings › Emulators")
        XCTAssertTrue(opened().isEmpty, "no host started")
        XCTAssertNil(model.retroPlay)
        let row = try XCTUnwrap(model.standaloneEmulatorSettings().rows.first { $0.id == "retro-host-download" })
        XCTAssertEqual(row.title, "Download the PS1 emulator")
        XCTAssertEqual(row.detail, "Its files did not pass their check before the last game. Select to download it again.")
    }

    func testAKeptHostIsCheckedAgainBeforeItsNextGameAndShutDownWhenItsCoreChanged() async throws {
        let (model, game, opened) = try await launcher()
        model.play(game)
        try await settle({ opened().first?.0.started.isEmpty == false })
        try await loaded(model)
        let (fake, _) = try XCTUnwrap(opened().first)
        fake.gameStatus = try RetroHostPlayTests.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertTrue(model.retroHostKeeper.holding)

        // Whole, it plays the next game after a second check.
        model.play(game)
        try await settle({ fake.started.count == 2 }, "the kept host plays the next game")
        try await loaded(model)
        XCTAssertEqual(opened().count, 1)
        fake.gameStatus = try RetroHostPlayTests.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertTrue(model.retroHostKeeper.holding)

        // Its core changed: it is shut down, and nothing starts.
        try Data("changed".utf8).write(to: model.retroHostRoot.appendingPathComponent("host/swanstation_libretro.dylib"))
        model.play(game)
        try await settle({ fake.shutdowns == 1 }, "the kept host is shut down")
        XCTAssertEqual(fake.started.count, 2)
        XCTAssertEqual(opened().count, 1)
        XCTAssertEqual(model.toast?.text, "The PS1 emulator did not pass its check. Download it again in Settings › Emulators")
    }

    func testNothingStartsWhileADownloadPutsANewHostInPlace() async throws {
        let (model, game, opened) = try await launcher()
        model.retroHostDownload.installing = true
        model.play(game)
        XCTAssertEqual(model.toast?.text, "The PS1 emulator is being updated. Try again in a moment")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(opened().isEmpty)
        XCTAssertNil(model.retroPlay)
    }

    func testADownloadShutsTheKeptHostDownFirstAndTheFirstOneTurnsPs1GamesOn() async throws {
        // The first host downloaded turns PS1 games in the host on.
        try RetroHostTestGitHub.publishFixture()
        let (fresh, _, _) = try await launcher(installed: false)
        XCTAssertNil(fresh.preferences.retroHostPs1)
        fresh.retroHostDownload.download()
        try await settle({ !fresh.retroHostDownload.downloading }, "downloaded")
        XCTAssertEqual(fresh.toast?.text, "PS1 emulator 1.0.0 is ready")
        XCTAssertEqual(fresh.preferences.retroHostPs1, true)
        XCTAssertTrue(fresh.playsInHost(.ps1))

        // A kept host lets go of its files before a new host goes in.
        let (model, game, opened) = try await launcher()
        model.play(game)
        try await settle({ opened().first?.0.started.isEmpty == false })
        try await loaded(model)
        let (fake, _) = try XCTUnwrap(opened().first)
        fake.gameStatus = try RetroHostPlayTests.status(ready: true)
        await model.retroPlay?.host.refresh()
        await model.closeRetroGame()
        XCTAssertTrue(model.retroHostKeeper.holding)
        model.retroHostDownload.failedCheck("swanstation_libretro.dylib does not match the signed release")
        model.retroHostDownload.download()
        try await settle({ !model.retroHostDownload.downloading }, "downloaded again")
        XCTAssertEqual(fake.shutdowns, 1, "the kept host was shut down")
        XCTAssertFalse(model.retroHostKeeper.holding)
        XCTAssertEqual(model.toast?.text, "PS1 emulator 1.0.0 is ready")
    }
}
