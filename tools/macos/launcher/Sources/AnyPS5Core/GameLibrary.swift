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

    /// Finds every game folder under `root`, down to three levels.
    public static func scan(_ root: URL) -> [Game] {
        var found: [Game] = []
        visit(root, depth: 0, into: &found)
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func visit(_ folder: URL, depth: Int, into found: inout [Game]) {
        if let game = inspect(folder) {
            found.append(game)
            return
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
        return Game(folder: folder, titleID: titleID, name: name, version: version, icon: existing("icon0.png"), background: existing("pic0.png"), music: existing("snd0.at9"), executable: executable,
                    ageLevels: ageLevels(parameters["ageLevel"]))
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
