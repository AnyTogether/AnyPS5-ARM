import Darwin
import XCTest
@testable import AnyPS5Core

/// PS2 games through the emulator host, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_library_test.dart and retro_host_release_test.dart after #171): the PS2 disc
/// kinds the host takes, the PS2 cue sheet listed only while the host plays PS2 discs, and the
/// signed release with LRPS2 beside the host (Fixtures/RetroHostReleasePs2, Desktop's
/// test/fixtures/retro_host_release_ps2), checked with the others.
final class RetroPs2HostTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        let made = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-ps2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        base = URL(fileURLWithPath: try XCTUnwrap(realpath(made.path, nil).map { String(cString: $0) }))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    @discardableResult
    private func write(_ data: Data, _ relative: String) throws -> URL {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func discs(hostPs2: Bool = false) -> [String: RetroPlatform] {
        Dictionary(GameLibrary.scan(base, includeRetro: true, hostPs2: hostPs2, cache: RetroScanCache()).compactMap { game in
            game.retro.map { ($0.path.lastPathComponent, $0.platform) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func testCsoAndZsoImagesAreListedUnderAFolderNamedForPs2Alone() throws {
        try write(Data("CISO".utf8) + Data(count: 28), "PS2/Racer.cso")
        try write(Data("ZISO".utf8) + Data(count: 28), "PS2/Fighter.zso")
        try write(Data("NOPE".utf8) + Data(count: 28), "PS2/Broken.cso")
        try write(Data("CISO".utf8) + Data(count: 28), "Elsewhere/Racer.cso")
        try write(Data("CISO".utf8) + Data(count: 28), "PS1/PS2/Both.cso")
        let found = discs()
        XCTAssertEqual(found["Racer.cso"], .ps2)
        XCTAssertEqual(found["Fighter.zso"], .ps2)
        XCTAssertNil(found["Broken.cso"], "the magic says what it is")
        XCTAssertEqual(found.count, 2, "not outside a PS2 folder, nor under a PS1 one too (a PSP image looks the same)")
    }

    func testAPs2CueSheetIsListedOnlyWhileTheHostPlaysPs2Discs() throws {
        try write(Data(count: 16), "PS2/Disc.bin")
        try write(Data("FILE \"Disc.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), "PS2/Disc.cue")
        XCTAssertNil(discs()["Disc.cue"], "PCSX2 does not boot a cue sheet")
        XCTAssertEqual(discs(hostPs2: true)["Disc.cue"], .ps2)
        try write(Data(count: 16), "Games/Other.bin")
        try write(Data("FILE \"Other.bin\" BINARY\n  TRACK 01 MODE2/2352\n".utf8), "Games/Other.cue")
        XCTAssertEqual(discs(hostPs2: true)["Other.cue"], .ps1, "a cue sheet anywhere else stays PS1")
    }

    func testARetroJsonMayNameAPs2CsoZsoOrElfAndACueOnlyForTheHost() throws {
        for (name, file) in [("Elf game", "game.elf"), ("Cso game", "game.cso"), ("Cue game", "game.cue")] {
            try write(Data(), "\(name)/\(file)")
            try write(try JSONSerialization.data(withJSONObject: ["platform": "ps2", "titleId": "SLUS20001", "name": name, "disc": file]),
                      "\(name)/retro.json")
        }
        let names = { (hostPs2: Bool) in Set(GameLibrary.scan(self.base, includeRetro: true, hostPs2: hostPs2, cache: RetroScanCache()).map(\.name)) }
        XCTAssertEqual(names(false), ["Elf game", "Cso game"])
        XCTAssertEqual(names(true), ["Elf game", "Cso game", "Cue game"])
    }

    // MARK: The signed release with LRPS2

    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/RetroHostReleasePs2")

    func testTheReleaseWithLrps2ChecksItWithTheOthersAndOffersIt() async throws {
        let host = base.appendingPathComponent("RetroHost/host")
        _ = try await RetroHostRelease.install(Self.fixture, into: host, tag: "v1.0.0", keys: RetroHostReleaseFixture.keys, system: .macosArm64)
        XCTAssertTrue(RetroHostRelease.installedHasPs2Core(host, system: .macosArm64))
        let store = RetroHostStore(root: base.appendingPathComponent("RetroHost"), keys: RetroHostReleaseFixture.keys, system: .macosArm64)
        XCTAssertEqual(store.installed()?.ps2Core, host.appendingPathComponent("pcsx2_libretro.dylib").path)
        let checked = try await store.check()
        XCTAssertEqual(checked.ps2Core, host.appendingPathComponent("pcsx2_libretro.dylib").path)
        XCTAssertEqual(checked.cores, [checked.core, host.appendingPathComponent("pcsx2_libretro.dylib").path])
        checked.release()
        // A changed LRPS2 fails the check for a PS1 game too: one kept host plays both.
        try Data("changed".utf8).write(to: host.appendingPathComponent("pcsx2_libretro.dylib"))
        do {
            _ = try await store.check()
            XCTFail("a changed LRPS2 passed")
        } catch let failure as RetroHostReleaseFailure {
            XCTAssertEqual(failure.file, "pcsx2_libretro.dylib")
        }
    }

    func testAStrayLrps2TheReleaseDoesNotListIsNeitherOfferedNorChecked() async throws {
        let host = base.appendingPathComponent("RetroHost/host")
        _ = try await RetroHostRelease.install(RetroHostReleaseFixture.folder, into: host, tag: "v1.0.0", keys: RetroHostReleaseFixture.keys,
                                               system: .macosArm64)
        try Data("stray".utf8).write(to: host.appendingPathComponent("pcsx2_libretro.dylib"))
        let store = RetroHostStore(root: base.appendingPathComponent("RetroHost"), keys: RetroHostReleaseFixture.keys, system: .macosArm64)
        XCTAssertNil(store.installed()?.ps2Core)
        let checked = try await store.check()
        XCTAssertNil(checked.ps2Core)
        checked.release()
    }
}
