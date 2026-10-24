import Compression
import Foundation

/// Reads files out of an Unreal Engine .pak (versions 3 to 11, UE 4.x and 5.x): the footer, the
/// index (the old list, or the path hash and full directory indexes of 4.26 and later) and the
/// files, stored or compressed with zlib. An encrypted index, encrypted files and compression
/// other than zlib (Oodle) cannot be read without what the game keeps to itself.
public struct UnrealPak {
    public static let magic: UInt32 = 0x5A6F_12E1

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    struct Entry {
        var offset: Int64
        var size: Int64
        var uncompressedSize: Int64
        var method: Int
        var encrypted: Bool
        /// Compressed blocks, from and to, from the entry's start.
        var blocks: [(Int64, Int64)]
        var headerSize: Int64
    }

    public let url: URL
    public let version: Int
    let methods: [String]
    let entries: [String: Entry]

    /// The paths of the files in the pak, mount point included.
    public var paths: [String] { Array(entries.keys) }

    public init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = Int64(try handle.seekToEnd())
        let tailLength = min(length, 1024)
        let tail = try Self.read(handle, at: length - tailLength, count: Int(tailLength))
        // The footer's length differs between versions: its magic is looked for from the end.
        var found: (position: Int, version: Int)?
        var position = tail.count - 4
        while position >= 0, found == nil {
            if tail.le32(position) == Self.magic, position + 8 <= tail.count {
                let version = Int(tail.le32(position + 4))
                if (3...11).contains(version), position + 44 <= tail.count { found = (position, version) }
            }
            position -= 1
        }
        guard let footer = found else { throw Failure(description: "not an Unreal pak") }
        version = footer.version
        if version >= 4, footer.position >= 1, tail[tail.startIndex + footer.position - 1] != 0 {
            throw Failure(description: "the pak's index is encrypted")
        }
        let indexOffset = tail.le64(footer.position + 8)
        let indexSize = tail.le64(footer.position + 16)
        var names: [String] = []
        var cursor = footer.position + 44 + (version == 9 ? 1 : 0)
        if version >= 8 {
            while cursor + 32 <= tail.count {
                let slot = tail.subdata(in: tail.startIndex + cursor ..< tail.startIndex + cursor + 32)
                names.append(String(decoding: slot.prefix { $0 != 0 }, as: UTF8.self))
                cursor += 32
            }
        }
        methods = names
        guard indexOffset >= 0, indexSize > 0, indexOffset + indexSize <= length, indexSize < 1 << 30 else { throw Failure(description: "the pak's index is out of the file") }
        var index = Reader(try Self.read(handle, at: indexOffset, count: Int(indexSize)))
        let mount = try index.string()
        if version < 10 {
            let count = try index.int32()
            var entries: [String: Entry] = [:]
            for _ in 0 ..< max(0, count) {
                let name = try index.string()
                entries[Self.join(mount, name)] = try Self.entry(&index, version: version)
            }
            self.entries = entries
            return
        }
        _ = try index.int32()
        _ = try index.uint64()
        if try index.uint32() != 0 {
            _ = try index.int64()
            _ = try index.int64()
            try index.skip(20)
        }
        guard try index.uint32() != 0 else { throw Failure(description: "the pak has no directory index") }
        let directoryOffset = try index.int64()
        let directorySize = try index.int64()
        try index.skip(20)
        let encoded = try index.bytes(Int(try index.int32()))
        let unencodedCount = try index.int32()
        var unencoded: [Entry] = []
        for _ in 0 ..< max(0, unencodedCount) { unencoded.append(try Self.entry(&index, version: version)) }
        guard directoryOffset >= 0, directorySize > 0, directoryOffset + directorySize <= length, directorySize < 1 << 30 else { throw Failure(description: "the pak's directory index is out of the file") }
        var directory = Reader(try Self.read(handle, at: directoryOffset, count: Int(directorySize)))
        var entries: [String: Entry] = [:]
        for _ in 0 ..< max(0, try directory.int32()) {
            let folder = try directory.string()
            for _ in 0 ..< max(0, try directory.int32()) {
                let name = try directory.string()
                let location = Int(try directory.int32())
                let entry: Entry?
                if location >= 0 {
                    var reader = Reader(encoded, at: location)
                    entry = try? Self.decode(&reader, version: version)
                } else {
                    entry = unencoded.indices.contains(-location - 1) ? unencoded[-location - 1] : nil
                }
                if let entry { entries[Self.join(mount, folder + name)] = entry }
            }
        }
        self.entries = entries
    }

    /// The file whose path ends with `suffix` (no matter the case), nil when there is none or it
    /// cannot be read.
    public func file(endingWith suffix: String) -> Data? {
        let lower = suffix.lowercased()
        guard let path = entries.keys.filter({ $0.lowercased().hasSuffix(lower) }).min(by: { $0.count < $1.count }) else { return nil }
        return try? file(path)
    }

    public func file(_ path: String) throws -> Data {
        guard let entry = entries[path] else { throw Failure(description: "\(path) is not in the pak") }
        guard !entry.encrypted else { throw Failure(description: "\(path) is encrypted") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if entry.method == 0 {
            return try Self.read(handle, at: entry.offset + entry.headerSize, count: Int(entry.size))
        }
        let name = entry.method - 1 < methods.count && entry.method >= 1 ? methods[entry.method - 1].lowercased() : (version < 8 && entry.method == 1 ? "zlib" : "")
        guard name == "zlib" else { throw Failure(description: "\(path) is compressed with \(name.isEmpty ? "an unknown method" : name)") }
        var data = Data()
        for (start, end) in entry.blocks {
            let block = try Self.read(handle, at: entry.offset + start, count: Int(end - start))
            data += try Self.inflate(block, limit: Int(entry.uncompressedSize) - data.count)
        }
        return data
    }

    // MARK: Entries

    /// An entry as the old index and every file's own header write it.
    static func entry(_ reader: inout Reader, version: Int) throws -> Entry {
        let offset = try reader.int64()
        let size = try reader.int64()
        let uncompressed = try reader.int64()
        let method = version < 8 ? Int(try reader.int32()) & 0x0F : Int(try reader.uint32())
        if version <= 1 { _ = try reader.int64() }
        try reader.skip(20)
        var blocks: [(Int64, Int64)] = []
        if method != 0 {
            for _ in 0 ..< max(0, try reader.int32()) { blocks.append((try reader.int64(), try reader.int64())) }
        }
        let flags = try reader.uint8()
        _ = try reader.uint32()
        // Before version 5 block positions count from the start of the pak.
        if version < 5 { blocks = blocks.map { ($0.0 - offset, $0.1 - offset) } }
        return Entry(offset: offset, size: size, uncompressedSize: uncompressed, method: method, encrypted: flags & 1 != 0, blocks: blocks,
                     headerSize: headerSize(version: version, compressed: method != 0, blocks: blocks.count))
    }

    /// An entry packed into a few bytes, as the index of 4.26 and later keeps most of them.
    static func decode(_ reader: inout Reader, version: Int) throws -> Entry {
        let bits = try reader.uint32()
        let blockSize = bits & 0x3F == 0x3F ? Int64(try reader.uint32()) : Int64(bits & 0x3F) << 11
        _ = blockSize
        let blockCount = Int((bits >> 6) & 0xFFFF)
        let encrypted = (bits >> 22) & 1 != 0
        let method = Int((bits >> 23) & 0x3F)
        let offset = bits & (1 << 31) != 0 ? Int64(try reader.uint32()) : try reader.int64()
        let uncompressed = bits & (1 << 30) != 0 ? Int64(try reader.uint32()) : try reader.int64()
        let size = method == 0 ? uncompressed : (bits & (1 << 29) != 0 ? Int64(try reader.uint32()) : try reader.int64())
        let header = headerSize(version: version, compressed: method != 0, blocks: blockCount)
        var blocks: [(Int64, Int64)] = []
        if blockCount == 1 && !encrypted {
            blocks = [(header, header + size)]
        } else if blockCount > 0 {
            var start = header
            for _ in 0 ..< blockCount {
                let length = Int64(try reader.uint32())
                blocks.append((start, start + length))
                start += encrypted ? (length + 15) & ~15 : length
            }
        }
        return Entry(offset: offset, size: size, uncompressedSize: uncompressed, method: method, encrypted: encrypted, blocks: blocks, headerSize: header)
    }

    /// The length of the header written before each file's bytes.
    static func headerSize(version: Int, compressed: Bool, blocks: Int) -> Int64 {
        var size: Int64 = 8 + 8 + 8 + 4 + 20
        if version <= 1 { size += 8 }
        if compressed { size += 4 + 16 * Int64(blocks) }
        return size + 1 + 4
    }

    static func join(_ mount: String, _ path: String) -> String {
        var mount = mount
        while mount.hasPrefix("../") { mount.removeFirst(3) }
        if mount.hasPrefix("/") { mount.removeFirst() }
        return mount + path
    }

    static func read(_ handle: FileHandle, at offset: Int64, count: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw Failure(description: "the pak ends early") }
        return data
    }

    /// Unreal's zlib blocks carry the zlib header and checksum around raw deflate.
    static func inflate(_ block: Data, limit: Int) throws -> Data {
        guard block.count > 6, limit > 0 else { throw Failure(description: "a broken compressed block") }
        let deflated = block.subdata(in: block.startIndex + 2 ..< block.endIndex)
        var output = Data(count: limit)
        let written = output.withUnsafeMutableBytes { target in
            deflated.withUnsafeBytes { source in
                compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, limit, source.bindMemory(to: UInt8.self).baseAddress!, deflated.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw Failure(description: "a broken compressed block") }
        return output.prefix(written)
    }
}

/// Little-endian reading through bytes, failing past their end.
struct Reader {
    let data: Data
    var position: Int

    init(_ data: Data, at position: Int = 0) {
        self.data = data
        self.position = position
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, position + count <= data.count else { throw UnrealPak.Failure(description: "the index ends early") }
        position += count
    }

    mutating func bytes(_ count: Int) throws -> Data {
        let start = position
        try skip(count)
        return data.subdata(in: data.startIndex + start ..< data.startIndex + position)
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let bytes = try bytes(MemoryLayout<T>.size)
        return T(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) })
    }

    mutating func uint8() throws -> UInt8 { try integer(UInt8.self) }
    mutating func uint32() throws -> UInt32 { try integer(UInt32.self) }
    mutating func int32() throws -> Int32 { try integer(Int32.self) }
    mutating func uint64() throws -> UInt64 { try integer(UInt64.self) }
    mutating func int64() throws -> Int64 { try integer(Int64.self) }

    /// Unreal's FString: a length counting the final zero, negative for UTF-16.
    mutating func string() throws -> String {
        let length = Int(try int32())
        if length == 0 { return "" }
        if length > 0 {
            guard length < 1 << 16 else { throw UnrealPak.Failure(description: "a name of \(length) bytes") }
            return String(decoding: try bytes(length).dropLast(), as: UTF8.self)
        }
        guard -length < 1 << 16 else { throw UnrealPak.Failure(description: "a name of \(-length) characters") }
        let raw = try bytes(-length * 2)
        let units = stride(from: 0, to: raw.count - 2, by: 2).map { UInt16(raw[raw.startIndex + $0]) | UInt16(raw[raw.startIndex + $0 + 1]) << 8 }
        return String(decoding: units, as: UTF16.self)
    }
}

extension Data {
    func le32(_ offset: Int) -> UInt32 { UInt32(littleEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }) }
    func le64(_ offset: Int) -> Int64 { Int64(littleEndian: withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int64.self) }) }
}
