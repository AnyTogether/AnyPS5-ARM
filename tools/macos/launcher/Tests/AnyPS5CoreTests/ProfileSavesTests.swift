import Foundation
import XCTest
@testable import AnyPS5Core

/// Each profile's saves and trophies in the game folder while it plays, the others' parked.
final class ProfileSavesTests: XCTestCase {
    var root: URL!
    var game: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-saves-\(UUID().uuidString.prefix(8))")
        game = root.appendingPathComponent("game")
        try write("utku's save", to: "_sd/slot/data.bin")
        try write("utku's memory", to: "_sd_mem/u1/slot0.bin")
        try write("utku's trophies", to: "_trophy/1_0.txt")
        try write("the game", to: "app0/eboot.bin")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, to path: String) throws {
        let file = game.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) -> String? { try? String(contentsOf: game.appendingPathComponent(path), encoding: .utf8) }

    func testSavesFromBeforeProfilesBelongToTheFirstProfile() {
        XCTAssertEqual(ProfileSaves.owner(of: game, legacyOwner: "default"), "default")
    }

    func testAnotherProfileStartsWithNoSavesAndTheFirstOnesComeBack() throws {
        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        XCTAssertNil(read("_sd/slot/data.bin"), "Selin does not play on Utku's saves")
        XCTAssertNil(read("_trophy/1_0.txt"), "nor gets his trophies")
        XCTAssertEqual(read("app0/eboot.bin"), "the game", "the game itself stays")
        XCTAssertEqual(ProfileSaves.owner(of: game, legacyOwner: "default"), "selin")
        try write("selin's save", to: "_sd/slot/data.bin")

        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        XCTAssertEqual(read("_sd/slot/data.bin"), "utku's save")
        XCTAssertEqual(read("_sd_mem/u1/slot0.bin"), "utku's memory")
        XCTAssertEqual(read("_trophy/1_0.txt"), "utku's trophies")

        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        XCTAssertEqual(read("_sd/slot/data.bin"), "selin's save", "each profile keeps its own")
    }

    func testActivatingTheOwnerAgainChangesNothing() throws {
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        XCTAssertEqual(read("_sd/slot/data.bin"), "utku's save")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProfileSaves.parked("default", in: game).appendingPathComponent("_sd").path))
    }

    /// A swap cut short (the Mac went off between the moves) is put right by the next one.
    func testAHalfDoneSwapIsFinishedNextTime() throws {
        // Utku's saves parked, the mark still his: what a stop right after the first move leaves.
        let parked = ProfileSaves.parked("default", in: game)
        try FileManager.default.createDirectory(at: parked, withIntermediateDirectories: true)
        for part in ProfileSaves.parts { try FileManager.default.moveItem(at: game.appendingPathComponent(part), to: parked.appendingPathComponent(part)) }
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        XCTAssertEqual(read("_sd/slot/data.bin"), "utku's save", "brought back in place")
    }

    func testParkedSavesNeverOverwriteOnes() throws {
        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        // Something left Utku's old saves parked twice (a copy put back by hand, say).
        try write("selin", to: "_sd/x")
        let parked = ProfileSaves.parked("selin", in: game)
        try FileManager.default.createDirectory(at: parked.appendingPathComponent("_sd"), withIntermediateDirectories: true)
        try "stale".write(to: parked.appendingPathComponent("_sd/x"), atomically: true, encoding: .utf8)
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        let kept = try FileManager.default.contentsOfDirectory(atPath: parked.path)
        XCTAssertTrue(kept.contains("_sd"))
        XCTAssertTrue(kept.contains { $0.hasPrefix("_sd.") }, "the one already there is kept aside, not lost")
    }

    func testRemovingAProfileTakesOnlyItsSaves() throws {
        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        try write("selin's save", to: "_sd/slot/data.bin")
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        try ProfileSaves.remove("selin", in: game, legacyOwner: "default")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ProfileSaves.parked("selin", in: game).path))
        XCTAssertEqual(read("_sd/slot/data.bin"), "utku's save")
    }

    func testRemovingTheProfileWhoseSavesAreInPlaceLeavesTheFolderEmpty() throws {
        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        try write("selin's save", to: "_sd/slot/data.bin")
        try ProfileSaves.remove("selin", in: game, legacyOwner: "default")
        XCTAssertNil(read("_sd/slot/data.bin"))
        try ProfileSaves.activate("default", in: game, legacyOwner: "default")
        XCTAssertEqual(read("_sd/slot/data.bin"), "utku's save")
    }

    func testTheParkedSavesMoveWithTheGameOnUnlockingAgain() throws {
        try ProfileSaves.activate("selin", in: game, legacyOwner: "default")
        let staged = root.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Installer.carryOver(from: game, to: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appendingPathComponent("_profiles/default/_sd/slot/data.bin").path))
        XCTAssertEqual(ProfileSaves.owner(of: staged, legacyOwner: "default"), "selin")
    }

    func testEachProfileSyncsToItsOwnFolder() {
        let sync = URL(fileURLWithPath: "/Sync")
        XCTAssertEqual(SaveSync.folder(in: sync, titleID: "PPSA1", profile: nil).path, "/Sync/AnyPS5/Saves/PPSA1", "the first profile keeps the folder it had")
        XCTAssertEqual(SaveSync.folder(in: sync, titleID: "PPSA1", profile: "p2").path, "/Sync/AnyPS5/Profiles/p2/Saves/PPSA1")
        let first = SaveSync(game: game, cloud: sync, backups: root, mac: "Mac")
        let second = SaveSync(game: game, cloud: sync, backups: root, mac: "Mac", profile: "p2")
        XCTAssertNotEqual(first.stateFile, second.stateFile, "what each profile last synced is remembered apart")
    }
}
