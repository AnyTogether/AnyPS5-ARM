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
        let file = Screenshots.trophyFile(in: folder, titleID: "PPSA01234", trophyID: "0/13", stamp: "20261108-120000")
        XCTAssertEqual(file.lastPathComponent, "PPSA01234-trophy0_13-20261108-120000.png")
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
