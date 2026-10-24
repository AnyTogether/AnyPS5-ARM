import Foundation

/// Turns a decrypted SELF or fSELF container into the clean ELF the relinker reads: the Swift form
/// of tools/unwrap_self.py, which documents the container layout. The two must write the same bytes:
/// SelfUnwrapTests checks it on synthetic containers, scripts/compare-unwrap.sh on real dumps.
public enum SelfUnwrap {
    public struct Refused: LocalizedError {
        public let reason: String
        public var errorDescription: String? { reason }
    }

    static let selfMagic: UInt32 = 0x1D3D_154F
    static let selfMagicKernel: UInt32 = 0xEEF5_1454
    static let recordOffset = 0x40
    static let recordSize = 0x20
    static let recordHasSegment: UInt64 = 0x800
    static let recordSegmentShift: UInt64 = 20
    static let firstRegion = 0x400
    /// The most zero bytes alignment may add to the output in all.
    static let maxAlignmentPadding = 64 * 1024 * 1024
    static let ptLoad: UInt32 = 1
    static let ptNote: UInt32 = 4
    static let entropyLimit = 7.5
    static let entropySample = 0x10000

    /// Whether the file starts with a SELF container's magic.
    public static func isContainer(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 4)
        guard head.count == 4 else { return false }
        let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return magic == selfMagic || magic == selfMagicKernel
    }

    /// Unwraps `input` into `output`; returns the ELF's size.
    @discardableResult
    public static func unwrap(_ input: URL, to output: URL) throws -> Int {
        if input.standardizedFileURL.resolvingSymlinksInPath() == output.standardizedFileURL.resolvingSymlinksInPath() {
            throw Refused(reason: "output aliases the input container")
        }
        let data = [UInt8](try Data(contentsOf: input, options: .alwaysMapped))
        let result = try unwrap(data)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(result).write(to: output)
        return result.count
    }

    final class Header {
        let index: Int
        let type: UInt32
        let flags: UInt32
        let offset: UInt64
        let vaddr: UInt64
        var size: UInt64
        var memory: UInt64
        let align: UInt64
        var source: UInt64
        var placed: UInt64 = 0
        /// The PT_LOAD whose bytes this segment lies in, when it was placed by its vaddr.
        var host: Header?

        init(index: Int, type: UInt32, flags: UInt32, offset: UInt64, vaddr: UInt64, size: UInt64, memory: UInt64, align: UInt64) {
            self.index = index
            self.type = type
            self.flags = flags
            self.offset = offset
            self.vaddr = vaddr
            self.size = size
            self.memory = memory
            self.align = align
            self.source = offset
        }
    }

    struct Record {
        let flags: UInt64
        let segment: UInt64
        let size: UInt64
    }

    final class Region {
        let old: UInt64
        let size: UInt64
        let vaddr: UInt64
        let align: UInt64
        var new: UInt64 = 0

        init(old: UInt64, size: UInt64, vaddr: UInt64, align: UInt64) {
            self.old = old
            self.size = size
            self.vaddr = vaddr
            self.align = align
        }
    }

    static func u16(_ data: [UInt8], _ at: Int) -> UInt16 {
        UInt16(data[at]) | UInt16(data[at + 1]) << 8
    }

    static func u32(_ data: [UInt8], _ at: Int) -> UInt32 {
        var value: UInt32 = 0
        for byte in 0..<4 { value |= UInt32(data[at + byte]) << (8 * UInt32(byte)) }
        return value
    }

    static func u64(_ data: [UInt8], _ at: Int) -> UInt64 {
        var value: UInt64 = 0
        for byte in 0..<8 { value |= UInt64(data[at + byte]) << (8 * UInt64(byte)) }
        return value
    }

    static func put16(_ data: inout [UInt8], _ at: Int, _ value: UInt16) {
        for byte in 0..<2 { data[at + byte] = UInt8(truncatingIfNeeded: value >> (8 * UInt16(byte))) }
    }

    static func put32(_ data: inout [UInt8], _ at: Int, _ value: UInt32) {
        for byte in 0..<4 { data[at + byte] = UInt8(truncatingIfNeeded: value >> (8 * UInt32(byte))) }
    }

    static func put64(_ data: inout [UInt8], _ at: Int, _ value: UInt64) {
        for byte in 0..<8 { data[at + byte] = UInt8(truncatingIfNeeded: value >> (8 * UInt64(byte))) }
    }

    static func entropy(_ data: ArraySlice<UInt8>) -> Double {
        guard !data.isEmpty else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        for byte in data { counts[Int(byte)] += 1 }
        let length = Double(data.count)
        var total = 0.0
        for count in counts where count != 0 {
            let share = Double(count) / length
            total -= share * log2(share)
        }
        return total
    }

    static func readRecords(_ data: [UInt8]) -> [Record] {
        var records: [Record] = []
        var offset = recordOffset
        let length = UInt64(data.count)
        while offset + recordSize <= firstRegion {
            let flags = u64(data, offset)
            let segment = u64(data, offset + 8)
            let size = u64(data, offset + 16)
            let sizeAgain = u64(data, offset + 24)
            if size == 0 || size != sizeAgain { break }
            if segment >= length || segment < 0x350 || segment % 0x10 != 0 { break }
            if size > length { break }
            records.append(Record(flags: flags, segment: segment, size: size))
            offset += recordSize
        }
        return records
    }

    /// The smallest offset at or after `cursor` congruent to `vaddr` modulo `alignment` (a power
    /// of two, or 1): Python's `cursor + (vaddr - cursor) % alignment`.
    static func placement(cursor: UInt64, vaddr: UInt64, alignment: UInt64) -> UInt64 {
        guard alignment > 1 else { return cursor }
        return cursor + ((vaddr &- cursor) & (alignment - 1))
    }

    static func findElf(_ data: [UInt8]) -> Int? {
        let magic: [UInt8] = [0x7F, 0x45, 0x4C, 0x46]
        guard data.count >= 4 else { return nil }
        for start in 0...(data.count - 4) where data[start] == 0x7F && data[start + 1] == magic[1] && data[start + 2] == magic[2] && data[start + 3] == magic[3] {
            return start
        }
        return nil
    }

    static func parseElf(_ data: [UInt8]) throws -> (inner: Int, header: [UInt8], headers: [Header]) {
        guard let inner = findElf(data) else { throw Refused(reason: "no inner ELF header") }
        if inner + 0x40 > data.count { throw Refused(reason: "inner ELF header is truncated") }
        let header = Array(data[inner..<(inner + 0x40)])
        if header[4] != 2 || header[5] != 1 { throw Refused(reason: "inner ELF is not 64-bit little-endian") }
        let programOffset = u64(header, 0x20)
        let entrySize = u16(header, 0x36)
        let count = Int(u16(header, 0x38))
        if entrySize != 56 || count == 0 { throw Refused(reason: "program header table is \(count) entries of \(entrySize) bytes") }
        if programOffset < UInt64(header.count) { throw Refused(reason: "ELF program header table overlaps the ELF header") }
        let (tableEnd, overflow) = UInt64(inner).addingReportingOverflow(programOffset)
        if overflow || tableEnd + UInt64(count * 56) > UInt64(data.count) { throw Refused(reason: "ELF program header table does not fit the file") }
        var headers: [Header] = []
        for index in 0..<count {
            let at = inner + Int(programOffset) + index * 56
            let kind = u32(data, at)
            let flags = u32(data, at + 4)
            let fileOffset = u64(data, at + 8)
            let vaddr = u64(data, at + 16)
            let fileSize = u64(data, at + 32)
            let memorySize = u64(data, at + 40)
            let alignment = u64(data, at + 48)
            if kind == ptLoad {
                if fileSize > memorySize { throw Refused(reason: "segment \(index) file size exceeds memory size") }
                if alignment != 0 && alignment & (alignment - 1) != 0 { throw Refused(reason: "segment \(index) alignment is not a power of two") }
                let (sum, wrapped) = vaddr.addingReportingOverflow(memorySize)
                if wrapped && sum != 0 { throw Refused(reason: "segment \(index) memory range exceeds ELF64") }
            }
            headers.append(Header(index: index, type: kind, flags: flags, offset: fileOffset, vaddr: vaddr, size: fileSize, memory: memorySize, align: alignment))
        }
        return (inner, header, headers)
    }

    static func placeSegments(_ data: [UInt8], _ headers: [Header], _ records: [Record]) throws {
        let length = UInt64(data.count)
        let loads = headers.filter { $0.type == ptLoad }
        var used = Set<Int>()
        var placed = Set<Int>()
        for (index, record) in records.enumerated() {
            let target = Int(truncatingIfNeeded: record.flags >> recordSegmentShift)
            if record.flags & recordHasSegment != 0 && target >= 0 && target < headers.count && !placed.contains(target) && headers[target].size == record.size {
                headers[target].source = record.segment
                placed.insert(target)
                used.insert(index)
            }
        }
        let recorded = headers.filter { placed.contains($0.index) && $0.vaddr == 0 && $0.type != ptLoad }
        if let last = recorded.max(by: { $0.offset < $1.offset }) {
            var cursor = last.source + last.size
            let trailing = headers.filter { !placed.contains($0.index) && $0.vaddr == 0 && $0.type != ptLoad && $0.size != 0 && $0.offset > last.offset }
            for header in trailing.sorted(by: { $0.offset < $1.offset }) {
                placed.insert(header.index)
                if header.type == ptNote {
                    header.source = 0
                    header.size = 0
                    continue
                }
                header.source = cursor
                cursor += header.size
                if cursor > length {
                    header.source = 0
                    header.size = 0
                }
            }
        }
        for header in loads {
            if header.size == 0 || placed.contains(header.index) { continue }
            for (index, record) in records.enumerated() where !used.contains(index) && record.size == header.size {
                used.insert(index)
                header.source = record.segment
                break
            }
        }

        func loadFor(_ vaddr: UInt64, _ size: UInt64) -> Header? {
            var found: Header?
            for header in loads {
                let end = header.vaddr &+ header.memory
                if header.memory != 0 && header.vaddr <= vaddr && (vaddr < end || (size == 0 && vaddr == end)) {
                    found = header
                }
            }
            return found
        }

        // (offset in the ELF, shift to the container offset) of the last placed segment.
        var tail: (offset: UInt64, shift: Int64)?
        for header in headers {
            if header.type == ptLoad { continue }
            if placed.contains(header.index) {
                if header.size != 0 && (tail == nil || header.offset > tail!.offset) {
                    tail = (header.offset, Int64(bitPattern: header.source &- header.offset))
                }
                continue
            }
            if header.vaddr != 0 {
                guard let host = loadFor(header.vaddr, header.size) else {
                    if header.size == 0 {
                        header.source = 0
                        continue
                    }
                    throw Refused(reason: "segment \(header.index) vaddr 0x\(String(header.vaddr, radix: 16)) is in no PT_LOAD")
                }
                let offset = header.vaddr - host.vaddr
                if header.size != 0 && (offset > host.size || header.size > host.size - offset) {
                    throw Refused(reason: "segment \(header.index) does not fit the file-backed range of PT_LOAD \(host.index)")
                }
                // In the part of the PT_LOAD with no file bytes (.bss): nothing to copy.
                if host.size == 0 || offset > host.size {
                    header.source = 0
                    continue
                }
                header.host = host
                header.source = host.source + offset
                if tail == nil || header.offset > tail!.offset {
                    tail = (header.offset, Int64(bitPattern: header.source &- header.offset))
                }
            } else if header.size != 0 {
                header.source = header.offset &+ UInt64(bitPattern: tail?.shift ?? 0)
                if header.source > length { header.source = length }
                let keep = length - header.source
                header.size = min(header.size, keep)
                header.memory = min(header.memory, keep)
            }
        }

        for header in headers {
            if header.type == ptLoad && header.size == 0 { continue }
            if header.source > length || header.size > length - header.source {
                throw Refused(reason: "segment \(header.index) does not fit the file")
            }
        }
    }

    static func checkDecrypted(_ data: [UInt8], _ headers: [Header]) throws {
        var encrypted: [(Int, UInt64, Double)] = []
        let loaded = headers.filter { $0.type == ptLoad && $0.size != 0 }
        for header in loaded {
            let start = Int(header.source)
            let end = start + Int(min(header.size, UInt64(entropySample)))
            let value = entropy(data[start..<end])
            if value >= entropyLimit { encrypted.append((header.index, header.source, value)) }
        }
        if !encrypted.isEmpty && encrypted.count == loaded.count {
            let listed = encrypted.map { String(format: "segment %d at 0x%llx (%.2f bits per byte)", $0.0, $0.1, $0.2) }.joined(separator: ", ")
            throw Refused(reason: "every load segment looks encrypted: " + listed)
        }
    }

    public static func unwrap(_ data: [UInt8]) throws -> [UInt8] {
        if data.count < firstRegion { throw Refused(reason: "file is smaller than the SELF header area") }
        let magic = u32(data, 0)
        if magic != selfMagic && magic != selfMagicKernel {
            throw Refused(reason: "not a SELF container (magic 0x\(String(magic, radix: 16)))")
        }

        let records = readRecords(data)
        let (_, elfHeader, headers) = try parseElf(data)
        try placeSegments(data, headers, records)
        try checkDecrypted(data, headers)

        var regions: [Region] = []
        // Each PT_LOAD's own region: segments inside it move with it, even where load
        // segments overlap in the container.
        var loadRegions: [Int: Region] = [:]
        for header in headers where header.type == ptLoad && header.size != 0 {
            let region = Region(old: header.source, size: header.size, vaddr: header.vaddr, align: header.align)
            regions.append(region)
            loadRegions[header.index] = region
        }

        func regionFor(_ offset: UInt64, _ size: UInt64) -> Region? {
            regions.first { $0.old <= offset && offset + size <= $0.old + $0.size }
        }

        for header in headers where header.type != ptLoad && header.size != 0 {
            if regionFor(header.source, header.size) == nil {
                regions.append(Region(old: header.source, size: header.size, vaddr: header.vaddr, align: header.align))
            }
        }

        // Stable, as Python's sort is: regions with the same container offset keep their order.
        regions = regions.enumerated().sorted { $0.element.old != $1.element.old ? $0.element.old < $1.element.old : $0.offset < $1.offset }.map(\.element)
        let programOffset = u64(elfHeader, 0x20)
        var cursor = max(UInt64(firstRegion), programOffset + UInt64(headers.count * 56))
        var padding: UInt64 = 0
        for region in regions {
            let alignment = region.align != 0 && region.align & (region.align - 1) == 0 ? region.align : 1
            // The first offset from the cursor on with offset % align == vaddr % align, as
            // tools/unwrap_self.py does it (not rounded up to the alignment first).
            let placed = placement(cursor: cursor, vaddr: region.vaddr, alignment: alignment)
            padding += placed - cursor
            region.new = placed
            cursor = placed + region.size
        }

        var emptyEnd = cursor
        for header in headers where header.type == ptLoad && header.size == 0 {
            emptyEnd = max(emptyEnd, header.vaddr % max(header.align, 1))
        }
        padding += emptyEnd - cursor
        if padding > UInt64(maxAlignmentPadding) {
            throw Refused(reason: "segment alignment requires more than \(maxAlignmentPadding) bytes of output padding")
        }
        cursor = emptyEnd

        var result = [UInt8](repeating: 0, count: Int(cursor))
        for region in regions {
            let from = Int(region.old)
            let to = Int(region.new)
            result.replaceSubrange(to..<(to + Int(region.size)), with: data[from..<(from + Int(region.size))])
        }

        for header in headers {
            if header.size == 0 && (header.type == ptLoad || header.source == 0) {
                header.placed = header.type == ptLoad ? header.vaddr % max(header.align, 1) : 0
                continue
            }
            let host = header.type == ptLoad ? header : header.host
            if let region = host.flatMap({ loadRegions[$0.index] }) ?? regionFor(header.source, header.size) {
                header.placed = region.new + (header.source - region.old)
            } else {
                header.placed = header.source
            }
            if header.placed + header.size > UInt64(result.count) {
                throw Refused(reason: "segment \(header.index) escaped the output")
            }
        }

        result.replaceSubrange(0..<0x40, with: elfHeader)
        put64(&result, 0x28, 0)
        put16(&result, 0x3C, 0)
        put16(&result, 0x3E, 0)
        for header in headers {
            let at = Int(programOffset) + header.index * 56
            put32(&result, at, header.type)
            put32(&result, at + 4, header.flags)
            put64(&result, at + 8, header.placed)
            put64(&result, at + 16, header.vaddr)
            put64(&result, at + 24, header.vaddr)
            put64(&result, at + 32, header.size)
            put64(&result, at + 40, header.memory)
            put64(&result, at + 48, header.align)
        }
        return result
    }
}
