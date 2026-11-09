import Foundation
import XCTest
@testable import AnyPS5Core

/// The gallery's files: the picture taken when a trophy was earned, named as on Windows and
/// Linux, and found again by its trophy.
final class ScreenshotsTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("shots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func touch(_ name: String) throws { try Data([1]).write(to: folder.appendingPathComponent(name)) }

    func testATrophysPictureHasTheTrophyInItsName() {
        let file = Screenshots.trophyFile(in: folder, gameName: "Stray", titleID: "PPSA01234", trophyID: "0/13", stamp: "20261108-120000")
        XCTAssertEqual(file.lastPathComponent, "PPSA01234-trophy0_13-20261108-120000.png")
        XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, "Stray", "in the game's own folder, as on Windows and Linux")
    }

    func testClipsAndLauncherScreenshotsGoInTheGamesOwnFolderAsOnWindowsAndLinux() throws {
        let clip = Screenshots.clipFile(in: folder, gameName: "Ratchet: Rift/Apart", titleID: "PPSA01234", stamp: "20261110-120000")
        XCTAssertEqual(clip.lastPathComponent, "PPSA01234-clip-20261110-120000.mp4")
        XCTAssertEqual(clip.deletingLastPathComponent().lastPathComponent, "Ratchet Rift Apart")
        let shot = Screenshots.shotFile(in: folder, gameName: "Ratchet: Rift/Apart", titleID: "PPSA01234", stamp: "20261110-120001")
        XCTAssertEqual(shot.lastPathComponent, "PPSA01234-20261110-120001.png")
        XCTAssertEqual(shot.deletingLastPathComponent(), clip.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: clip.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: clip)
        try Data([1]).write(to: shot)
        // A clip from before the move, loose among the captures, is still listed.
        try touch("PPSA01234-20261101-120000.mp4")
        let listed = Screenshots.list(titleID: "PPSA01234", gameName: "Ratchet: Rift/Apart", in: folder)
        XCTAssertEqual(listed.map(\.lastPathComponent), ["PPSA01234-20261110-120001.png", "PPSA01234-clip-20261110-120000.mp4", "PPSA01234-20261101-120000.mp4"])
        XCTAssertEqual(listed.map(Screenshots.isClip), [false, true, true])
    }

    func testTheGamesFolderIsFoundByTheGalleryAndOlderPicturesBesideItToo() throws {
        let file = Screenshots.trophyFile(in: folder, gameName: "Stray", titleID: "PPSA01234", trophyID: "0/13", stamp: "20261109-120000")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        // A picture from before the move, loose among the captures, and an F12 screenshot.
        try touch("PPSA01234-trophy0_2-20261101-120000.png")
        try touch("PPSA01234-20261105-120000.png")
        let shots = Screenshots.list(titleID: "PPSA01234", gameName: "Stray", in: folder)
        XCTAssertEqual(shots.map(\.lastPathComponent), ["PPSA01234-trophy0_13-20261109-120000.png", "PPSA01234-20261105-120000.png", "PPSA01234-trophy0_2-20261101-120000.png"])
        let byTrophy = Screenshots.trophyShots(shots)
        XCTAssertEqual(byTrophy["0/13"]?.deletingLastPathComponent().lastPathComponent, "Stray")
        XCTAssertNotNil(byTrophy["0/2"], "the old one still opens from its trophy")
        XCTAssertEqual(Screenshots.list(titleID: "PPSA01234", in: folder).count, 2, "without the name only the loose ones")
    }

    func testAGameNameIsMadeSafeForAFolderAsOnWindowsAndLinux() {
        XCTAssertEqual(Screenshots.safeName("Ratchet: Rift/Apart? ", fallback: "T"), "Ratchet Rift Apart")
        XCTAssertEqual(Screenshots.safeName("Game...  ", fallback: "T"), "Game")
        XCTAssertEqual(Screenshots.safeName("  ", fallback: "PPSA1"), "PPSA1")
        XCTAssertEqual(Screenshots.safeName("con", fallback: "PPSA1"), "PPSA1")
        XCTAssertEqual(Screenshots.safeName(String(repeating: "a", count: 100)).count, 80)
    }

    func testPicturesAreFoundAgainByTheirTrophyTheNewestWhenSeveral() throws {
        try touch("PPSA01234-trophy0_13-20261108-120000.png")
        try touch("PPSA01234-trophy0_13-20261109-090000.png")
        try touch("PPSA01234-trophy0_2-20261107-120000.png")
        try touch("PPSA01234-20261110-120000.png")
        let shots = Screenshots.list(titleID: "PPSA01234", in: folder)
        let byTrophy = Screenshots.trophyShots(shots)
        XCTAssertEqual(byTrophy.count, 2, "\(byTrophy)")
        XCTAssertEqual(byTrophy["0/13"]?.lastPathComponent, "PPSA01234-trophy0_13-20261109-090000.png")
        XCTAssertEqual(byTrophy["0/2"]?.lastPathComponent, "PPSA01234-trophy0_2-20261107-120000.png")
    }

    func testTheGalleryIsNewestFirstWhateverComesBeforeTheTime() throws {
        // A trophy's name sorts after a plain one by its letters alone: the time decides.
        try touch("PPSA01234-trophy0_1-20261101-120000.png")
        try touch("PPSA01234-20261108-120000.png")
        try touch("PPSA01234-20261105-120000.mp4")
        try touch("PPSA09999-20261112-120000.png")
        let shots = Screenshots.list(titleID: "PPSA01234", in: folder).map(\.lastPathComponent)
        XCTAssertEqual(shots, ["PPSA01234-20261108-120000.png", "PPSA01234-20261105-120000.mp4", "PPSA01234-trophy0_1-20261101-120000.png"])
    }
}
