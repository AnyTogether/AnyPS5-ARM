import XCTest
@testable import AnyPS5Core

/// SelfUnwrap on small containers made here (no game bytes): where segments land, the bytes they
/// carry, what is refused, and that tools/unwrap_self.py (upstream's reference) writes the same.
final class SelfUnwrapTests: XCTestCase {
    struct Segment {
        var type: UInt32 = 1
        var vaddr: UInt64
        var size: UInt64
        var memory: UInt64? = nil
        var align: UInt64 = 0x10
        /// Where its bytes sit in the container, with a record pointing there; nil for none.
        var at: UInt64?
    }

    /// A SELF: magic, a record per segment with bytes (flag 0x800, its index in bits 20 and up),
    /// the inner ELF at 0x100 with its program headers, the bytes from 0x400 on (each byte its
    /// offset's low bits, so nothing looks encrypted and every move shows).
    static func container(_ segments: [Segment], elfClass: UInt8 = 2, programOffset: UInt64 = 0x40, length: Int? = nil) -> [UInt8] {
        let end = segments.compactMap { segment in segment.at.map { Int($0 + segment.size) } }.max() ?? 0x400
        var data = [UInt8](repeating: 0, count: max(length ?? 0, end, 0x400))
        for index in 0x400 ..< data.count { data[index] = UInt8(truncatingIfNeeded: index * 7 + index / 251) }
        SelfUnwrap.put32(&data, 0, SelfUnwrap.selfMagic)
        var record = 0x40
        for (index, segment) in segments.enumerated() {
            guard let at = segment.at else { continue }
            SelfUnwrap.put64(&data, record, 0x800 | UInt64(index) << 20)
            SelfUnwrap.put64(&data, record + 8, at)
            SelfUnwrap.put64(&data, record + 16, segment.size)
            SelfUnwrap.put64(&data, record + 24, segment.size)
            record += 0x20
        }
        let inner = 0x100
        for (index, segment) in segments.enumerated() {
            let at = inner + Int(programOffset) + index * 56
            guard at + 56 <= 0x400 else { break }
            SelfUnwrap.put32(&data, at, segment.type)
            SelfUnwrap.put32(&data, at + 4, 4)
            SelfUnwrap.put64(&data, at + 8, segment.at ?? 0)
            SelfUnwrap.put64(&data, at + 16, segment.vaddr)
            SelfUnwrap.put64(&data, at + 32, segment.size)
            SelfUnwrap.put64(&data, at + 40, segment.memory ?? segment.size)
            SelfUnwrap.put64(&data, at + 48, segment.align)
        }
        // The ELF header last: a table said to overlap it must not overwrite it.
        data.replaceSubrange(inner ..< inner + 4, with: [0x7F, 0x45, 0x4C, 0x46])
        data[inner + 4] = elfClass
        data[inner + 5] = 1
        // Version 1, x86-64 and a 64-byte header, which upstream's reference now asks for.
        data[inner + 6] = 1
        SelfUnwrap.put16(&data, inner + 0x12, 62)
        SelfUnwrap.put32(&data, inner + 0x14, 1)
        SelfUnwrap.put16(&data, inner + 0x34, 64)
        SelfUnwrap.put64(&data, inner + 0x20, programOffset)
        SelfUnwrap.put16(&data, inner + 0x36, 56)
        SelfUnwrap.put16(&data, inner + 0x38, UInt16(segments.count))
        return data
    }

    struct Program { let type: UInt32; let offset: UInt64; let vaddr: UInt64; let size: UInt64; let align: UInt64 }

    static func programs(_ elf: [UInt8]) -> [Program] {
        let offset = Int(SelfUnwrap.u64(elf, 0x20))
        return (0 ..< Int(SelfUnwrap.u16(elf, 0x38))).map { index in
            let at = offset + index * 56
            return Program(type: SelfUnwrap.u32(elf, at), offset: SelfUnwrap.u64(elf, at + 8), vaddr: SelfUnwrap.u64(elf, at + 16),
                           size: SelfUnwrap.u64(elf, at + 32), align: SelfUnwrap.u64(elf, at + 48))
        }
    }

    /// The same bytes as tools/unwrap_self.py, where python3 is there to ask.
    func assertSameAsReference(_ container: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../unwrap_self.py").standardizedFileURL
        guard FileManager.default.fileExists(atPath: script.path), FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("unwrap-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(container).write(to: folder.appendingPathComponent("in.self"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", script.path, folder.appendingPathComponent("in.self").path, folder.appendingPathComponent("py.elf").path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let swift = Result { try SelfUnwrap.unwrap(container) }
        guard process.terminationStatus == 0 else {
            if case .success = swift { XCTFail("the reference refuses what the Swift side unwraps", file: file, line: line) }
            return
        }
        let reference = [UInt8](try Data(contentsOf: folder.appendingPathComponent("py.elf")))
        XCTAssertEqual(try swift.get(), reference, "not the reference's bytes", file: file, line: line)
    }

    /// A segment goes to the first offset from the cursor on with offset % align == vaddr % align,
    /// not to the alignment first and the remainder after: that added 16 KiB of zeros to most
    /// modules and eboots, and made their bytes differ from the reference.
    func testASegmentLandsAtTheFirstOffsetItsAlignmentAllows() throws {
        let container = Self.container([Segment(vaddr: 0, size: 0x50, at: 0x400), Segment(vaddr: 0x4500, size: 0x20, align: 0x4000, at: 0x460)])
        let elf = try SelfUnwrap.unwrap(container)
        let programs = Self.programs(elf)
        XCTAssertEqual(programs.map(\.offset), [0x400, 0x500])
        XCTAssertEqual(elf.count, 0x520)
        for program in programs { XCTAssertEqual(program.offset % program.align, program.vaddr % program.align) }
        XCTAssertEqual(Array(elf[0x500 ..< 0x520]), Array(container[0x460 ..< 0x480]), "the segment's bytes")
        XCTAssertEqual(SelfUnwrap.placement(cursor: 0x450, vaddr: 0x4500, alignment: 0x4000), 0x500)
        XCTAssertEqual(SelfUnwrap.placement(cursor: 0x4200, vaddr: 0x4100, alignment: 0x4000), 0x8100)
        XCTAssertEqual(SelfUnwrap.placement(cursor: 0x451, vaddr: 0x9, alignment: 1), 0x451)
        try assertSameAsReference(container)
    }

    /// Where load segments overlap in the container, a segment found by its vaddr moves with the
    /// PT_LOAD it is in, not with the first region that happens to hold its bytes.
    func testASegmentMovesWithItsOwnLoad() throws {
        let container = Self.container([
            Segment(vaddr: 0, size: 0x200, at: 0x400),
            Segment(vaddr: 0x1000, size: 0x80, at: 0x480),
            Segment(type: 2, vaddr: 0x1010, size: 0x10, at: nil),
        ])
        let elf = try SelfUnwrap.unwrap(container)
        let programs = Self.programs(elf)
        XCTAssertEqual(programs[1].offset, 0x600)
        XCTAssertEqual(programs[2].offset, 0x610, "inside its own PT_LOAD's copy")
        XCTAssertEqual(Array(elf[0x610 ..< 0x620]), Array(container[0x490 ..< 0x4A0]))
        try assertSameAsReference(container)
    }

    /// A segment in a PT_LOAD's part without file bytes (.bss) has nothing to copy: no offset.
    func testASegmentInBssHasNoFileBytes() throws {
        let container = Self.container([
            Segment(vaddr: 0, size: 0x40, memory: 0x400, at: 0x400),
            Segment(type: 7, vaddr: 0x200, size: 0, memory: 0x20, at: nil),
        ])
        let programs = Self.programs(try SelfUnwrap.unwrap(container))
        XCTAssertEqual(programs[1].offset, 0)
        XCTAssertEqual(programs[1].size, 0)
        try assertSameAsReference(container)
    }

    func testWhatIsRefused() {
        let overlapping = Self.container([Segment(vaddr: 0, size: 0x50, at: 0x400)], programOffset: 0x20)
        XCTAssertThrowsError(try SelfUnwrap.unwrap(overlapping)) { XCTAssertTrue("\($0.localizedDescription)".contains("overlaps the ELF header")) }
        let narrow = Self.container([Segment(vaddr: 0, size: 0x50, at: 0x400)], elfClass: 1)
        XCTAssertThrowsError(try SelfUnwrap.unwrap(narrow)) { XCTAssertTrue("\($0.localizedDescription)".contains("64-bit")) }
        // 128 MiB of alignment before one segment: refused, not allocated.
        let padded = Self.container([Segment(vaddr: 0x7FF_F000, size: 0x40, align: 0x800_0000, at: 0x400)])
        XCTAssertThrowsError(try SelfUnwrap.unwrap(padded)) { XCTAssertTrue("\($0.localizedDescription)".contains("padding")) }
        var plain = Self.container([Segment(vaddr: 0, size: 0x50, at: 0x400)])
        SelfUnwrap.put32(&plain, 0, 0x464C_457F)
        XCTAssertThrowsError(try SelfUnwrap.unwrap(plain))
    }

    func testTheSameBytesAsTheReferenceForAPlainModule() throws {
        try assertSameAsReference(Self.container([
            Segment(vaddr: 0, size: 0x300, align: 0x4000, at: 0x400),
            Segment(vaddr: 0x4300, size: 0x120, memory: 0x2000, align: 0x4000, at: 0x700),
            Segment(type: 2, vaddr: 0x4310, size: 0x40, at: nil),
        ]))
    }
}
