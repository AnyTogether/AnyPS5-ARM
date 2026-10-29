import Foundation

/// A PS5 game dump found in the games folder: a folder with sce_sys/param.json and an eboot.bin.
public struct Game: Identifiable, Hashable, Sendable {
    public enum Executable: Sendable {
        /// A plain ELF (an unwrapped dump).
        case elf
        /// A SELF container, or a re-signed one with its ELF kept as eboot.bin.esbak.
        case container
        /// Neither: an encrypted or unknown file.
        case unreadable
    }

    public var id: String { folder.path }
    public let folder: URL
    public let titleID: String
    public let name: String
    public let version: String
    public let icon: URL?
    public let background: URL?
    public let music: URL?
    public let executable: Executable
    /// The age ratings in param.json's `ageLevel`: "default" or a region ("US") to an age.
    public var ageLevels: [String: Int]? = nil
    /// The update dumped beside the game (GameAddons), nil when there is none.
    public var update: GameUpdate? = nil
    /// The add-ons dumped beside the game (GameAddons).
    public var addons: [GameAddon] = []

    public var bundleIdentifier: String {
        "org.anyps5." + titleID.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func == (left: Game, right: Game) -> Bool { left.folder == right.folder }
    public func hash(into hasher: inout Hasher) { hasher.combine(folder) }
}

public enum GameLibrary {
    /// Where the launcher keeps what it makes inside the games folder: on the same volume, so the
    /// installed copies of the game files are APFS clones that take no space.
    public static let storeName = ".AnyPS5"
    static let skipped: Set<String> = [storeName, "sce_sys", "sce_module", "sce_modules", "prx", "out", "rel"]

    /// What a look through the games folder found: the games, and the folders that look like a
    /// game still being copied (a sce_sys folder or an eboot.bin, but no whole game yet).
    public struct Survey: Sendable {
        public var games: [Game] = []
        public var incomplete: [URL] = []
    }

    /// Finds every game folder under `root`, down to three levels.
    public static func scan(_ root: URL) -> [Game] {
        survey(root).games
    }

    /// The games under `root` and the dumps that are not whole yet. Cheap: a folder listing per
    /// level and each game's param.json.
    public static func survey(_ root: URL) -> Survey {
        var found = Survey()
        visit(root, depth: 0, into: &found)
        GameAddons.attach(to: &found)
        found.games.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return found
    }

    /// One of the user's games folders as the last look found it: there or not (a drive
    /// unplugged), and how many games it holds.
    public struct FolderStatus: Equatable, Sendable {
        public let url: URL
        public let connected: Bool
        public let games: Int
        public init(url: URL, connected: Bool, games: Int) {
            self.url = url
            self.connected = connected
            self.games = games
        }
    }

    /// What a look through all the games folders found: the library (their union), the folder
    /// each game came from, and each folder's state.
    public struct Library: Sendable {
        public var games: [Game] = []
        /// Game ID (its folder's path) to the games folder it was found in: where its unlocked
        /// copy lives (the folder's store, on the same drive).
        public var roots: [String: URL] = [:]
        public var folders: [FolderStatus] = []
        public var incomplete: [URL] = []
        public init() {}
    }

    /// The games under every folder in `roots`, in their order. A folder that is not there is
    /// skipped and said to be not connected.
    public static func survey(roots: [URL]) -> Library {
        let fileManager = FileManager.default
        return merge(roots.map { root in
            var directory: ObjCBool = false
            let there = fileManager.fileExists(atPath: root.path, isDirectory: &directory) && directory.boolValue
            return (root, there ? survey(root) : nil)
        })
    }

    /// The union of the folders' surveys (nil for a folder that is not there). A game (title ID)
    /// in several folders shows once, from the folder earliest in the list; two dumps of one game
    /// in the same folder both show, as with a single folder.
    public static func merge(_ surveys: [(root: URL, survey: Survey?)]) -> Library {
        var library = Library()
        var earlier = Set<String>()
        for (root, survey) in surveys {
            guard let survey else {
                library.folders.append(FolderStatus(url: root, connected: false, games: 0))
                continue
            }
            library.folders.append(FolderStatus(url: root, connected: true, games: survey.games.count))
            library.incomplete += survey.incomplete
            for game in survey.games where !earlier.contains(game.titleID) && library.roots[game.id] == nil {
                library.games.append(game)
                library.roots[game.id] = root
            }
            earlier.formUnion(survey.games.map(\.titleID))
        }
        library.games.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return library
    }

    /// Whether two scans show the same library: the same folders, names, art and states.
    public static func sameListing(_ left: [Game], _ right: [Game]) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.folder == b.folder && a.titleID == b.titleID && a.name == b.name && a.version == b.version && a.icon == b.icon
                && a.background == b.background && a.music == b.music && a.executable == b.executable && a.ageLevels == b.ageLevels
                && a.update == b.update && a.addons == b.addons
        }
    }

    static func visit(_ folder: URL, depth: Int, into found: inout Survey) {
        if let game = inspect(folder) {
            found.games.append(game)
            return
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.appendingPathComponent("sce_sys").path) || fileManager.fileExists(atPath: folder.appendingPathComponent("eboot.bin").path) {
            found.incomplete.append(folder)
        }
        guard depth < 3, let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return }
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values?.isDirectory == true, values?.isPackage != true, !skipped.contains(entry.lastPathComponent) else { continue }
            visit(entry, depth: depth + 1, into: &found)
        }
    }

    public static func inspect(_ folder: URL) -> Game? {
        let fileManager = FileManager.default
        let system = folder.appendingPathComponent("sce_sys")
        let eboot = folder.appendingPathComponent("eboot.bin")
        guard fileManager.fileExists(atPath: eboot.path),
              let data = try? Data(contentsOf: system.appendingPathComponent("param.json")),
              let parameters = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let titleID = parameters["titleId"] as? String ?? folder.lastPathComponent
        let localized = parameters["localizedParameters"] as? [String: Any] ?? [:]
        let language = localized["defaultLanguage"] as? String ?? parameters["defaultLanguage"] as? String ?? "en-US"
        let names = (localized[language] as? [String: Any]) ?? (localized["en-US"] as? [String: Any]) ?? [:]
        let name = names["titleName"] as? String ?? titleID
        let version = parameters["contentVersion"] as? String ?? "1.0"
        func existing(_ name: String) -> URL? {
            let url = system.appendingPathComponent(name)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        let executable: Game.Executable
        if Elf.isElf(eboot) {
            executable = .elf
        } else if SelfUnwrap.isContainer(eboot) || Elf.isElf(eboot.appendingPathExtension("esbak")) {
            executable = .container
        } else {
            executable = .unreadable
        }
        let beside = GameAddons.look(beside: folder, titleID: titleID)
        return Game(folder: folder, titleID: titleID, name: name, version: version, icon: existing("icon0.png"), background: existing("pic0.png"), music: existing("snd0.at9"), executable: executable,
                    ageLevels: ageLevels(parameters["ageLevel"]), update: beside.update, addons: beside.addons)
    }

    /// The numbers of an `ageLevel` object; nil when there is none.
    static func ageLevels(_ value: Any?) -> [String: Int]? {
        guard let object = value as? [String: Any] else { return nil }
        let levels = object.compactMapValues { value -> Int? in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.intValue
        }
        return levels.isEmpty ? nil : levels
    }

    /// The total allocated size of a folder.
    public static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}

enum Elf {
    static func isElf(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 4) == Data([0x7F, 0x45, 0x4C, 0x46])
    }
}

/// The user's games folders, an ordered list of paths: the library is all of them, and the first
/// is the one the first-run setup picks. Launchers before this kept a single folder.
public enum LibraryFolders {
    /// The list kept, or the single folder of an older launcher's settings as a list of one. The
    /// list keeps its first folder in `legacy` too; when the two differ, an older launcher chose
    /// another folder since, and that one becomes the first.
    public static func list(_ folders: [String]?, legacy: String?) -> [String] {
        guard let folders else { return legacy.map { [$0] } ?? [] }
        guard let legacy, folders.first != legacy else { return folders }
        return replacingFirst(with: legacy, in: folders)
    }

    /// `folders` with `path` added at the end; a folder already in the list (as it is written, or
    /// once standardized) is not added again.
    public static func adding(_ path: String, to folders: [String]) -> [String] {
        let key = standard(path)
        return folders.contains { standard($0) == key } ? folders : folders + [path]
    }

    /// `folders` with `path` as the first one: the first-run setup choosing again. A folder that
    /// was further down moves up rather than showing twice.
    public static func replacingFirst(with path: String, in folders: [String]) -> [String] {
        let key = standard(path)
        let rest = folders.dropFirst().filter { standard($0) != key }
        return [path] + rest
    }

    public static func removing(_ path: String, from folders: [String]) -> [String] {
        let key = standard(path)
        return folders.filter { standard($0) != key }
    }

    static func standard(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
