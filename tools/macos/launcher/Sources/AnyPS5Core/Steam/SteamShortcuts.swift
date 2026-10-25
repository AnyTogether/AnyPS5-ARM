import Foundation

/// Steam's IDs for a non-Steam shortcut, the way Steam (and Steam ROM Manager) derive them: the
/// CRC-32 of the quoted Exe and the AppName with the top bit set. Written into the shortcut's
/// appid field, so Steam uses it and the grid pictures named after it match.
public enum SteamAppID {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// CRC-32 (IEEE 802.3, as zlib's crc32).
    public static func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// The 32-bit shortcut ID: the grid pictures' names.
    public static func shortcut(exe: String, appName: String) -> UInt32 { crc32(Array((exe + appName).utf8)) | 0x8000_0000 }

    /// The 64-bit game ID Big Picture and `steam://rungameid/<id>` use.
    public static func gameID(_ shortcut: UInt32) -> UInt64 { UInt64(shortcut) << 32 | 0x0200_0000 }
}

/// One shortcut AnyPS5 puts in Steam.
public struct SteamShortcut: Equatable {
    public var appName: String
    /// The program, quoted as Steam stores it.
    public var exe: String
    public var startDir: String
    public var launchOptions: String
    public var icon: String
    public var tags: [String]

    public init(appName: String, exe: String, startDir: String, launchOptions: String, icon: String = "", tags: [String] = [SteamShortcuts.tag]) {
        self.appName = appName
        self.exe = exe
        self.startDir = startDir
        self.launchOptions = launchOptions
        self.icon = icon
        self.tags = tags
    }

    public static func quote(_ path: String) -> String { "\"\(path)\"" }

    public var appID: UInt32 { SteamAppID.shortcut(exe: exe, appName: appName) }

    /// The entry's fields in the order Steam itself writes them.
    public var vdf: VdfMap {
        VdfMap([
            .int32("appid", Int32(bitPattern: appID)),
            .string("AppName", appName),
            .string("Exe", exe),
            .string("StartDir", startDir),
            .string("icon", icon),
            .string("ShortcutPath", ""),
            .string("LaunchOptions", launchOptions),
            .int32("IsHidden", 0),
            .int32("AllowDesktopConfig", 1),
            .int32("AllowOverlay", 1),
            .int32("OpenVR", 0),
            .int32("Devkit", 0),
            .string("DevkitGameID", ""),
            .int32("DevkitOverrideAppID", 0),
            .int32("LastPlayTime", 0),
            .string("FlatpakAppID", ""),
            .map("tags", VdfMap(tags.enumerated().map { .string(String($0.offset), $0.element) })),
        ])
    }
}

/// The pictures Steam shows for a shortcut, in `userdata/<id>/config/grid`, by the file name's
/// ending after the shortcut ID.
public enum SteamArt: CaseIterable, Hashable, Sendable {
    /// The library's portrait capsule, 600 × 900.
    case portrait
    /// The wide capsule, 920 × 430.
    case wide
    /// The banner across the top of the game's page, 1920 × 620.
    case hero
    /// The name over the hero, transparent around it.
    case logo
    /// The small square beside the name in lists, also the shortcut's icon field.
    case icon

    public var suffix: String {
        switch self {
        case .portrait: return "p.png"
        case .wide: return ".png"
        case .hero: return "_hero.png"
        case .logo: return "_logo.png"
        case .icon: return "_icon.png"
        }
    }

    public var size: (width: Int, height: Int) {
        switch self {
        case .portrait: return (600, 900)
        case .wide: return (920, 430)
        case .hero: return (1920, 620)
        case .logo: return (1280, 340)
        case .icon: return (256, 256)
        }
    }

    public func fileName(_ appID: UInt32) -> String { "\(appID)\(suffix)" }
}

/// A shortcut and the pictures that go with it.
public struct SteamEntry {
    public var shortcut: SteamShortcut
    public var art: [SteamArt: Data]

    public init(_ shortcut: SteamShortcut, art: [SteamArt: Data] = [:]) {
        self.shortcut = shortcut
        self.art = art
    }
}

/// What a shortcuts.vdf holds, with AnyPS5's entries told apart from everyone else's.
public struct ShortcutsFile {
    private var document: VdfDocument
    /// Where the shortcuts list sits in the root map.
    private let listIndex: Int

    public static var empty: ShortcutsFile {
        ShortcutsFile(document: VdfDocument(root: VdfMap([.map("shortcuts", VdfMap())])), listIndex: 0)
    }

    private init(document: VdfDocument, listIndex: Int) {
        self.document = document
        self.listIndex = listIndex
    }

    public init(bytes: [UInt8]) throws {
        let document = try BinaryVdf.decode(bytes)
        guard let index = document.root.entries.firstIndex(where: { $0.name.lowercased() == "shortcuts" }),
              case .map = document.root.entries[index].value else {
            throw BinaryVdf.Failure(reason: "shortcuts.vdf without its shortcuts list", offset: 0)
        }
        self.init(document: document, listIndex: index)
    }

    public var bytes: [UInt8] { BinaryVdf.encode(document) }

    private var list: VdfMap {
        get {
            guard case .map(let map) = document.root.entries[listIndex].value else { return VdfMap() }
            return map
        }
        set { document.root.entries[listIndex].value = .map(newValue) }
    }

    public var shortcuts: [VdfMap] {
        list.entries.compactMap { if case .map(let map) = $0.value { return map } else { return nil } }
    }

    /// AnyPS5's: tagged AnyPS5 and started with --steam (which the launcher's entries always
    /// are), so a shortcut someone made by hand is never taken for one.
    public static func isOurs(_ shortcut: VdfMap) -> Bool {
        shortcut.strings("tags").contains(SteamShortcuts.tag)
            && (shortcut.string("LaunchOptions") ?? "").split(separator: " ").contains(Substring(SteamShortcuts.launchFlag))
    }

    public static func appID(of shortcut: VdfMap) -> UInt32 { UInt32(bitPattern: shortcut.int32("appid") ?? 0) }

    public var ours: [VdfMap] { shortcuts.filter(Self.isOurs) }

    private static func ours(_ entry: VdfEntry) -> VdfMap? {
        if case .map(let map) = entry.value, isOurs(map) { return map }
        return nil
    }

    /// Takes out AnyPS5's entries; the IDs they had. The others keep their bytes, renumbered only
    /// when one of ours sat before them.
    @discardableResult
    public mutating func removeOurs() -> [UInt32] {
        var removed: [UInt32] = []
        var map = list
        map.entries.removeAll { entry in
            guard let shortcut = Self.ours(entry) else { return false }
            removed.append(Self.appID(of: shortcut))
            return true
        }
        list = Self.renumbered(map)
        return removed
    }

    /// Makes AnyPS5's entries `wanted`: ours not among them go, one already there with the same ID
    /// is replaced where it is, the rest are added at the end.
    public mutating func putOurs(_ wanted: [SteamShortcut]) {
        let ids = Set(wanted.map(\.appID))
        var map = list
        map.entries.removeAll { entry in Self.ours(entry).map { !ids.contains(Self.appID(of: $0)) } ?? false }
        for shortcut in wanted {
            let entry = VdfEntry.map(String(map.entries.count), shortcut.vdf)
            if let at = map.entries.firstIndex(where: { Self.ours($0).map { Self.appID(of: $0) == shortcut.appID } ?? false }) {
                map.entries[at] = entry
            } else {
                map.entries.append(entry)
            }
        }
        list = Self.renumbered(map)
    }

    private static func renumbered(_ map: VdfMap) -> VdfMap {
        var map = map
        for i in map.entries.indices where map.entries[i].name != String(i) {
            map.entries[i] = map.entries[i].renamed(String(i))
        }
        return map
    }
}

/// What adding or removing did.
public struct SteamChange: Equatable {
    public var shortcutsFile: URL
    /// The shortcut IDs added or removed.
    public var appIDs: [UInt32]
    /// The copy of shortcuts.vdf made before it was written; nil when there was no file.
    public var backup: URL?
    public var artFiles: [URL]
}

/// AnyPS5's shortcuts in one Steam account: `userdata/<id>/config/shortcuts.vdf` and the
/// pictures in config/grid. Steam must be closed while they are written (see `SteamControl`).
public struct SteamShortcuts {
    public let install: SteamInstall
    public let user: SteamUser

    /// The tag every AnyPS5 shortcut carries, a collection in the Steam library.
    public static let tag = "AnyPS5"
    /// The option every AnyPS5 shortcut starts the launcher with.
    public static let launchFlag = "--steam"
    public static let backupSuffix = ".anyps5-backup"

    public init(install: SteamInstall, user: SteamUser) {
        self.install = install
        self.user = user
    }

    public var config: URL { install.userdata.appendingPathComponent(user.id).appendingPathComponent("config") }
    public var shortcutsFile: URL { config.appendingPathComponent("shortcuts.vdf") }
    public var backupFile: URL { URL(fileURLWithPath: shortcutsFile.path + Self.backupSuffix) }
    public var gridFolder: URL { config.appendingPathComponent("grid") }

    public func artPath(_ appID: UInt32, _ kind: SteamArt) -> URL { gridFolder.appendingPathComponent(kind.fileName(appID)) }

    public func read() throws -> ShortcutsFile {
        guard FileManager.default.fileExists(atPath: shortcutsFile.path) else { return .empty }
        let bytes = [UInt8](try Data(contentsOf: shortcutsFile))
        return bytes.isEmpty ? .empty : try ShortcutsFile(bytes: bytes)
    }

    /// AnyPS5's shortcuts there now.
    public func ours() -> [VdfMap] { (try? read().ours) ?? [] }

    /// Makes AnyPS5's shortcuts exactly `entries`: adds them, replaces the ones there, takes out
    /// ours no longer wanted (and their pictures), writes the pictures. Everything else in the
    /// file stays as it was; the file as it was is kept as shortcuts.vdf.anyps5-backup.
    @discardableResult
    public func put(_ entries: [SteamEntry]) throws -> SteamChange {
        var file = try read()
        let before = Set(file.ours.map(ShortcutsFile.appID(of:)))
        file.putOurs(entries.map(\.shortcut))
        let backup = try write(file)
        let wanted = Set(entries.map(\.shortcut.appID))
        for gone in before.subtracting(wanted) { deleteArt(gone) }
        var written: [URL] = []
        if entries.contains(where: { !$0.art.isEmpty }) {
            try FileManager.default.createDirectory(at: gridFolder, withIntermediateDirectories: true)
        }
        for entry in entries {
            for (kind, data) in entry.art {
                let path = artPath(entry.shortcut.appID, kind)
                try data.write(to: path, options: .atomic)
                written.append(path)
            }
        }
        return SteamChange(shortcutsFile: shortcutsFile, appIDs: entries.map(\.shortcut.appID), backup: backup, artFiles: written)
    }

    /// Takes out AnyPS5's shortcuts and their pictures; nothing else is touched. A file with none
    /// of ours is not written at all.
    @discardableResult
    public func remove() throws -> SteamChange {
        guard FileManager.default.fileExists(atPath: shortcutsFile.path) else {
            return SteamChange(shortcutsFile: shortcutsFile, appIDs: [], backup: nil, artFiles: [])
        }
        var file = try read()
        let removed = file.removeOurs()
        guard !removed.isEmpty else { return SteamChange(shortcutsFile: shortcutsFile, appIDs: [], backup: nil, artFiles: []) }
        let backup = try write(file)
        return SteamChange(shortcutsFile: shortcutsFile, appIDs: removed, backup: backup, artFiles: removed.flatMap(deleteArt))
    }

    @discardableResult
    private func deleteArt(_ appID: UInt32) -> [URL] {
        SteamArt.allCases.compactMap { kind in
            let path = artPath(appID, kind)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            try? FileManager.default.removeItem(at: path)
            return path
        }
    }

    /// Backs the old file up, then writes the new one beside it and moves it over.
    private func write(_ file: ShortcutsFile) throws -> URL? {
        let manager = FileManager.default
        var backup: URL?
        if manager.fileExists(atPath: shortcutsFile.path) {
            try? manager.removeItem(at: backupFile)
            try manager.copyItem(at: shortcutsFile, to: backupFile)
            backup = backupFile
        } else {
            try manager.createDirectory(at: config, withIntermediateDirectories: true)
        }
        let temporary = URL(fileURLWithPath: shortcutsFile.path + ".anyps5-new")
        try Data(file.bytes).write(to: temporary)
        guard Foundation.rename(temporary.path, shortcutsFile.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: shortcutsFile.path])
        }
        return backup
    }
}

/// The shortcuts this launcher makes: one for AnyPS5 itself, and with games on, one per
/// unlocked game that starts it with --play <title ID>.
public enum SteamPlan {
    public static let appName = "AnyPS5"

    public static func launchOptions(play: String? = nil, fullscreen: Bool = false) -> String {
        ([SteamShortcuts.launchFlag] + (fullscreen ? ["--fullscreen"] : []) + (play.map { ["--play", $0] } ?? [])).joined(separator: " ")
    }

    public static func launcher(program: String, fullscreen: Bool = false, into: SteamShortcuts? = nil) -> SteamShortcut {
        shortcut(program: program, name: appName, options: launchOptions(fullscreen: fullscreen), into: into)
    }

    public static func game(program: String, name: String, titleID: String, fullscreen: Bool = false, into: SteamShortcuts? = nil) -> SteamShortcut {
        shortcut(program: program, name: name, options: launchOptions(play: titleID, fullscreen: fullscreen), into: into)
    }

    private static func shortcut(program: String, name: String, options: String, into: SteamShortcuts?) -> SteamShortcut {
        let exe = SteamShortcut.quote(program)
        let id = SteamAppID.shortcut(exe: exe, appName: name)
        return SteamShortcut(appName: name, exe: exe, startDir: SteamShortcut.quote((program as NSString).deletingLastPathComponent),
                             launchOptions: options, icon: into?.artPath(id, .icon).path ?? "")
    }
}
