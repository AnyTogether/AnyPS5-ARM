import CryptoKit
import Foundation

/// The consoles whose discs the library can list for an emulator installed on the Mac, as on
/// Windows and Linux (AnyPS5 Desktop, lib/core/game_library.dart).
public enum RetroPlatform: String, CaseIterable, Codable, Sendable {
    case ps1, ps2, ps3

    /// The emulator the launcher starts the console's discs with.
    public var emulator: String {
        switch self {
        case .ps1: return "DuckStation"
        case .ps2: return "PCSX2"
        case .ps3: return "RPCS3"
        }
    }

    /// PS1, PS2, PS3: the console as the home screen's folder and the title IDs write it.
    public var label: String { rawValue.uppercased() }
}

/// A disc an emulator plays: its console, and the file handed to the emulator (a cue sheet,
/// playlist, image or PS3_DISC.SFB).
public struct RetroDisc: Hashable, Sendable {
    public let platform: RetroPlatform
    public let path: URL

    public init(platform: RetroPlatform, path: URL) {
        self.platform = platform
        self.path = path
    }
}

/// What a scan read from the disc files (a cue sheet's tracks, whether an ISO boots a PS2, a
/// playlist's entries, a PS3 disc's PARAM.SFO), by path, kept while the file's size and
/// modification time stay the same: a rescan, or a watched folder's change, reads again only
/// the files that changed, and a library without discs reads none.
public final class RetroScanCache: @unchecked Sendable {
    enum Reading {
        case names([String]?)
        case flag(Bool)
        case fields([String: String]?)
    }

    public struct NotAFile: Error {}

    private struct Entry {
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
        let value: Reading
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var seen: Set<String>?

    public init() {}

    /// How many files it holds what was read from.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// What `read` gives for the file at `path`, read again only when the file changed since the
    /// last time, or when what is kept is of another kind (`fits`). Throws when it is not a file.
    func value(_ path: String, fits: (Reading) -> Bool, read: () throws -> Reading) throws -> Reading {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw NotAFile() }
        let size = Int64(info.st_size), seconds = Int(info.st_mtimespec.tv_sec), nanoseconds = Int(info.st_mtimespec.tv_nsec)
        lock.lock()
        seen?.insert(path)
        let known = entries[path]
        lock.unlock()
        if let known, known.size == size, known.seconds == seconds, known.nanoseconds == nanoseconds, fits(known.value) { return known.value }
        let value = try read()
        lock.lock()
        entries[path] = Entry(size: size, seconds: seconds, nanoseconds: nanoseconds, value: value)
        lock.unlock()
        return value
    }

    func names(_ path: String, _ read: () throws -> [String]?) throws -> [String]? {
        let kept = try value(path, fits: { if case .names = $0 { return true } else { return false } }, read: { .names(try read()) })
        if case .names(let names) = kept { return names }
        return nil
    }

    func flag(_ path: String, _ read: () throws -> Bool) throws -> Bool {
        let kept = try value(path, fits: { if case .flag = $0 { return true } else { return false } }, read: { .flag(try read()) })
        if case .flag(let flag) = kept { return flag }
        return false
    }

    func fields(_ path: String, _ read: () throws -> [String: String]?) throws -> [String: String]? {
        let kept = try value(path, fits: { if case .fields = $0 { return true } else { return false } }, read: { .fields(try read()) })
        if case .fields(let fields) = kept { return fields }
        return nil
    }

    /// A whole library's scan starts: the files it does not look at are let go at `end`.
    public func begin() {
        lock.lock()
        seen = []
        lock.unlock()
    }

    /// The whole library's scan is done.
    public func end() {
        lock.lock()
        if let seen { entries = entries.filter { seen.contains($0.key) } }
        seen = nil
        lock.unlock()
    }
}

/// Where a scan looks for discs: the games folder it started in, and what it keeps of the files.
struct RetroScan {
    let root: URL
    let cache: RetroScanCache
}

/// An extracted PS3 disc: a folder with PS3_DISC.SFB and PS3_GAME, which RPCS3 boots from
/// PS3_GAME/USRDIR/EBOOT.BIN.
public enum PS3Disc {
    /// The disc's PARAM.SFO, which names the game.
    public static func paramsFile(_ folder: URL) -> URL { folder.appendingPathComponent("PS3_GAME/PARAM.SFO") }

    /// What RPCS3 is handed to boot the disc.
    public static func bootFile(_ folder: URL) -> URL { folder.appendingPathComponent("PS3_GAME/USRDIR/EBOOT.BIN") }

    /// Whether `folder` holds a whole extracted disc.
    public static func isDisc(_ folder: URL) -> Bool {
        GameLibrary.isFile(folder.appendingPathComponent("PS3_DISC.SFB").path) && GameLibrary.isFile(bootFile(folder).path) && GameLibrary.isFile(paramsFile(folder).path)
    }

    /// The text values of the disc's PARAM.SFO (TITLE, TITLE_ID, APP_VER...), nil when `folder`
    /// is no disc or its PARAM.SFO cannot be read.
    public static func metadata(_ folder: URL) -> [String: String]? {
        guard isDisc(folder) else { return nil }
        let file = paramsFile(folder)
        guard let size = GameLibrary.fileLength(file.path), size <= 1024 * 1024, let data = try? Data(contentsOf: file) else { return nil }
        return fields(of: [UInt8](data))
    }

    /// The text values of a PARAM.SFO's bytes; nil when they are not one.
    static func fields(of bytes: [UInt8]) -> [String: String]? {
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 20, bytes[0] == 0x00, bytes[1] == 0x50, bytes[2] == 0x53, bytes[3] == 0x46 else { return nil }
        let keyStart = u32(8), valueStart = u32(12), count = u32(16)
        guard 20 + count * 16 <= keyStart, keyStart <= valueStart, valueStart <= bytes.count else { return nil }
        func string(_ start: Int, _ limit: Int) -> String {
            var end = start
            while end < limit, bytes[end] != 0 { end += 1 }
            return String(decoding: bytes[start..<end], as: UTF8.self)
        }
        var result: [String: String] = [:]
        for index in 0..<count {
            let entry = 20 + index * 16
            guard u16(entry + 2) == 0x0204 else { continue }
            let key = keyStart + u16(entry)
            let size = u32(entry + 4)
            let value = valueStart + u32(entry + 12)
            guard key < valueStart, value + size <= bytes.count else { continue }
            result[string(key, valueStart)] = string(value, value + size)
        }
        return result
    }
}

extension GameLibrary {
    /// What the launcher's scans have read from disc files (RetroScanCache).
    public static let retroCache = RetroScanCache()

    // MARK: Files

    /// Whether `path` is a file, through a link too.
    static func isFile(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }

    /// Whether `path` is a file itself, not a link to one.
    static func isOwnFile(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }

    /// A file's length in bytes, through a link too; nil when it is not there.
    static func fileLength(_ path: String) -> Int64? {
        var info = stat()
        return stat(path, &info) == 0 ? Int64(info.st_size) : nil
    }

    /// The total length of `files`, in bytes; one that is not there counts nothing. A disc's
    /// identifier is made of it, so it is the files' length and not the room they take on a drive.
    public static func filesLength(_ files: [URL]) -> Int64 {
        files.reduce(0) { $0 + (fileLength($1.path) ?? 0) }
    }

    /// UTF-8 text without a byte order mark.
    static func text(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let start = bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0
        return String(decoding: bytes[start...], as: UTF8.self)
    }

    static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func fileExtension(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }

    // MARK: Discs side by side

    static let ps1Folders: Set<String> = ["ps1", "psx", "playstation"]
    static let ps2Folders: Set<String> = ["ps2", "playstation 2"]

    /// The discs among `entries`, all in `folder`: cue sheets whose tracks are all there, PBP
    /// files, PS2 ISOs, CHDs under a folder named for one console, and the playlists that gather a
    /// game's discs (the discs they list are not games of their own then). What is read from each
    /// file comes from the scan's cache while the file is unchanged.
    static func retroFiles(in folder: URL, entries: [URL], scan: RetroScan) -> [Game] {
        let cache = scan.cache
        let base = folder.path
        let parts = folder.pathComponents.map { $0.lowercased() }
        let ps1Folder = parts.contains { ps1Folders.contains($0) }
        let ps2Folder = parts.contains { ps2Folders.contains($0) }
        var order: [String] = []
        var discs: [String: RetroPlatform] = [:]
        var tracks: [String: [String]] = [:]
        var playlists: [String] = []
        func add(_ path: String, _ platform: RetroPlatform) {
            if discs[path] == nil { order.append(path) }
            discs[path] = platform
        }
        for name in entries.map(\.lastPathComponent).sorted() {
            let path = base + "/" + name
            guard isFile(path) else { continue }
            switch fileExtension(name) {
            case "m3u":
                playlists.append(path)
            case "cue" where !ps2Folder:
                guard let names = try? cache.names(path, { cueFiles(path) }), !names.isEmpty else { continue }
                let local = names.compactMap { localDiscFile(base, $0) }
                guard local.count == names.count else { continue }
                add(path, .ps1)
                tracks[path] = local
            case "pbp":
                if (try? cache.flag(path) { fileMagic(path, [0x00, 0x50, 0x42, 0x50]) }) == true { add(path, .ps1) }
            case "chd" where ps1Folder != ps2Folder:
                if (try? cache.flag(path) { fileMagic(path, Array("MComprHD".utf8)) }) == true { add(path, ps1Folder ? .ps1 : .ps2) }
            case "iso":
                if (try? cache.flag(path) { ps2ISO(path) }) == true { add(path, .ps2) }
            default:
                break
            }
        }
        var claimed = Set<String>()
        var gathered: [String: [String]] = [:]
        for playlist in playlists {
            guard let names = try? cache.names(playlist, { playlistEntries(playlist) }), !names.isEmpty else { continue }
            let local = names.compactMap { localDiscFile(base, $0) }
            guard local.count == names.count, local.allSatisfy({ discs[$0] == .ps1 }) else { continue }
            add(playlist, .ps1)
            claimed.formUnion(local)
            gathered[playlist] = [playlist] + local.flatMap { [$0] + (tracks[$0] ?? []) }
        }
        return order.filter { !claimed.contains($0) }.compactMap { disc in
            guard let platform = discs[disc] else { return nil }
            return discoveredRetro(folder, disc: disc, platform: platform, root: scan.root, files: gathered[disc] ?? [disc] + (tracks[disc] ?? []))
        }
    }

    /// The file `name` names beside the sheet or playlist in `folder`, as the path the scan lists
    /// it by; nil when it leaves the folder (an absolute path, a drive letter, `..` out of it) or
    /// is not there.
    static func localDiscFile(_ folder: String, _ name: String) -> String? {
        let written = name.replacingOccurrences(of: "\\", with: "/")
        guard !written.hasPrefix("/"), !written.contains(":") else { return nil }
        var parts: [String] = []
        for part in written.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(String(part))
            }
        }
        guard !parts.isEmpty else { return nil }
        let path = folder + "/" + parts.joined(separator: "/")
        return isFile(path) ? path : nil
    }

    /// The files a cue sheet names, as written in it; nil when it is not a data disc's sheet.
    static func cueFiles(_ path: String) -> [String]? {
        guard let length = fileLength(path), length <= 64 * 1024, let data = FileManager.default.contents(atPath: path) else { return nil }
        let contents = text(data)
        guard !matches(#"^\s*TRACK\s+[0-9]+\s+MODE[12]/[0-9]+"#, contents).isEmpty else { return nil }
        return matches(#"^\s*FILE\s+(?:"([^"]+)"|(\S+))\s+[A-Za-z0-9_]+"#, contents).compactMap { match in
            let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            return Range(range, in: contents).map { String(contents[$0]) }
        }
    }

    /// The entries of an M3U playlist, as written in it.
    static func playlistEntries(_ path: String) -> [String] {
        guard let length = fileLength(path), length <= 64 * 1024, let data = FileManager.default.contents(atPath: path) else { return [] }
        return text(data).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func fileMagic(_ path: String, _ magic: [UInt8]) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)).map { [UInt8]($0) } == magic
    }

    /// Whether the image at `path` is a PS2 disc: an ISO 9660 volume whose SYSTEM.CNF has a BOOT2
    /// line.
    static func ps2ISO(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path), let whole = fileLength(path).map({ Int($0) }) else { return false }
        defer { try? handle.close() }
        let sector = 2048
        func read(_ offset: Int, _ count: Int) -> [UInt8] {
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil, let data = try? handle.read(upToCount: count) else { return [] }
            return [UInt8](data)
        }
        func u32(_ bytes: [UInt8], _ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        let descriptor = read(16 * sector, sector)
        guard descriptor.count >= 190, descriptor[0] == 1, Array(descriptor[1..<6]) == Array("CD001".utf8) else { return false }
        let rootOffset = u32(descriptor, 158) * sector
        let rootLength = u32(descriptor, 166)
        guard rootLength != 0, rootLength <= 1024 * 1024, rootOffset + rootLength <= whole else { return false }
        let records = read(rootOffset, rootLength)
        var position = 0
        while position + 34 <= records.count {
            let length = Int(records[position])
            if length == 0 {
                position = (position / sector + 1) * sector
                continue
            }
            let nameLength = Int(records[position + 32])
            guard length >= 34, position + length <= records.count, 33 + nameLength <= length else { return false }
            let name = String(decoding: records[(position + 33)..<(position + 33 + nameLength)], as: UTF8.self)
            if name == "SYSTEM.CNF;1" || name == "SYSTEM.CNF" {
                let start = u32(records, position + 2) * sector
                let size = u32(records, position + 10)
                guard size != 0, size <= 64 * 1024, start + size <= whole else { return false }
                return !matches(#"^\s*BOOT2\s*="#, text(Data(read(start, size)))).isEmpty
            }
            position += length
        }
        return false
    }

    // MARK: Identity

    /// A disc's `Game.libraryID`: its console, `key` and its path inside the games folder `root`,
    /// with / between folders as on every system, so that the same games folder on another mount
    /// point (or another computer) keeps its games' identifiers. `key` tells apart two games at
    /// the same path in two games folders: the title ID a disc names, or the length of a loose
    /// disc's files. Outside a games folder, the whole path.
    public static func retroID(_ platform: RetroPlatform, key: String, disc: URL, root: URL?) -> String {
        func inside(_ path: String, _ folder: String) -> Substring? { path.hasPrefix(folder + "/") ? path.dropFirst(folder.count + 1) : nil }
        // As the scan lists it, else with both written the same way (a games folder reached
        // through a link, such as /tmp).
        if let root, let relative = inside(disc.path, root.path) ?? inside(disc.resolvingSymlinksInPath().path, root.resolvingSymlinksInPath().path) {
            return "retro:\(platform.rawValue):\(key):\(relative)"
        }
        // The whole path, split and joined as AnyPS5 Desktop writes one (its root, then the rest).
        return "retro:\(platform.rawValue):\(key):/\(disc.standardizedFileURL.path)"
    }

    /// The title ID of a disc that names none: its console and the start of its identifier's
    /// SHA-256.
    static func retroTitleID(_ platform: RetroPlatform, id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02X", $0) }.joined()
        return "\(platform.label)-\(digest.prefix(16))"
    }

    static func discoveredRetro(_ folder: URL, disc: String, platform: RetroPlatform, root: URL, files: [String]) -> Game {
        let url = URL(fileURLWithPath: disc)
        let own = files.map { URL(fileURLWithPath: $0) }
        let name = (url.lastPathComponent as NSString).deletingPathExtension
        let id = retroID(platform, key: "\(filesLength(own))", disc: url, root: root)
        return Game(folder: folder, titleID: retroTitleID(platform, id: id), name: name, version: "", icon: nil, background: nil, music: nil, executable: .disc,
                    retro: RetroDisc(platform: platform, path: url), libraryID: id, files: own)
    }

    // MARK: Game folders

    /// An extracted PS3 disc in `folder` (PS3_DISC.SFB, PS3_GAME/PARAM.SFO and the game's
    /// EBOOT.BIN), named from its PARAM.SFO.
    static func inspectPS3(_ folder: URL, root: URL?, cache: RetroScanCache) -> Game? {
        guard PS3Disc.isDisc(folder), let metadata = try? cache.fields(PS3Disc.paramsFile(folder).path, { PS3Disc.metadata(folder) }) else { return nil }
        guard let titleID = metadata["TITLE_ID"], titleID.range(of: #"^[A-Z]{4}[0-9]{5}$"#, options: .regularExpression) != nil else { return nil }
        func image(_ name: String) -> URL? {
            let url = folder.appendingPathComponent(name)
            return isFile(url.path) ? url : nil
        }
        let disc = folder.appendingPathComponent("PS3_DISC.SFB")
        return Game(folder: folder, titleID: "PS3-\(titleID)", name: metadata["TITLE"] ?? folder.lastPathComponent, version: metadata["APP_VER"] ?? "",
                    icon: image("cover.webp") ?? image("cover.png") ?? image("cover.jpg") ?? image("PS3_GAME/ICON0.PNG"), background: image("PS3_GAME/PIC1.PNG"), music: nil,
                    executable: .disc, retro: RetroDisc(platform: .ps3, path: disc), libraryID: retroID(.ps3, key: titleID, disc: disc, root: root))
    }

    /// A PS1 or PS2 game folder its retro.json describes: the console, name, title ID and disc,
    /// and the art and music beside it. Each file is named without a folder and has to be a file
    /// of the game's folder itself, not a link out of it.
    static func inspectRetro(_ folder: URL, root: URL?) -> Game? {
        let manifest = folder.appendingPathComponent("retro.json")
        guard isFile(manifest.path), let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: Data(text(data).utf8)) as? [String: Any] else { return nil }
        func string(_ field: String) -> String? {
            guard let value = json[field] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let platform = string("platform").flatMap(RetroPlatform.init(rawValue:)), platform != .ps3,
              let titleID = string("titleId"), let name = string("name"),
              titleID.range(of: #"^[A-Z0-9-]+$"#, options: .regularExpression) != nil else { return nil }
        func localFile(_ field: String, _ extensions: Set<String>) -> URL? {
            guard let name = string(field), name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:")) == nil, extensions.contains(fileExtension(name)) else { return nil }
            let url = folder.appendingPathComponent(name)
            return isOwnFile(url.path) ? url : nil
        }
        let images: Set<String> = ["png", "jpg", "jpeg", "webp"]
        let discs: Set<String> = platform == .ps1 ? ["cue", "chd", "m3u", "pbp"] : ["iso", "chd"]
        guard let disc = localFile("disc", discs) else { return nil }
        return Game(folder: folder, titleID: "\(platform.label)-\(titleID)", name: name, version: "", icon: localFile("icon", images), background: localFile("background", images),
                    music: localFile("music", ["wav", "mp3", "m4a"]), executable: .disc, ageLevels: ageLevels(json["ageLevel"]),
                    retro: RetroDisc(platform: platform, path: disc), libraryID: retroID(platform, key: titleID, disc: disc, root: root))
    }
}
