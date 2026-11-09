@testable import AnyPS5Core
import XCTest

/// A small .ffpfsc written byte by byte as AnyDevKit's FfpfscPackager lays one out, so a test can
/// also write what no packager would.
struct TestFfpfsc {
    static let blockSize = 0x1000

    struct Item {
        var path: String
        var data: [UInt8] = []
        var directory = false
        /// The dirent type when not the regular one (a link's, say).
        var type: UInt32?
        /// The inode's mode when not the regular one.
        var mode: UInt16?
        /// The name as it is in the directory, when not the last part of `path`.
        var rawName: String?
    }

    struct Node {
        var data: [UInt8] = []
        var size = 0
        var directory = false
        var internal_ = false
        var pfsc = false
        var flags: UInt32 = 0
        var mode: UInt16?
        var start = 0
        var blocks = 0
    }

    static func align(_ value: Int, _ to: Int) -> Int { (value + to - 1) / to * to }

    static func put(_ value: UInt64, _ bytes: inout [UInt8], _ at: Int, _ width: Int) {
        for index in 0..<width { bytes[at + index] = UInt8((value >> (UInt64(index) * 8)) & 0xFF) }
    }

    static func dirent(_ data: inout [UInt8], _ inode: Int, _ type: UInt32, _ name: String) {
        let bytes = Array(name.utf8)
        let size = align(bytes.count + 17, 8)
        var entry = [UInt8](repeating: 0, count: size)
        put(UInt64(inode), &entry, 0, 4)
        put(UInt64(type), &entry, 4, 4)
        put(UInt64(bytes.count), &entry, 8, 4)
        put(UInt64(size), &entry, 12, 4)
        entry.replaceSubrange(16..<(16 + bytes.count), with: bytes)
        data += entry
    }

    static func parent(_ path: String) -> String {
        path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
    }

    static func base(_ path: String) -> String {
        path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
    }

    /// One PFS image of `items`, the same fields and order the writer uses.
    static func pfs(_ items: [Item], pfscFile: Bool = false) -> (bytes: [UInt8], nodes: [Node]) {
        let bs = blockSize
        let sorted = items.sorted { ($0.directory ? 0 : 1, $0.path) < ($1.directory ? 0 : 1, $1.path) }
        let root = 2
        var nodes = [Node](repeating: Node(), count: root + 1)
        nodes[0].directory = true
        nodes[0].internal_ = true
        nodes[1].internal_ = true
        nodes[root].directory = true
        var directories: [String: Int] = ["": root]
        for item in sorted where item.directory { directories[item.path] = root + 1 + (sorted.firstIndex { $0.path == item.path }!) }
        for item in sorted {
            var node = Node()
            node.mode = item.mode
            if item.directory {
                node.directory = true
            } else {
                node.data = item.data
                node.pfsc = pfscFile
            }
            node.flags = 0x10 | (pfscFile ? 1 : 0)
            nodes.append(node)
        }
        for (path, inode) in directories {
            dirent(&nodes[inode].data, inode, 4, ".")
            dirent(&nodes[inode].data, directories[parent(path)] ?? inode, 5, "..")
        }
        for (index, item) in sorted.enumerated() {
            let inode = root + 1 + index
            guard let owner = directories[parent(item.path)] else { fatalError("no parent for \(item.path)") }
            dirent(&nodes[owner].data, inode, item.type ?? (item.directory ? 3 : 2), item.rawName ?? base(item.path))
        }
        dirent(&nodes[0].data, 1, 2, "flat_path_table")
        dirent(&nodes[0].data, root, 3, "uroot")
        let perBlock = bs / 0xA8
        let inodeBlocks = (nodes.count + perBlock - 1) / perBlock
        var next = 1 + inodeBlocks
        for index in nodes.indices {
            let bytes = nodes[index].data.count
            let blocks = max(1, align(bytes, bs) / bs)
            nodes[index].start = next
            nodes[index].blocks = blocks
            nodes[index].size = nodes[index].directory ? blocks * bs : bytes
            next += blocks
        }
        var image = [UInt8](repeating: 0, count: next * bs)
        put(2, &image, 0, 8)
        put(20_130_315, &image, 8, 8)
        put(UInt64(bs), &image, 0x20, 4)
        put(1, &image, 0x28, 8)
        put(UInt64(nodes.count), &image, 0x30, 8)
        put(UInt64(next), &image, 0x38, 8)
        put(UInt64(inodeBlocks), &image, 0x40, 8)
        for (index, node) in nodes.enumerated() {
            var inode = [UInt8](repeating: 0, count: 0xA8)
            put(UInt64(node.mode ?? ((node.directory ? 0x4000 : 0x8000) | 0o555)), &inode, 0, 2)
            put(1, &inode, 2, 2)
            put(UInt64(node.flags | (node.internal_ ? 0x20000 : 0)), &inode, 4, 4)
            put(UInt64(node.size), &inode, 8, 8)
            put(UInt64(node.size), &inode, 16, 8)
            put(UInt64(node.blocks), &inode, 0x60, 4)
            put(UInt64(node.start), &inode, 0x64, 4)
            for pointer in 1..<12 { put(0xFFFF_FFFF, &inode, 0x64 + pointer * 4, 4) }
            image.replaceSubrange(((1 + index / perBlock) * bs + (index % perBlock) * 0xA8)..<((1 + index / perBlock) * bs + (index % perBlock) * 0xA8 + 0xA8), with: inode)
            image.replaceSubrange(node.start * bs..<(node.start * bs + node.data.count), with: node.data)
        }
        return (image, nodes)
    }

    /// A PFSC container of stored blocks around `source`, its bytes, the header's size and the
    /// blocks in it.
    static func pfsc(_ source: [UInt8]) -> (bytes: [UInt8], header: Int, blocks: Int) {
        let padded = align(source.count, 0x10000)
        let blocks = padded / 0x10000
        let header = align(0x400 + (blocks + 1) * 8, 0x10000)
        var bytes = [UInt8](repeating: 0, count: header + padded)
        put(0x4353_4650, &bytes, 0, 4)
        put(6, &bytes, 8, 4)
        put(0x10000, &bytes, 12, 4)
        put(0x10000, &bytes, 16, 8)
        put(0x400, &bytes, 24, 8)
        put(UInt64(header), &bytes, 32, 8)
        put(UInt64(padded), &bytes, 40, 8)
        for index in 0...blocks { put(UInt64(header + index * 0x10000), &bytes, 0x400 + index * 8, 8) }
        bytes.replaceSubrange(header..<(header + source.count), with: source)
        return (bytes, header, blocks)
    }

    var bytes: [UInt8]
    /// Where the PFSC container, the inner image's first byte and the inner image's inode table are.
    let pfscStart: Int
    let innerStart: Int
    /// The blocks in the PFSC container: the table has one entry more.
    let blocks: Int

    init(_ items: [Item], outerExtra: [Item] = []) {
        let inner = Self.pfs(items).bytes
        let packed = Self.pfsc(inner)
        let outer = Self.pfs([Item(path: "pfs_image.dat", data: packed.bytes)] + outerExtra, pfscFile: true)
        bytes = outer.bytes
        // Inode 3, or 4 with another file: the first file after the root.
        let index = outerExtra.isEmpty ? 3 : 4
        pfscStart = outer.nodes[index].start * Self.blockSize
        innerStart = pfscStart + packed.header
        blocks = packed.blocks
    }

    static func game(titleName: String = "Small Quest") -> [Item] {
        [
            Item(path: "sce_module", directory: true),
            Item(path: "sce_sys", directory: true),
            Item(path: "eboot.bin", data: [UInt8](repeating: 7, count: 3000)),
            Item(path: "sce_module/libc.prx", data: (0..<150_000).map { UInt8($0 & 0xFF) }),
            Item(path: "sce_sys/param.json", data: Array(#"{"titleId":"PPSA07007","contentVersion":"01.000.000","localizedParameters":{"defaultLanguage":"en-US","en-US":{"titleName":"\#(titleName)"}}}"#.utf8)),
            Item(path: "sce_sys/icon0.png", data: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8) + [0, 0, 0, 16, 0, 0, 0, 16, 8, 6, 0, 0, 0]),
            Item(path: "sce_sys/empty.dat", data: []),
        ]
    }

    func write(to url: URL) throws { try Data(bytes).write(to: url) }

    func put32(_ value: UInt32, at offset: Int) -> TestFfpfsc {
        var copy = self
        Self.put(UInt64(value), &copy.bytes, offset, 4)
        return copy
    }

    func put64(_ value: UInt64, at offset: Int) -> TestFfpfsc {
        var copy = self
        Self.put(value, &copy.bytes, offset, 8)
        return copy
    }

    /// The offset of `needle`, the first found at or past `from`.
    func find(_ needle: String, from: Int) -> Int {
        let target = Array(needle.utf8)
        var at = from
        while at + target.count <= bytes.count {
            if Array(bytes[at..<(at + target.count)]) == target { return at }
            at += 1
        }
        fatalError("\(needle) is not in the image")
    }

    /// The inner image's inode `number` table entry, for inner image block size `blockSize`.
    func innerInode(_ number: Int) -> Int {
        let perBlock = Self.blockSize / 0xA8
        return innerStart + (1 + number / perBlock) * Self.blockSize + (number % perBlock) * 0xA8
    }
}

/// A game dropped into the games folder as one .ffpfsc: found, read as a plan, unpacked with the
/// zip flow into the folder beside it, and refused with a true message when out of shape.
final class FfpfscTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-ffpfsc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func file(_ name: String = "Small.ffpfsc") -> URL { root.appendingPathComponent(name) }

    func damaged(_ image: TestFfpfsc, _ name: String = "Small.ffpfsc", file line: StaticString = #filePath, line number: UInt = #line) throws {
        let url = file(name)
        try image.write(to: url)
        XCTAssertThrowsError(try GameArchives.plan(url), file: line, line: number) { error in
            XCTAssertTrue(String(describing: error).contains("damaged"), "\(error)", file: line, line: number)
        }
    }

    func testAGameFileUnpacksBesideItByteForByte() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        try image.write(to: file())
        let found = GameArchives.find([root])
        XCTAssertEqual(found.map(\.name), ["Small.ffpfsc"])
        let archive = found[0]
        XCTAssertTrue(archive.isFfpfsc)
        XCTAssertEqual(archive.folder.lastPathComponent, "Small")

        let plan = try GameArchives.plan(archive.url)
        XCTAssertTrue(plan.looksLikeGame)
        XCTAssertEqual(plan.strip, "")
        XCTAssertEqual(plan.titleID, "PPSA07007")
        XCTAssertEqual(plan.version, "01.000.000")
        XCTAssertEqual(plan.titleName, "Small Quest")
        XCTAssertEqual(plan.files, 5)
        XCTAssertEqual(plan.size, Int64(3000 + 150_000 + TestFfpfsc.game()[4].data.count + 29))
        XCTAssertNotNil(plan.icon)
        XCTAssertEqual(plan.refused, [])
        XCTAssertNil(plan.problem)

        var heard: [(Int64, Int64)] = []
        try GameArchives.unpack(archive, progress: { heard.append(($0, $1)) })
        XCTAssertEqual(heard.first?.0, 0)
        XCTAssertEqual(heard.last?.0, plan.size)
        for item in TestFfpfsc.game() where !item.directory {
            let written = try Data(contentsOf: archive.folder.appendingPathComponent(item.path))
            XCTAssertEqual(Array(written), item.data, item.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.partial.path))
        XCTAssertEqual(GameArchives.find([root]), [], "unpacked: a folder of its name stands beside it")
    }

    func testAFileWithNoGameIsReadButNotOffered() throws {
        let image = TestFfpfsc([TestFfpfsc.Item(path: "notes.txt", data: Array("hello".utf8))])
        try image.write(to: file())
        let plan = try GameArchives.plan(file())
        XCTAssertFalse(plan.looksLikeGame)
        XCTAssertEqual(plan.files, 1)
    }

    func testAnExistingFolderIsNeverWrittenOver() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        try image.write(to: file())
        let folder = root.appendingPathComponent("Small")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appendingPathComponent("mine.txt")
        try Data("keep".utf8).write(to: marker)
        XCTAssertEqual(GameArchives.find([root]), [], "a folder of its name is there: not offered")
        let archive = GameArchive(url: file(), size: Int64(image.bytes.count))
        XCTAssertThrowsError(try GameArchives.unpack(archive))
        XCTAssertThrowsError(try GameArchives.unpackSync(file(), into: folder))
        XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
    }

    func testAStopLeavesNothingBehind() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        try image.write(to: file())
        let into = root.appendingPathComponent("out")
        XCTAssertThrowsError(try GameArchives.unpackSync(file(), into: into, cancelled: { true })) { error in
            XCTAssertTrue(error is UnpackCancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: into.path))
    }

    // MARK: Malformed files, each refused

    func testNotAPfsImageIsDamaged() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        try damaged(image.put64(0, at: 8))
        try Data("not one".utf8).write(to: file())
        XCTAssertThrowsError(try GameArchives.plan(file()))
    }

    func testTruncationAtEveryStageIsDamaged() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        for size in [200, 0x900, image.pfscStart + 0x40, image.innerStart + 0x200, image.bytes.count - 1] {
            var cut = image
            cut.bytes = Array(image.bytes.prefix(size))
            try damaged(cut, "cut\(size).ffpfsc")
        }
    }

    func testOffsetsPastTheEndAreDamaged() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        let bs = TestFfpfsc.blockSize
        // Outer inode 3 (pfs_image.dat): its first block far past the file.
        try damaged(image.put32(0x7FFF_FFFF, at: bs + 3 * 0xA8 + 0x64))
        // A block count past the file, outer and inner.
        try damaged(image.put64(1 << 40, at: 0x38))
        try damaged(image.put64(1 << 40, at: image.innerStart + 0x38))
        // A count of inodes past its table.
        try damaged(image.put64(100_000, at: image.innerStart + 0x30))
        // A file's bytes past its blocks: inner inode of "eboot.bin", size 3000 → past one block.
        let eboot = image.innerInode(5)
        try damaged(image.put64(UInt64(bs * 50), at: eboot + 8))
        // The PFSC table: the first entry not at the data, a later one out of order.
        try damaged(image.put64(0, at: image.pfscStart + 0x400))
        try damaged(image.put64(1, at: image.pfscStart + 0x408))
    }

    func testPathsThatEscapeAreRefused() throws {
        let names: [(String, String)] = [("dots", ".."), ("slash", "../evil.dll"), ("absolute", "/etc/passwd"), ("back", #"..\evil"#), ("drive", "C:evil"), ("device", "con.txt"), ("dot", "trailing.")]
        for (name, raw) in names {
            let items = TestFfpfsc.game() + [TestFfpfsc.Item(path: "x", data: [1], rawName: raw)]
            let image = TestFfpfsc(items)
            let url = file("\(name).ffpfsc")
            try image.write(to: url)
            let plan = try GameArchives.plan(url)
            XCTAssertEqual(plan.refused.count, 1, raw)
            XCTAssertThrowsError(try GameArchives.unpackSync(url, into: root.appendingPathComponent("o-\(name)")), raw)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("o-\(name)").path), raw)
        }
    }

    func testALinkIsRefused() throws {
        let typed = TestFfpfsc(TestFfpfsc.game() + [TestFfpfsc.Item(path: "l", data: [1], type: 6)])
        try typed.write(to: file("typed.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("typed.ffpfsc")).refused.count, 1)
        let moded = TestFfpfsc(TestFfpfsc.game() + [TestFfpfsc.Item(path: "l", data: [1], mode: 0xA16D)])
        try moded.write(to: file("moded.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("moded.ffpfsc")).refused.count, 1)
    }

    func testCompressedIsSaid() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        // The table says each block is 0x8000 bytes: as a compressed one would be.
        let table = image.pfscStart + 0x400
        let first = (0..<8).reduce(UInt64(0)) { $0 | UInt64(image.bytes[table + $1]) << UInt64($1 * 8) }
        var packed = image
        for index in 1...image.blocks { TestFfpfsc.put(first + UInt64(index) * 0x8000, &packed.bytes, table + index * 8, 8) }
        try packed.write(to: file())
        XCTAssertEqual(try GameArchives.plan(file()).problem, ArchiveProblem.compressed)
        XCTAssertThrowsError(try GameArchives.unpackSync(file(), into: root.appendingPathComponent("o")))
        // A file inside flagged as PFSC compressed.
        let inside = image.put32(0x11, at: image.innerInode(5) + 4)
        try inside.write(to: file("inside.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("inside.ffpfsc")).problem, ArchiveProblem.compressed)
    }

    func testOtherLayoutsAreSaidUnsupported() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        var scratch = image
        // Encrypted (mode bit 4), outer and inner.
        TestFfpfsc.put(4, &scratch.bytes, 0x1C, 2)
        try scratch.write(to: file("enc.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("enc.ffpfsc")).problem, ArchiveProblem.unsupported)
        scratch = image
        TestFfpfsc.put(4, &scratch.bytes, image.innerStart + 0x1C, 2)
        try scratch.write(to: file("enc2.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("enc2.ffpfsc")).problem, ArchiveProblem.unsupported)
        // A block size that is not a power of two.
        try image.put32(0x1800, at: 0x20).write(to: file("bs.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("bs.ffpfsc")).problem, ArchiveProblem.unsupported)
        // A PFSC block size other than 64 KiB.
        try image.put32(0x8000, at: image.pfscStart + 12).write(to: file("pb.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("pb.ffpfsc")).problem, ArchiveProblem.unsupported)
        // A second file in the outer image.
        let extra = TestFfpfsc(TestFfpfsc.game(), outerExtra: [TestFfpfsc.Item(path: "more.bin", data: [1])])
        try extra.write(to: file("two.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("two.ffpfsc")).problem, ArchiveProblem.unsupported)
        // pfs_image.dat without the PFSC flag.
        try image.put32(0x10, at: TestFfpfsc.blockSize + 3 * 0xA8 + 4).write(to: file("noflag.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("noflag.ffpfsc")).problem, ArchiveProblem.unsupported)
        // A file in more than one piece.
        try image.put32(99, at: image.innerInode(5) + 0x68).write(to: file("frag.ffpfsc"))
        XCTAssertEqual(try GameArchives.plan(file("frag.ffpfsc")).problem, ArchiveProblem.unsupported)
    }

    func testLoopsAndSharedFilesAreRefused() throws {
        let image = TestFfpfsc(TestFfpfsc.game())
        // uroot's "sce_sys" entry pointing back to uroot (inode 2): a directory loop.
        let name = image.find("sce_sys", from: image.innerStart)
        try damaged(image.put32(2, at: name - 16))
        // A second name for one file: "eboot.bin" pointed at the file of the next entry.
        var twice = TestFfpfsc(TestFfpfsc.game())
        TestFfpfsc.put(5, &twice.bytes, twice.find("empty.dat", from: twice.innerStart) - 16, 4)
        try damaged(twice)
    }

    func testDepthAndCountAreBounded() throws {
        var deep: [TestFfpfsc.Item] = []
        var path = ""
        for level in 0..<40 {
            path += level == 0 ? "d" : "/d"
            deep.append(TestFfpfsc.Item(path: path, directory: true))
        }
        try damaged(TestFfpfsc(deep + [TestFfpfsc.Item(path: path + "/f", data: [1])]))
    }

    func testAnUnreadableIconOrBadJSONStaysUnread() throws {
        var items = TestFfpfsc.game()
        items[4] = TestFfpfsc.Item(path: "sce_sys/param.json", data: Array("not json".utf8))
        items.removeAll { $0.path == "sce_sys/icon0.png" }
        let image = TestFfpfsc(items)
        try image.write(to: file())
        let plan = try GameArchives.plan(file())
        XCTAssertNil(plan.titleID)
        XCTAssertNil(plan.titleName)
        XCTAssertNil(plan.icon)
        XCTAssertTrue(plan.looksLikeGame)
    }

    func testIconLimits() {
        var picture: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8) + [0, 0, 0x20, 0, 0, 0, 0x20, 0, 8, 6, 0, 0, 0]
        XCTAssertFalse(Ffpfsc.isReasonablePNG(picture), "8192 x 8192 is too large to decode for an icon")
        picture[18] = 0
        picture[22] = 0
        XCTAssertTrue(Ffpfsc.isReasonablePNG(picture))
        XCTAssertFalse(Ffpfsc.isReasonablePNG(Array(picture.prefix(20))))
    }
}
