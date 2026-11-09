import Foundation

/// Why a .ffpfsc is not unpacked though it reads as one: the two the launcher can say for sure,
/// unlike a file that is damaged or still being copied.
public enum ArchiveProblem: String, Sendable, Equatable {
    /// Its PFSC blocks are compressed. AnyDevKit's packager never writes those, other tools do.
    case compressed
    /// A layout the launcher does not read: signed, encrypted, 64-bit inodes, or any other than
    /// the one AnyDevKit's FfpfscPackager writes.
    case unsupported
}

/// A game in one file, as AnyDevKit's FfpfscPackager writes it: an outer PFS image with a single
/// file `pfs_image.dat`, that file a PFSC container of stored (never compressed) 64 KiB blocks,
/// and in them an inner PFS image holding the dump. So the inner image's bytes are one contiguous
/// slice of the file, and each game file is one contiguous slice of that.
///
/// Everything about the file is untrusted: every count, offset and size is bounded against the
/// file before use, no read is larger than the bounds below, each inode is visited once (a
/// directory cannot loop and two names cannot share one file), and the bytes the files come to
/// can never exceed the image they sit in. A name that would land outside the game's folder, or a
/// link, is listed in `refused` as a zip's is; anything else out of shape is refused whole.
enum Ffpfsc {
    static let maxDirectoryBytes = 16 * 1024 * 1024
    /// All directories together: a file cannot make the reader hold more than this.
    static let maxTotalDirectoryBytes = 64 * 1024 * 1024
    static let maxEntries = 500_000
    static let maxInodes: Int64 = 2_000_000
    static let maxDepth = 32
    static let maxPath = 1024
    static let maxParameters = 1024 * 1024
    static let maxIcon = 8 * 1024 * 1024
    static let maxIconSide: UInt32 = 4096

    static let pfscMagic: UInt64 = 0x4353_4650
    static let pfscBlock: Int64 = 0x10000
    static let inodeSize: Int64 = 0xA8
    static let tableChunk = 0x10000

    enum Failure: Error, Equatable {
        case damaged(String)
        case compressed
        case unsupported(String)
    }

    static func matches(_ url: URL) -> Bool { url.pathExtension.lowercased() == "ffpfsc" }

    /// Little-endian `width` bytes at `at` as an unsigned value; the caller has checked the bounds.
    fileprivate static func le(_ bytes: [UInt8], _ at: Int, _ width: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<width { value |= UInt64(bytes[at + index]) << (UInt64(index) * 8) }
        return value
    }

    /// A u64 field as a signed size; one past 2^63 cannot be a real size or offset.
    fileprivate static func size(_ bytes: [UInt8], _ at: Int) throws -> Int64 {
        guard let value = Int64(exactly: le(bytes, at, 8)) else { throw Failure.damaged("a size is out of range") }
        return value
    }

    /// The file opened to read, its bytes read at an offset with `pread`.
    final class Source {
        let descriptor: Int32
        let length: Int64

        init(_ url: URL) throws {
            let opened = open(url.path, O_RDONLY)
            guard opened >= 0 else { throw Failure.damaged("cannot be opened: \(String(cString: strerror(errno)))") }
            var info = stat()
            guard fstat(opened, &info) == 0 else {
                let reason = String(cString: strerror(errno))
                close(opened)
                throw Failure.damaged("cannot be read: \(reason)")
            }
            descriptor = opened
            length = Int64(info.st_size)
        }

        deinit { close(descriptor) }

        func fill(_ offset: Int64, _ buffer: UnsafeMutableRawBufferPointer) throws {
            var position = offset
            var remaining = buffer.count
            var cursor = buffer.baseAddress!
            while remaining > 0 {
                let count = pread(descriptor, cursor, remaining, off_t(position))
                if count < 0 { throw Failure.damaged("cannot be read: \(String(cString: strerror(errno)))") }
                if count == 0 { throw Failure.damaged("ends early") }
                position += Int64(count)
                remaining -= count
                cursor = cursor.advanced(by: count)
            }
        }

        func bytes(_ offset: Int64, _ count: Int) throws -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: count)
            if count > 0 { try buffer.withUnsafeMutableBytes { try fill(offset, $0) } }
            return buffer
        }
    }

    /// A range of the file; every read is bounded against the range.
    struct Slice {
        let source: Source
        let base: Int64
        let length: Int64

        func checked(_ offset: Int64, _ count: Int64) throws {
            guard offset >= 0, count >= 0, offset <= length, count <= length - offset else {
                throw Failure.damaged("a read lands past the end")
            }
        }

        func bytes(at offset: Int64, _ count: Int) throws -> [UInt8] {
            try checked(offset, Int64(count))
            return try source.bytes(base + offset, count)
        }
    }

    struct Inode {
        let number: Int64
        let mode: Int
        let flags: UInt32
        let size: Int64
        let blocks: Int64
        let start: Int64

        var isDirectory: Bool { mode & 0xF000 == 0x4000 }
        var isRegular: Bool { mode & 0xF000 == 0x8000 }
        var isLink: Bool { mode & 0xF000 == 0xA000 }
    }

    struct Entry {
        let inode: Int64
        let type: Int
        let name: [UInt8]
    }

    /// One PFS image, its header checked, its inodes and directories read on demand.
    final class Image {
        let slice: Slice
        let blockSize: Int64
        let inodes: Int64
        let blocks: Int64
        let inodeBlocks: Int64
        let perBlock: Int64

        init(_ slice: Slice) throws {
            guard slice.length >= 0x400 else { throw Failure.damaged("too short for a PFS header") }
            let header = try slice.bytes(at: 0, 0x400)
            guard Ffpfsc.le(header, 0, 8) == 2, Ffpfsc.le(header, 8, 8) == 20_130_315 else {
                throw Failure.damaged("not a PFS image")
            }
            let mode = Ffpfsc.le(header, 0x1C, 2)
            guard mode & ~UInt64(8) == 0 else { throw Failure.unsupported("signed, encrypted or 64-bit PFS") }
            let block = Ffpfsc.le(header, 0x20, 4)
            guard block >= 0x1000, block <= 0x100000, block & (block - 1) == 0 else {
                throw Failure.unsupported("block size \(block)")
            }
            let blockSize = Int64(block)
            let inodes = try Ffpfsc.size(header, 0x30)
            let blocks = try Ffpfsc.size(header, 0x38)
            let inodeBlocks = try Ffpfsc.size(header, 0x40)
            let perBlock = blockSize / Ffpfsc.inodeSize
            guard inodes >= 3, inodes <= Ffpfsc.maxInodes, inodeBlocks >= 1, inodeBlocks <= Ffpfsc.maxInodes else {
                throw Failure.damaged("impossible inode count")
            }
            guard inodes <= inodeBlocks * perBlock else { throw Failure.damaged("more inodes than the table holds") }
            guard blocks > inodeBlocks, blocks <= slice.length / blockSize else {
                throw Failure.damaged("the image is larger than the file")
            }
            self.slice = slice
            self.blockSize = blockSize
            self.inodes = inodes
            self.blocks = blocks
            self.inodeBlocks = inodeBlocks
            self.perBlock = perBlock
        }

        func inode(_ number: Int64) throws -> Inode {
            guard number >= 0, number < inodes else { throw Failure.damaged("an inode number is out of range") }
            let bytes = try slice.bytes(at: (1 + number / perBlock) * blockSize + (number % perBlock) * Ffpfsc.inodeSize, Int(Ffpfsc.inodeSize))
            let size = try Ffpfsc.size(bytes, 8)
            let count = Int64(Ffpfsc.le(bytes, 0x60, 4))
            let start = Int64(Ffpfsc.le(bytes, 0x64, 4))
            for pointer in 1..<12 where Ffpfsc.le(bytes, 0x64 + pointer * 4, 4) != 0xFFFF_FFFF {
                throw Failure.unsupported("a file not in one piece")
            }
            guard count >= 1, count <= blocks, start > inodeBlocks, start <= blocks - count, size >= 0, size <= count * blockSize else {
                throw Failure.damaged("an inode is out of range")
            }
            return Inode(number: number, mode: Int(Ffpfsc.le(bytes, 0, 2)), flags: UInt32(Ffpfsc.le(bytes, 4, 4)), size: size, blocks: count, start: start)
        }

        func offset(_ inode: Inode) -> Int64 { inode.start * blockSize }

        /// A directory's entries; `budget` is what is left of `maxTotalDirectoryBytes`.
        func entries(of directory: Inode, budget: inout Int) throws -> [Entry] {
            guard directory.isDirectory else { throw Failure.damaged("expected a directory") }
            guard directory.size <= Int64(Ffpfsc.maxDirectoryBytes), directory.size <= Int64(budget) else {
                throw Failure.damaged("a directory is too large")
            }
            budget -= Int(directory.size)
            let data = try slice.bytes(at: offset(directory), Int(directory.size))
            var result: [Entry] = []
            var position = 0
            while position + 16 <= data.count {
                let inode = Int64(Ffpfsc.le(data, position, 4))
                let type = Int(Ffpfsc.le(data, position + 4, 4))
                let length = Int(Ffpfsc.le(data, position + 8, 4))
                let size = Int(Ffpfsc.le(data, position + 12, 4))
                if size == 0 { break }
                guard length >= 1, length <= 255, size >= 16 + length, size <= data.count - position else {
                    throw Failure.damaged("a directory entry is out of range")
                }
                result.append(Entry(inode: inode, type: type, name: Array(data[(position + 16)..<(position + 16 + length)])))
                position += size
            }
            return result
        }

        /// The `uroot` directory, found through the super-root (inode 0).
        func root(budget: inout Int) throws -> Inode {
            let top = try inode(0)
            guard let uroot = try entries(of: top, budget: &budget).first(where: { $0.type == 3 && $0.name == Array("uroot".utf8) }) else {
                throw Failure.damaged("no uroot directory")
            }
            let root = try inode(uroot.inode)
            guard root.isDirectory else { throw Failure.damaged("uroot is no directory") }
            return root
        }
    }

    /// The slice of the outer image the inner image's bytes are, once its PFSC header and table
    /// are shown to be stored blocks.
    static func innerSlice(_ outer: Image, _ inode: Inode, _ source: Source) throws -> Slice {
        let start = outer.offset(inode)
        guard inode.size >= 0x30 else { throw Failure.damaged("pfs_image.dat is too short") }
        let header = try outer.slice.bytes(at: start, 0x30)
        guard le(header, 0, 4) == pfscMagic else { throw Failure.damaged("no PFSC header") }
        guard le(header, 12, 4) == UInt64(pfscBlock), le(header, 16, 8) == UInt64(pfscBlock) else {
            throw Failure.unsupported("a PFSC block size other than 64 KiB")
        }
        let table = try size(header, 24)
        let dataStart = try size(header, 32)
        let dataLength = try size(header, 40)
        guard dataLength > 0, dataLength % pfscBlock == 0, table >= 0x30, dataStart >= 0, dataStart <= inode.size, dataLength <= inode.size - dataStart else {
            throw Failure.damaged("the PFSC header is out of range")
        }
        let count = dataLength / pfscBlock
        let tableBytes = (count + 1) * 8
        guard table <= dataStart, tableBytes <= dataStart - table else { throw Failure.damaged("the PFSC table is out of range") }
        var previous: Int64 = -1
        var compressed = false
        var position = start + table
        var remaining = tableBytes
        var first = true
        while remaining > 0 {
            let chunk = Int(min(Int64(tableChunk), remaining))
            let bytes = try outer.slice.bytes(at: position, chunk)
            for index in stride(from: 0, to: chunk, by: 8) {
                let value = try size(bytes, index)
                if first {
                    guard value == dataStart else { throw Failure.damaged("the PFSC table starts in the wrong place") }
                    first = false
                } else {
                    let delta = value - previous
                    guard delta > 0, delta <= pfscBlock else { throw Failure.damaged("the PFSC table is out of order") }
                    if delta < pfscBlock { compressed = true }
                }
                previous = value
            }
            position += Int64(chunk)
            remaining -= Int64(chunk)
        }
        if compressed { throw Failure.compressed }
        return Slice(source: source, base: outer.slice.base + start + dataStart, length: dataLength)
    }

    /// What a .ffpfsc holds: the walk's result, offsets being from the start of the file.
    struct Manifest {
        struct Item {
            let path: String
            let directory: Bool
            let offset: Int64
            let size: Int64
        }

        var items: [Item] = []
        var refused: [String] = []
        var files = 0
        var size: Int64 = 0
    }

    private static let reserved: Set<String> = Set(["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] })

    /// The name when it is safe as one path component on every system, else nil.
    static func safeName(_ raw: [UInt8]) -> String? {
        guard raw.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { return nil }
        let name = String(decoding: raw, as: UTF8.self)
        guard !name.contains("/"), !name.contains("\\"), !name.hasSuffix("."), !name.hasSuffix(" "), GameArchives.safeParts(name)?.count == 1 else { return nil }
        let stem = name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        return reserved.contains(stem.uppercased()) ? nil : name
    }

    /// Reads and bounds the image at `source`, and walks its files.
    static func read(_ source: Source) throws -> Manifest {
        let outer = try Image(Slice(source: source, base: 0, length: source.length))
        var budget = maxTotalDirectoryBytes
        let outerRoot = try outer.root(budget: &budget)
        let children = try outer.entries(of: outerRoot, budget: &budget).filter { $0.type != 4 && $0.type != 5 }
        guard children.count == 1, children[0].type == 2, children[0].name == Array("pfs_image.dat".utf8) else {
            throw Failure.unsupported("an outer image without just pfs_image.dat")
        }
        let packed = try outer.inode(children[0].inode)
        guard packed.isRegular, packed.flags & 1 == 1 else { throw Failure.unsupported("pfs_image.dat is not a PFSC container") }
        let inner = try Image(innerSlice(outer, packed, source))
        let root = try inner.root(budget: &budget)
        var manifest = Manifest()
        var seen: Set<Int64> = [root.number]
        var paths: Set<String> = []

        func walk(_ directory: Inode, _ prefix: [String], _ depth: Int) throws {
            for entry in try inner.entries(of: directory, budget: &budget) {
                if entry.type == 4 || entry.type == 5 { continue }
                let shown = (prefix + [String(decoding: entry.name, as: UTF8.self)]).joined(separator: "/")
                guard entry.type == 2 || entry.type == 3, let name = safeName(entry.name) else {
                    manifest.refused.append(shown)
                    continue
                }
                let path = (prefix + [name]).joined(separator: "/")
                guard path.utf8.count <= maxPath else {
                    manifest.refused.append(shown)
                    continue
                }
                guard depth < maxDepth else { throw Failure.damaged("folders nested too deeply") }
                guard seen.insert(entry.inode).inserted else { throw Failure.damaged("two names for one file") }
                guard paths.insert(path.lowercased()).inserted else { throw Failure.damaged("the same path twice") }
                guard manifest.items.count < maxEntries else { throw Failure.damaged("too many files") }
                let inode = try inner.inode(entry.inode)
                if entry.type == 3 {
                    guard inode.isDirectory else { throw Failure.damaged("a directory entry is no directory") }
                    manifest.items.append(Manifest.Item(path: path, directory: true, offset: 0, size: 0))
                    try walk(inode, prefix + [name], depth + 1)
                    continue
                }
                if inode.isLink {
                    manifest.refused.append(shown)
                    continue
                }
                guard inode.isRegular else { throw Failure.damaged("a file entry is no file") }
                if inode.flags & 1 != 0 { throw Failure.compressed }
                guard inode.flags & ~UInt32(0x10) == 0 else { throw Failure.unsupported("file flags 0x\(String(inode.flags, radix: 16))") }
                guard inode.size <= inner.slice.length - manifest.size else { throw Failure.damaged("the files add up to more than the image") }
                manifest.files += 1
                manifest.size += inode.size
                manifest.items.append(Manifest.Item(path: path, directory: false, offset: inner.slice.base + inner.offset(inode), size: inode.size))
            }
        }
        try walk(root, [], 0)
        return manifest
    }

    private static func item(_ manifest: Manifest, _ path: String, under limit: Int) -> Manifest.Item? {
        manifest.items.first { !$0.directory && $0.path == path && $0.size < Int64(limit) }
    }

    private static func message(_ name: String, _ reason: String) -> String { "\(name) is damaged or not fully copied: \(reason)" }

    /// What `url` holds, as a zip's plan. A compressed or unsupported file is a plan that says so;
    /// a damaged one throws, as a zip that does not read yet does.
    static func plan(_ url: URL) throws -> ArchivePlan {
        let source: Source
        let manifest: Manifest
        do {
            source = try Source(url)
            manifest = try read(source)
        } catch Failure.compressed {
            return ArchivePlan(files: 0, size: 0, strip: "", looksLikeGame: false, refused: [], problem: .compressed)
        } catch Failure.unsupported {
            return ArchivePlan(files: 0, size: 0, strip: "", looksLikeGame: false, refused: [], problem: .unsupported)
        } catch Failure.damaged(let reason) {
            throw ArchiveError(message(url.lastPathComponent, reason))
        }
        let names = Set(manifest.items.filter { !$0.directory }.map { $0.path.lowercased() })
        var plan = ArchivePlan(files: manifest.files, size: manifest.size, strip: "", looksLikeGame: names.contains("eboot.bin") && names.contains("sce_sys/param.json"), refused: manifest.refused)
        if let entry = item(manifest, "sce_sys/param.json", under: maxParameters),
           let data = try? source.bytes(entry.offset, Int(entry.size)),
           let about = GameArchives.parse(Data(data)) {
            plan.titleID = about["titleId"] as? String
            plan.version = about["contentVersion"] as? String
            let localized = about["localizedParameters"] as? [String: Any] ?? [:]
            let language = localized["defaultLanguage"] as? String ?? about["defaultLanguage"] as? String ?? "en-US"
            let languages = (localized[language] as? [String: Any]) ?? (localized["en-US"] as? [String: Any]) ?? [:]
            plan.titleName = (languages["titleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let entry = item(manifest, "sce_sys/icon0.png", under: maxIcon),
           let data = try? source.bytes(entry.offset, Int(entry.size)), isReasonablePNG(data) {
            plan.icon = Data(data)
        }
        return plan
    }

    /// PNG signature, and an IHDR no larger than `maxIconSide` a side: the picture is decoded for
    /// the panel, and a very large one (or a decompression bomb) is simply not shown.
    static func isReasonablePNG(_ bytes: [UInt8]) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 24, Array(bytes[0..<8]) == signature, Array(bytes[12..<16]) == Array("IHDR".utf8) else { return false }
        func big(_ at: Int) -> UInt32 { UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3]) }
        return big(16) <= maxIconSide && big(20) <= maxIconSide
    }

    /// Unpacks the file at `url` into `into` (made fresh; it must not be there) with the same
    /// progress and stops as a zip: `into` is removed again on any failure or a stop.
    static func unpackSync(_ url: URL, into: URL, progress: ((Int64, Int64) -> Void)?, cancelled: (() -> Bool)?) throws {
        let source: Source
        let manifest: Manifest
        do {
            source = try Source(url)
            manifest = try read(source)
        } catch Failure.compressed {
            throw ArchiveError("\(url.lastPathComponent) is compressed")
        } catch Failure.unsupported(let what) {
            throw ArchiveError("\(url.lastPathComponent) is not a kind AnyPS5 unpacks: \(what)")
        } catch Failure.damaged(let reason) {
            throw ArchiveError(message(url.lastPathComponent, reason))
        }
        if manifest.files == 0 { throw ArchiveError("The file holds no game files") }
        if let first = manifest.refused.first { throw ArchiveError("\(manifest.refused.count) names would land outside the folder: \(first)") }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: into.path) { throw ArchiveError("\(into.path) is there already") }
        do {
            try fileManager.createDirectory(at: into, withIntermediateDirectories: true)
            var done: Int64 = 0, reported: Int64 = 0
            progress?(0, manifest.size)
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: GameArchives.chunk, alignment: 16)
            defer { buffer.deallocate() }
            for entry in manifest.items {
                if cancelled?() == true { throw UnpackCancelled() }
                guard let target = GameArchives.safePath(into, entry.path) else {
                    throw ArchiveError("\(entry.path) would land outside the folder")
                }
                if entry.directory {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // O_EXCL: no file is written over, not even one the disk's case folding made the same.
                let descriptor = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
                guard descriptor >= 0 else { throw ArchiveError("\(entry.path) could not be written: \(String(cString: strerror(errno)))") }
                defer { close(descriptor) }
                var remaining = entry.size
                var position = entry.offset
                while remaining > 0 {
                    let wanted = Int(min(Int64(GameArchives.chunk), remaining))
                    let piece = UnsafeMutableRawBufferPointer(rebasing: buffer[0..<wanted])
                    do {
                        try source.fill(position, piece)
                    } catch Failure.damaged(let reason) {
                        throw ArchiveError(message(url.lastPathComponent, reason))
                    }
                    var offset = 0
                    while offset < wanted {
                        let count = write(descriptor, piece.baseAddress! + offset, wanted - offset)
                        guard count > 0 else { throw ArchiveError("\(entry.path) could not be written: \(String(cString: strerror(errno)))") }
                        offset += count
                    }
                    position += Int64(wanted)
                    remaining -= Int64(wanted)
                    done += Int64(wanted)
                    if done - reported >= GameArchives.reportEvery {
                        reported = done
                        if cancelled?() == true { throw UnpackCancelled() }
                        progress?(done, manifest.size)
                    }
                }
            }
            progress?(manifest.size, manifest.size)
        } catch {
            try? fileManager.removeItem(at: into)
            throw error
        }
    }
}
