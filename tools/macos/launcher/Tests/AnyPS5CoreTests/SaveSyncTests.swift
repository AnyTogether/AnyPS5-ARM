import Foundation
import XCTest
@testable import AnyPS5Core

/// Two Macs sharing a sync folder: each has its game folder and its own record of the last sync.
final class SaveSyncTests: XCTestCase {
    var root: URL!
    var cloud: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        cloud = root.appendingPathComponent("Cloud/AnyPS5/Saves/PPSA15065")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func game(_ mac: String) -> URL { root.appendingPathComponent("\(mac)/game") }
    func backups(_ mac: String) -> URL { root.appendingPathComponent("\(mac)/Backups") }

    func save(_ text: String, on mac: String, slot: String = "savedata0/save.dat") throws {
        let file = game(mac).appendingPathComponent("_sd/\(slot)")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(on mac: String, slot: String = "savedata0/save.dat") -> String? {
        try? String(contentsOf: game(mac).appendingPathComponent("_sd/\(slot)"), encoding: .utf8)
    }

    func sync(_ mac: String, at seconds: Double) throws -> SaveSync.Outcome {
        try SaveSync(game: game(mac), cloud: cloud, backups: backups(mac), mac: mac).sync(date: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    func testTheFirstMacPutsItsSavesUp() throws {
        try save("level 1", on: "A")
        XCTAssertEqual(try sync("A", at: 0), .uploaded)
        XCTAssertEqual(try sync("A", at: 10), .unchanged, "nothing changed since")
    }

    func testAnotherMacTakesThemAndPlaysOn() throws {
        try save("level 1", on: "A")
        _ = try sync("A", at: 0)
        XCTAssertEqual(try sync("B", at: 100), .downloaded(from: "A"))
        XCTAssertEqual(read(on: "B"), "level 1")
        try save("level 2", on: "B")
        XCTAssertEqual(try sync("B", at: 200), .uploaded)
        XCTAssertEqual(try sync("A", at: 300), .downloaded(from: "B"))
        XCTAssertEqual(read(on: "A"), "level 2")
    }

    func testSavesPlayedOnBothMacsKeepTheNewestAndBackUpTheOther() throws {
        try save("level 1", on: "A")
        _ = try sync("A", at: 0)
        _ = try sync("B", at: 10)
        try save("A's level 2", on: "A")
        _ = try sync("A", at: 20)
        // B played on without syncing in between, and later.
        try save("B's level 3", on: "B")
        let outcome = try sync("B", at: 30)
        XCTAssertEqual(outcome, .uploaded, "B's saves are newer")
        XCTAssertFalse(SaveBackup.backups(in: cloud.appendingPathComponent("Older")).isEmpty, "A's saves, replaced, are not kept in the sync folder")
        XCTAssertEqual(try sync("A", at: 40), .downloaded(from: "B"))
        XCTAssertEqual(read(on: "A"), "B's level 3")
        XCTAssertFalse(SaveBackup.backups(in: backups("A")).isEmpty, "A's saves before the download are not backed up")
    }

    func testAMacWithoutSavesJustTakesThem() throws {
        try save("level 1", on: "A")
        _ = try sync("A", at: 0)
        XCTAssertEqual(try sync("B", at: 5), .downloaded(from: "A"))
        XCTAssertTrue(SaveBackup.backups(in: backups("B")).isEmpty, "there was nothing to back up")
    }

    func testNoSavesAnywhereIsNothingToDo() throws {
        try FileManager.default.createDirectory(at: game("A"), withIntermediateDirectories: true)
        XCTAssertEqual(try sync("A", at: 0), .unchanged)
    }
}
