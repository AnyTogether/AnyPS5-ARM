import XCTest
@testable import AnyPS5Core

/// A zip written byte by byte (stored, no compression), so a test can put in what no zip tool
/// would: names with "..", absolute paths, links.
struct TestZip {
    enum Item {
        case file(String, Data)
        case folder(String)
        case link(String, String)
    }

    var items: [Item] = []

    mutating func file(_ name: String, _ text: String) { items.append(.file(name, Data(text.utf8))) }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return ~crc
    }

    func data() -> Data {
        var out = Data(), central = Data()
        func u16(_ value: Int, _ to: inout Data) { withUnsafeBytes(of: UInt16(value).littleEndian) { to.append(contentsOf: $0) } }
        func u32(_ value: UInt32, _ to: inout Data) { withUnsafeBytes(of: value.littleEndian) { to.append(contentsOf: $0) } }
        for item in items {
            let (name, body, mode): (String, Data, UInt32) = switch item {
            case .file(let name, let body): (name, body, 0o100644)
            case .folder(let name): (name.hasSuffix("/") ? name : name + "/", Data(), 0o040755)
            case .link(let name, let target): (name, Data(target.utf8), 0o120777)
            }
            let nameBytes = Data(name.utf8), crc = TestZip.crc32(body), offset = UInt32(out.count)
            u32(0x0403_4B50, &out); u16(20, &out); u16(0x0800, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(UInt32(body.count), &out); u32(UInt32(body.count), &out); u16(nameBytes.count, &out); u16(0, &out)
            out.append(nameBytes); out.append(body)
            u32(0x0201_4B50, &central); u16(3 << 8 | 20, &central); u16(20, &central); u16(0x0800, &central); u16(0, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(UInt32(body.count), &central); u32(UInt32(body.count), &central)
            u16(nameBytes.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(mode << 16, &central); u32(offset, &central); central.append(nameBytes)
        }
        let start = UInt32(out.count)
        out.append(central)
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(items.count, &out); u16(items.count, &out)
        u32(UInt32(central.count), &out); u32(start, &out); u16(0, &out)
        return out
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data().write(to: url)
    }

    /// A game's dump in the folder `top` ("" for none): eboot.bin, param.json, a module.
    static func game(_ top: String, title: String = "PPSA01234", version: String = "01.000.000") -> TestZip {
        var zip = TestZip()
        zip.items.append(.folder(top.isEmpty ? "sce_sys" : top))
        zip.file(top + "eboot.bin", "\u{7F}ELF game")
        zip.file(top + "sce_sys/param.json", #"{"titleId":"\#(title)","contentVersion":"\#(version)","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"Game \#(title)"}}}"#)
        zip.file(top + "sce_module/libc.prx", "module")
        return zip
    }
}

final class GameArchivesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-archives-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func names(_ folder: URL) -> [String] {
        let base = folder.standardizedFileURL.path
        return (FileManager.default.enumerator(atPath: base)?.allObjects as? [String] ?? []).sorted()
    }

    func testZipsAreFoundInTheFolderAndOneBelowUnlessUnpackedAlready() throws {
        try TestZip.game("").write(to: root.appendingPathComponent("A.zip"))
        try TestZip.game("").write(to: root.appendingPathComponent("sub/B.ZIP"))
        try TestZip.game("").write(to: root.appendingPathComponent("sub/deeper/C.zip"))
        try TestZip.game("").write(to: root.appendingPathComponent(".hidden.zip"))
        try TestZip.game("").write(to: root.appendingPathComponent("D.zip"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("D"), withIntermediateDirectories: true)
        try Data("not a zip".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let found = GameArchives.find([root])
        XCTAssertEqual(found.map(\.name), ["A.zip", "B.ZIP"])
        XCTAssertEqual(found[0].folder.lastPathComponent, "A")
        XCTAssertEqual(found[0].partial.lastPathComponent, ".A.unpacking")
        XCTAssertGreaterThan(found[0].size, 0)
    }

    func testNamesThatWouldLeaveTheFolderAreRefused() {
        XCTAssertEqual(GameArchives.safeParts("PPSA01234/sce_sys/param.json"), ["PPSA01234", "sce_sys", "param.json"])
        XCTAssertEqual(GameArchives.safeParts("a/./b//c"), ["a", "b", "c"])
        XCTAssertEqual(GameArchives.safeParts("PPSA01234/eboot.bin", strip: "PPSA01234/"), ["eboot.bin"])
        XCTAssertEqual(GameArchives.safeParts("a\\b"), ["a", "b"])
        for bad in ["../evil", "a/../../evil", "/etc/passwd", "C:/Windows/x", "c:evil", "a\\..\\..\\evil", "a/b:c", "a/ b", "a/b ", "a/\u{1}b", "a/b?"] {
            XCTAssertNil(GameArchives.safeParts(bad), bad)
        }
        XCTAssertNil(GameArchives.safeParts("Other/eboot.bin", strip: "PPSA01234/"))
        let into = root.appendingPathComponent("Game")
        XCTAssertEqual(GameArchives.safePath(into, "x/y")?.path, into.appendingPathComponent("x/y").standardizedFileURL.path)
        XCTAssertNil(GameArchives.safePath(into, "../Game2/x"))
    }

    func testThePlanReadsTheDumpInsideAndItsOneTopFolder() throws {
        let zip = root.appendingPathComponent("PPSA01234.zip")
        try TestZip.game("PPSA01234/", version: "01.004.000").write(to: zip)
        let plan = try GameArchives.plan(zip)
        XCTAssertEqual(plan.strip, "PPSA01234/")
        XCTAssertTrue(plan.looksLikeGame)
        XCTAssertEqual(plan.files, 3)
        XCTAssertEqual(plan.titleID, "PPSA01234")
        XCTAssertEqual(plan.version, "01.004.000")
        XCTAssertEqual(plan.refused, [])
        XCTAssertGreaterThan(plan.size, 0)

        var other = TestZip()
        other.file("readme.txt", "hello")
        other.file("photos/a.jpg", "jpg")
        try other.write(to: root.appendingPathComponent("photos.zip"))
        let photos = try GameArchives.plan(root.appendingPathComponent("photos.zip"))
        XCTAssertFalse(photos.looksLikeGame)
        XCTAssertEqual(photos.strip, "")
        XCTAssertNil(photos.titleID)
    }

    func testAZipThatIsNotOneYetCannotBePlanned() throws {
        let zip = root.appendingPathComponent("copying.zip")
        try Data(TestZip.game("").data().prefix(40)).write(to: zip)
        XCTAssertThrowsError(try GameArchives.plan(zip))
    }

    func testItUnpacksIntoAHiddenFolderThenRenamesItWithoutTheTopFolderOrLinks() throws {
        var game = TestZip.game("PPSA01234/")
        game.items.append(.link("PPSA01234/escape", "/etc"))
        let zip = root.appendingPathComponent("PPSA01234.zip")
        try game.write(to: zip)
        let archive = try XCTUnwrap(GameArchives.find([root]).first)
        var heard: [(Int64, Int64)] = []
        try GameArchives.unpack(archive, progress: { heard.append(($0, $1)) })
        XCTAssertEqual(names(root.appendingPathComponent("PPSA01234")), ["eboot.bin", "sce_module", "sce_module/libc.prx", "sce_sys", "sce_sys/param.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.partial.path))
        XCTAssertEqual(heard.last?.0, heard.last?.1)
        XCTAssertNotNil(GameLibrary.inspect(root.appendingPathComponent("PPSA01234")), "the unpacked folder reads as a game")
        XCTAssertEqual(GameArchives.find([root]), [], "unpacked: not offered again")
    }

    func testAnArchiveWithANameOutsideTheFolderWritesNothing() throws {
        var evil = TestZip.game("")
        evil.file("../escaped.txt", "out")
        let zip = root.appendingPathComponent("evil.zip")
        try evil.write(to: zip)
        let plan = try GameArchives.plan(zip)
        XCTAssertEqual(plan.refused, ["../escaped.txt"])
        let archive = GameArchive(url: zip, size: 1)
        XCTAssertThrowsError(try GameArchives.unpack(archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("evil").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.partial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
    }

    func testAStopLeavesNothingBehind() throws {
        let zip = root.appendingPathComponent("PPSA01234.zip")
        try TestZip.game("").write(to: zip)
        let cancel = UnpackCancel()
        cancel.cancel()
        let archive = GameArchive(url: zip, size: 1)
        XCTAssertThrowsError(try GameArchives.unpack(archive, cancel: cancel)) { XCTAssertTrue($0 is UnpackCancelled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.partial.path))
    }

    func testItUnpacksIntoAnotherFolderWhenToldAndNeverOverAnExistingOne() throws {
        let zip = root.appendingPathComponent("PPSA01234-v104.zip")
        try TestZip.game("", version: "01.004.000").write(to: zip)
        let archive = GameArchive(url: zip, size: 1)
        let into = root.appendingPathComponent("PPSA01234-UPDATE")
        try GameArchives.unpack(archive, into: into)
        XCTAssertTrue(FileManager.default.fileExists(atPath: into.appendingPathComponent("eboot.bin").path))
        XCTAssertThrowsError(try GameArchives.unpack(archive, into: into))
    }

    /// A zip made the way the Finder makes one (deflated, a folder at the top) unpacks byte for byte.
    func testAFinderStyleCompressedZipUnpacksWhole() throws {
        let dump = root.appendingPathComponent("made/PPSA05678")
        try FileManager.default.createDirectory(at: dump.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        let big = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 / 7) })
        try big.write(to: dump.appendingPathComponent("eboot.bin"))
        try Data(#"{"titleId":"PPSA05678","contentVersion":"01.000.000"}"#.utf8).write(to: dump.appendingPathComponent("sce_sys/param.json"))
        let zip = root.appendingPathComponent("PPSA05678.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", dump.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        XCTAssertEqual(ditto.terminationStatus, 0)
        let plan = try GameArchives.plan(zip)
        XCTAssertTrue(plan.looksLikeGame)
        XCTAssertEqual(plan.strip, "PPSA05678/")
        XCTAssertEqual(plan.titleID, "PPSA05678")
        try GameArchives.unpack(GameArchive(url: zip, size: 1))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("PPSA05678/eboot.bin")), big)
    }

    func testLeftoversOfAStoppedLauncherAreRemoved() throws {
        let fileManager = FileManager.default
        for name in [".A.unpacking", "sub/.B-UPDATE.copying", ".AnyPS5", "Game"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        GameArchives.removeLeftovers([root])
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent(".A.unpacking").path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("sub/.B-UPDATE.copying").path))
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent(".AnyPS5").path))
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Game").path))
    }
}

final class GameUpdatesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-updates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func dump(_ relative: String, title: String = "PPSA01234", version: String) throws -> URL {
        let folder = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data(#"{"titleId":"\#(title)","contentVersion":"\#(version)"}"#.utf8).write(to: folder.appendingPathComponent("sce_sys/param.json"))
        try Data("\u{7F}ELF".utf8).write(to: folder.appendingPathComponent("eboot.bin"))
        return folder
    }

    private func game(_ relative: String = "Games/PPSA01234") throws -> Game {
        try XCTUnwrap(GameLibrary.inspect(root.appendingPathComponent(relative)))
    }

    func testVersionsCompareNumberByNumber() {
        XCTAssertEqual(GameUpdates.compareVersions("01.004.000", "01.010.000"), -1)
        XCTAssertEqual(GameUpdates.compareVersions("01.010.000", "01.004.000"), 1)
        XCTAssertEqual(GameUpdates.compareVersions("01.004", "01.004.000"), 0)
        XCTAssertEqual(GameUpdates.compareVersions("2.0", "10.0"), -1)
    }

    func testAFolderIsAnUpdateOnlyWhenItIsANewerDumpOfTheSameGame() throws {
        try dump("Games/PPSA01234", version: "01.000.000")
        let base = try game()
        XCTAssertEqual(GameUpdates.target(base).lastPathComponent, "PPSA01234-UPDATE")
        XCTAssertEqual(GameUpdates.check(try dump("Downloads/other", title: "PPSA09999", version: "01.004.000"), for: base).problem, .otherGame)
        XCTAssertEqual(GameUpdates.check(try dump("Downloads/old", version: "01.000.000"), for: base).problem, .notNewer)
        XCTAssertEqual(GameUpdates.check(base.folder, for: base).problem, .notNewer, "the game's own folder")
        let empty = root.appendingPathComponent("Downloads/empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(GameUpdates.check(empty, for: base).problem, .notADump)
        let good = GameUpdates.check(try dump("Downloads/patch", title: "ppsa01234", version: "01.004.000"), for: base)
        XCTAssertNil(good.problem)
        XCTAssertEqual(good.update?.shortVersion, "01.004")
    }

    func testAnUpdateAlreadyBesideTheGameDecides() throws {
        try dump("Games/PPSA01234", version: "01.000.000")
        try dump("Games/PPSA01234-UPDATE", version: "01.004.000")
        let base = try game()
        XCTAssertEqual(base.update?.version, "01.004.000")
        XCTAssertEqual(GameUpdates.problem(with: base, titleID: "PPSA01234", version: "01.004.000"), .haveNewer)
        XCTAssertEqual(GameUpdates.problem(with: base, titleID: "PPSA01234", version: "01.002.000"), .haveNewer)
        XCTAssertEqual(GameUpdates.problem(with: base, titleID: "PPSA01234", version: "01.006.000"), .haveOlder)
    }

    func testOnTheSameVolumeTheUpdateIsMovedAndTheGameFindsIt() throws {
        try dump("Games/PPSA01234", version: "01.000.000")
        let source = try dump("Downloads/patch", version: "01.004.000")
        let base = try game()
        let update = try XCTUnwrap(GameUpdates.check(source, for: base).update)
        XCTAssertTrue(try GameUpdates.install(update, for: base))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try game().update?.version, "01.004.000")
        XCTAssertEqual(try game().update?.folder.lastPathComponent, "PPSA01234-UPDATE")
        XCTAssertThrowsError(try GameUpdates.install(update, for: base), "never over an update folder that is there")
    }

    func testACopyLeavesTheSourceSkipsLinksAndAStopLeavesNothing() throws {
        let source = try dump("Downloads/patch", version: "01.004.000")
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        let into = root.appendingPathComponent("copy")
        var heard: [(Int64, Int64)] = []
        try GameUpdates.copySync(from: source, into: into, progress: { heard.append(($0, $1)) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: into.appendingPathComponent("sce_sys/param.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("eboot.bin").path))
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: into.appendingPathComponent("link").path))
        XCTAssertEqual(heard.last?.0, heard.last?.1)
        let stopped = root.appendingPathComponent("stopped")
        XCTAssertThrowsError(try GameUpdates.copySync(from: source, into: stopped, cancelled: { true })) { XCTAssertTrue($0 is UnpackCancelled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stopped.path))
    }
}
