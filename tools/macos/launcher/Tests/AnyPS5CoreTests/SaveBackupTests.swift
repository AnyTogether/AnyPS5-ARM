import Foundation
import XCTest
@testable import AnyPS5Core

final class SaveBackupTests: XCTestCase {
    var root: URL!
    var game: URL!
    var backups: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("saves-\(UUID().uuidString)")
        game = root.appendingPathComponent("game")
        backups = root.appendingPathComponent("Backups/Silksong (PPSA12544)")
        try write("first save", to: "_sd/savedata1/user1.dat")
        try write("memory", to: "_sd_mem/block")
        try write("trophy", to: "_trophy/TROP.SFM")
        try write("not a save", to: "app0/eboot.bin")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, to path: String) throws {
        let file = game.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? { try? String(contentsOf: game.appendingPathComponent(path), encoding: .utf8) }

    func testABackupHoldsTheSavesAndTrophiesOnly() throws {
        let backup = try SaveBackup.backUp(game, to: backups, date: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(backup.lastPathComponent.hasSuffix(".zip"))
        let listing = try SaveBackup.contents(of: backup)
        XCTAssertTrue(listing.contains("_sd/savedata1/user1.dat"))
        XCTAssertTrue(listing.contains("_sd_mem/block"))
        XCTAssertTrue(listing.contains("_trophy/TROP.SFM"))
        XCTAssertFalse(listing.contains { $0.hasPrefix("app0") })
    }

    func testRestoringPutsTheSavesBackAndKeepsWhatWasThere() throws {
        let backup = try SaveBackup.backUp(game, to: backups, date: Date(timeIntervalSince1970: 1_800_000_000))
        try write("later save", to: "_sd/savedata1/user1.dat")
        try write("a new slot", to: "_sd/savedata2/user1.dat")
        try SaveBackup.restore(backup, into: game, keepingIn: backups, date: Date(timeIntervalSince1970: 1_800_000_600))
        XCTAssertEqual(read("_sd/savedata1/user1.dat"), "first save")
        XCTAssertNil(read("_sd/savedata2/user1.dat"))
        XCTAssertEqual(read("app0/eboot.bin"), "not a save")
        let kept = SaveBackup.backups(in: backups)
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(try SaveBackup.contents(of: kept[0]).contains("_sd/savedata2/user1.dat"), "the saves before the restore are kept, newest first")
    }

    func testAGameWithoutSavesHasNothingToBackUp() throws {
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("app0"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try SaveBackup.backUp(empty, to: backups, date: Date()))
    }

    func testSomethingElseIsNotRestored() throws {
        let other = root.appendingPathComponent("other.zip")
        try "junk".write(to: other, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try SaveBackup.restore(other, into: game, keepingIn: backups, date: Date()))
        XCTAssertEqual(read("_sd/savedata1/user1.dat"), "first save")
    }

    func testAGamesScreenshotsNewestFirst() throws {
        let folder = root.appendingPathComponent("Pictures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["PPSA12544-20261020-101010.png", "PPSA12544-20261023-090000.png", "PPSA12544-20261023-090000-1.png", "PPSA02929-20261023-120000.png", "notes.txt"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        XCTAssertEqual(Screenshots.list(titleID: "PPSA12544", in: folder).map(\.lastPathComponent),
                       ["PPSA12544-20261023-090000-1.png", "PPSA12544-20261023-090000.png", "PPSA12544-20261020-101010.png"])
        XCTAssertTrue(Screenshots.list(titleID: "PPSA99999", in: folder).isEmpty)
        XCTAssertTrue(Screenshots.list(titleID: "PPSA12544", in: folder.appendingPathComponent("missing")).isEmpty)
    }
}
