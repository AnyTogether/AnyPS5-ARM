import CArchive
import Foundation

/// A zip a game was dropped into the games folder as, and the folder beside it that it unpacks
/// into: PPSA01234.zip becomes PPSA01234/, and PPSA01234-UPDATE.zip an update the game finds. The
/// same rules as AnyLauncher Port's game_archives.dart.
public struct GameArchive: Hashable, Sendable {
    public let url: URL
    /// The zip's own size on the disk.
    public let size: Int64

    public init(url: URL, size: Int64) {
        self.url = url
        self.size = size
    }

    public var name: String { url.lastPathComponent }

    /// The folder it unpacks into, named as the zip without ".zip".
    public var folder: URL { url.deletingPathExtension() }

    /// Where it unpacks first: a hidden folder the library does not read, renamed to `folder` once
    /// every file is in it, so no half-unpacked dump shows as a game.
    public var partial: URL { GameArchives.partial(for: folder) }
}

/// What a zip holds, read from its list of files (not their contents, but a param.json).
public struct ArchivePlan: Equatable, Sendable {
    /// The files it unpacks (folders and links left out).
    public var files: Int
    /// The bytes they come to unpacked.
    public var size: Int64
    /// The one folder every file is in ("PPSA01234/"), left out when it unpacks: the folder beside
    /// the zip is the dump itself. Empty when the files are not all in one folder.
    public var strip: String
    /// Whether it holds a dump: an eboot.bin and a sce_sys/param.json.
    public var looksLikeGame: Bool
    /// The names that would land outside the folder (an absolute path, a drive, "..", a name that
    /// cannot be made on every system). An archive with any is never unpacked.
    public var refused: [String]
    /// The dump's title ID and contentVersion from its param.json, nil when it has none that
    /// reads: what tells an update for a game in the library from a game of its own.
    public var titleID: String?
    public var version: String?

    public init(files: Int, size: Int64, strip: String, looksLikeGame: Bool, refused: [String], titleID: String? = nil, version: String? = nil) {
        self.files = files
        self.size = size
        self.strip = strip
        self.looksLikeGame = looksLikeGame
        self.refused = refused
        self.titleID = titleID
        self.version = version
    }
}

/// Unpacking or copying stopped on purpose; what was written is gone.
public struct UnpackCancelled: Error, Equatable {
    public init() {}
}

public struct ArchiveError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// A stop asked for from the interface while a job runs on another thread.
public final class UnpackCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    public init() {}

    public func cancel() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}

public enum GameArchives {
    public static let extensions: Set<String> = ["zip"]
    /// How far below a games folder an archive is looked for: in it, and in its folders.
    public static let depth = 1
    /// Room kept free beyond what the files take, for the file system's own use.
    public static let spaceMargin: Int64 = 512 * 1024 * 1024
    /// How often the progress is told and a stop looked for, in bytes written.
    static let reportEvery: Int64 = 8 * 1024 * 1024
    static let chunk = 1024 * 1024

    /// The hidden folder `folder` is filled in first.
    public static func partial(for folder: URL) -> URL {
        folder.deletingLastPathComponent().appendingPathComponent(".\(folder.lastPathComponent).unpacking")
    }

    /// The archives in `roots` (and one folder below) with no folder of their name beside them
    /// yet, sorted by path. Hidden files and the launcher's own folder are skipped.
    public static func find(_ roots: [URL]) -> [GameArchive] {
        var found: [GameArchive] = []
        let fileManager = FileManager.default
        func visit(_ folder: URL, _ level: Int) {
            guard let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return }
            for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true, values?.isPackage != true, level < depth { visit(entry, level + 1) }
                guard values?.isRegularFile == true, extensions.contains(entry.pathExtension.lowercased()) else { continue }
                let archive = GameArchive(url: entry, size: Int64(values?.fileSize ?? 0))
                if fileManager.fileExists(atPath: archive.folder.path) { continue }
                found.append(archive)
            }
        }
        for root in roots { visit(root, 0) }
        return found.sorted { $0.url.path < $1.url.path }
    }

    /// Hidden folders a job left when the launcher stopped half way: `.<name>.unpacking` and
    /// `.<name>.copying` in a games folder or one below. Removed while no job runs.
    public static func removeLeftovers(_ roots: [URL]) {
        let fileManager = FileManager.default
        func visit(_ folder: URL, _ level: Int) {
            guard let entries = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for entry in entries {
                let name = entry.lastPathComponent
                let directory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if name.hasPrefix("."), name.hasSuffix(".unpacking") || name.hasSuffix(".copying"), directory {
                    try? fileManager.removeItem(at: entry)
                } else if directory, level < depth, !name.hasPrefix(".") {
                    visit(entry, level + 1)
                }
            }
        }
        for root in roots { visit(root, 0) }
    }

    /// Letters Windows does not allow in a name (":" would also write an alternate data stream
    /// there): a zip AnyLauncher Port refuses is refused here too.
    static func unmakeable(_ part: String) -> Bool {
        part.unicodeScalars.contains { "<>:\"|?*".unicodeScalars.contains($0) || $0.value < 0x20 }
    }

    /// The parts of an entry's name below `strip`, or nil when the name would leave the folder it
    /// unpacks into: an absolute path, a drive, a "..", or a name another system cannot make.
    public static func safeParts(_ name: String, strip: String = "") -> [String]? {
        var relative = name.replacingOccurrences(of: "\\", with: "/")
        if relative.hasPrefix("/") { return nil }
        let characters = Array(relative.unicodeScalars)
        if characters.count >= 2, characters[1] == ":", CharacterSet.letters.contains(characters[0]), characters[0].isASCII { return nil }
        if !strip.isEmpty {
            guard relative.hasPrefix(strip) else { return nil }
            relative = String(relative.dropFirst(strip.count))
        }
        let parts = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
        if parts.contains(where: { $0 == ".." || unmakeable($0) || $0.trimmingCharacters(in: .whitespaces) != $0 }) { return nil }
        return parts
    }

    /// Where `name` is written under `into`, nil when it would land outside it (`safeParts`).
    public static func safePath(_ into: URL, _ name: String, strip: String = "") -> URL? {
        guard let parts = safeParts(name, strip: strip) else { return nil }
        let target = parts.reduce(into.standardizedFileURL) { $0.appendingPathComponent($1) }.standardizedFileURL
        let base = into.standardizedFileURL.path
        guard target.path == base || target.path.hasPrefix(base + "/") else { return nil }
        return target
    }

    /// The one top folder every entry is in ("PPSA01234/"), or empty.
    static func commonFolder(_ names: [String]) -> String {
        var first: String?
        var any = false
        for raw in names {
            let name = raw.replacingOccurrences(of: "\\", with: "/")
            guard let slash = name.firstIndex(of: "/"), slash != name.startIndex else {
                // A file at the top: nothing to leave out.
                if name.isEmpty { continue }
                return ""
            }
            let top = String(name[...slash])
            if first == nil { first = top }
            if top != first { return "" }
            if name.count > top.count { any = true }
        }
        guard any, let first, safeParts(first) != nil else { return "" }
        return first
    }

    /// What the zip at `url` holds. Throws when it is not a zip (or not a whole one yet).
    public static func plan(_ url: URL) throws -> ArchivePlan {
        let entries = try ZipReader.list(url)
        let strip = commonFolder(entries.map(\.name))
        var plan = ArchivePlan(files: 0, size: 0, strip: strip, looksLikeGame: false, refused: [])
        var eboot = false, parameters = false
        var parameterIndex: Int?
        var parameterDepth = 99
        for (index, entry) in entries.enumerated() {
            guard entry.readable, let parts = safeParts(entry.name, strip: strip) else {
                plan.refused.append(entry.name)
                continue
            }
            guard entry.kind == .file, !parts.isEmpty else { continue }
            plan.files += 1
            plan.size += entry.size
            // A dump at the top, or in a folder or two below it.
            if parts.count <= 3, parts.last!.lowercased() == "eboot.bin" { eboot = true }
            let last = parts.count
            if last >= 2, last <= 4, parts[last - 2] == "sce_sys", parts[last - 1] == "param.json" {
                parameters = true
                if last < parameterDepth, entry.size < 1024 * 1024 {
                    parameterIndex = index
                    parameterDepth = last
                }
            }
        }
        plan.looksLikeGame = eboot && parameters
        if let parameterIndex, let data = try? ZipReader.contents(url, entry: parameterIndex, limit: 1024 * 1024),
           let about = parse(data) {
            plan.titleID = about["titleId"] as? String
            plan.version = about["contentVersion"] as? String
        }
        return plan
    }

    static func parse(_ data: Data) -> [String: Any]? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any]
    }

    /// Unpacks the zip at `url` into `into` (made fresh; it must not be there), the one folder
    /// every file is in left out. `progress` hears the bytes written and the whole every few
    /// megabytes; `cancelled` is asked as often. Folders and files only: links are skipped, and an
    /// archive with a name that would land outside `into` is refused before anything is written.
    /// On any failure or a stop, `into` is removed again.
    public static func unpackSync(_ url: URL, into: URL, progress: ((Int64, Int64) -> Void)? = nil, cancelled: (() -> Bool)? = nil) throws {
        let plan = try plan(url)
        if plan.files == 0 { throw ArchiveError("The archive has no files") }
        if let first = plan.refused.first { throw ArchiveError("\(plan.refused.count) names would land outside the folder: \(first)") }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: into.path) { throw ArchiveError("\(into.path) is there already") }
        do {
            try fileManager.createDirectory(at: into, withIntermediateDirectories: true)
            var done: Int64 = 0, reported: Int64 = 0
            progress?(0, plan.size)
            let reader = try ZipReader(url)
            while let entry = try reader.next() {
                if cancelled?() == true { throw UnpackCancelled() }
                if entry.kind == .link || entry.kind == .other { continue }
                guard entry.readable, let target = safePath(into, entry.name, strip: plan.strip) else {
                    throw ArchiveError("\(entry.name) would land outside the folder")
                }
                if entry.kind == .directory {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                // O_NOFOLLOW: nothing inside `into` is a link, and nothing is written through one.
                let descriptor = open(target.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
                guard descriptor >= 0 else { throw ArchiveError("\(entry.name) could not be written: \(String(cString: strerror(errno)))") }
                var written: Int64 = 0
                do {
                    defer { close(descriptor) }
                    try reader.readData { buffer in
                        var offset = 0
                        while offset < buffer.count {
                            let count = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                            guard count > 0 else { throw ArchiveError("\(entry.name) could not be written: \(String(cString: strerror(errno)))") }
                            offset += count
                        }
                        written += Int64(buffer.count)
                        done += Int64(buffer.count)
                        if done - reported >= reportEvery {
                            reported = done
                            if cancelled?() == true { throw UnpackCancelled() }
                            progress?(done, plan.size)
                        }
                    }
                }
                if entry.size > 0, written != entry.size { throw ArchiveError("\(entry.name) came out at the wrong size") }
            }
            progress?(plan.size, plan.size)
        } catch {
            try? fileManager.removeItem(at: into)
            throw error
        }
    }

    /// Unpacks `archive` into a hidden folder beside `into` (the archive's `folder` when not
    /// given), then renames that to it. Throws `UnpackCancelled` after `cancel`, the archive's or
    /// the disk's error otherwise; nothing is left behind either way.
    public static func unpack(_ archive: GameArchive, into: URL? = nil, progress: ((Int64, Int64) -> Void)? = nil, cancel: UnpackCancel? = nil) throws {
        let folder = into ?? archive.folder
        let partial = partial(for: folder)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: partial)
        if fileManager.fileExists(atPath: folder.path) { throw ArchiveError("A folder of that name is there already: \(folder.path)") }
        try unpackSync(archive.url, into: partial, progress: progress, cancelled: cancel.map { cancel in { cancel.cancelled } })
        do {
            try fileManager.moveItem(at: partial, to: folder)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }
}

/// A zip read through macOS's libarchive, its central directory first (the seekable reader), so a
/// list of a large zip reads no file contents.
final class ZipReader {
    enum Kind { case file, directory, link, other }

    struct Entry {
        /// The name as the zip has it; empty when it could not be read as text.
        let name: String
        let kind: Kind
        let size: Int64
        /// The name could be read, and the entry is not encrypted.
        let readable: Bool
    }

    private let handle: OpaquePointer

    init(_ url: URL) throws {
        guard let handle = archive_read_new() else { throw ArchiveError("libarchive could not start") }
        self.handle = handle
        archive_read_support_format_zip_seekable(handle)
        guard archive_read_open_filename(handle, url.path, 1 << 16) == ARCHIVE_OK else {
            let message = archive_error_string(handle).map { String(cString: $0) } ?? "not a zip"
            // deinit frees the handle: a class whose properties are all set runs it on a throw.
            throw ArchiveError("\(url.lastPathComponent) cannot be read as a zip: \(message)")
        }
    }

    deinit { archive_read_free(handle) }

    private var error: String { archive_error_string(handle).map { String(cString: $0) } ?? "unreadable" }

    func next() throws -> Entry? {
        var entry: OpaquePointer?
        let status = archive_read_next_header(handle, &entry)
        if status == ARCHIVE_EOF { return nil }
        guard status == ARCHIVE_OK || status == ARCHIVE_WARN, let entry else { throw ArchiveError("the zip's list of files cannot be read: \(error)") }
        let raw = archive_entry_pathname_utf8(entry).map { String(cString: $0) }
            ?? archive_entry_pathname(entry).flatMap { String(validatingUTF8: $0) }
        let type = archive_entry_filetype(entry) & AE_IFMT
        var kind: Kind
        switch type {
        case AE_IFREG: kind = .file
        case AE_IFDIR: kind = .directory
        case AE_IFLNK: kind = .link
        case 0: kind = .file
        default: kind = .other
        }
        if let raw, raw.hasSuffix("/"), kind == .file { kind = .directory }
        let size = archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : 0
        return Entry(name: raw ?? "", kind: kind, size: max(0, size), readable: raw != nil && archive_entry_is_encrypted(entry) == 0)
    }

    /// The current entry's bytes, a chunk at a time.
    func readData(_ body: (UnsafeRawBufferPointer) throws -> Void) throws {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: GameArchives.chunk, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let count = archive_read_data(handle, buffer, GameArchives.chunk)
            if count == 0 { return }
            guard count > 0 else { throw ArchiveError("the zip's data cannot be read: \(error)") }
            try body(UnsafeRawBufferPointer(start: buffer, count: count))
        }
    }

    /// Every entry, in the zip's order.
    static func list(_ url: URL) throws -> [Entry] {
        let reader = try ZipReader(url)
        var entries: [Entry] = []
        while let entry = try reader.next() { entries.append(entry) }
        return entries
    }

    /// The bytes of the entry at `index` in the zip's order, at most `limit` of them.
    static func contents(_ url: URL, entry index: Int, limit: Int) throws -> Data {
        let reader = try ZipReader(url)
        var position = 0
        while try reader.next() != nil {
            defer { position += 1 }
            guard position == index else { continue }
            var data = Data()
            try reader.readData { buffer in
                data.append(contentsOf: buffer)
                if data.count > limit { throw ArchiveError("too large") }
            }
            return data
        }
        throw ArchiveError("no entry \(index)")
    }
}
