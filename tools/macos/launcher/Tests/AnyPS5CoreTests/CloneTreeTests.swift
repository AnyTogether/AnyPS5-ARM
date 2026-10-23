import XCTest
@testable import AnyPS5Core

final class CloneTreeTests: XCTestCase {
    var folder: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        folder = fm.temporaryDirectory.appendingPathComponent("clone-\(UUID().uuidString)")
        try fm.createDirectory(at: folder.appendingPathComponent("dump/sce_sys"), withIntermediateDirectories: true)
        try Data("eboot".utf8).write(to: folder.appendingPathComponent("dump/eboot.bin"))
        try Data("param".utf8).write(to: folder.appendingPathComponent("dump/sce_sys/param.json"))
        try fm.createDirectory(at: folder.appendingPathComponent("app0"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: folder) }

    func testTheMacsOwnDiskClones() {
        XCTAssertTrue(Installer.clones(from: folder.appendingPathComponent("dump"), to: folder.appendingPathComponent("app0")))
    }

    /// Where cloning is not possible (exFAT, HFS+, another disk), the game's files are links to
    /// the dump rather than a second copy of it.
    func testWithoutCloningTheGameLinksToTheDump() throws {
        let dump = folder.appendingPathComponent("dump")
        let app0 = folder.appendingPathComponent("app0")
        var reported: [Double] = []
        try Installer.copyTree(dump, into: app0, link: true, cancelled: {}) { reported.append($0) }
        let eboot = app0.appendingPathComponent("eboot.bin")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: eboot.path), dump.appendingPathComponent("eboot.bin").resolvingSymlinksInPath().path)
        XCTAssertEqual(try String(contentsOf: app0.appendingPathComponent("sce_sys/param.json"), encoding: .utf8), "param")
        XCTAssertEqual(reported.last, 1)
    }

    func testWithCloningTheFilesAreTheirOwn() throws {
        let app0 = folder.appendingPathComponent("app0")
        try Installer.copyTree(folder.appendingPathComponent("dump"), into: app0, link: false, cancelled: {}) { _ in }
        let eboot = app0.appendingPathComponent("eboot.bin")
        XCTAssertNotEqual((try? eboot.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink, true)
        try Data("changed".utf8).write(to: eboot)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("dump/eboot.bin"), encoding: .utf8), "eboot", "a clone never changes the dump")
    }
}
