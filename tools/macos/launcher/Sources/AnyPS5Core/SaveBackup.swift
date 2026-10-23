import Foundation

/// A game's saves and trophies as one zip: the save data (_sd), the save memory (_sd_mem) and
/// the earned trophies (_trophy) from its game folder, and nothing else.
public enum SaveBackup {
    public static let parts = ["_sd", "_sd_mem", "_trophy"]

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Where a game's backups go: one folder per game, under ~/Documents/AnyPS5/Backups.
    public static func folder(for game: Game) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnyPS5/Backups/\(game.name.replacingOccurrences(of: "/", with: "-")) (\(game.titleID))")
    }

    /// Zips the saves of the game folder `game` into `folder`, named after `date`.
    @discardableResult
    public static func backUp(_ game: URL, to folder: URL, date: Date) throws -> URL {
        let present = parts.filter { FileManager.default.fileExists(atPath: game.appendingPathComponent($0).path) }
        guard !present.isEmpty else { throw Failure(description: "the game has no saves yet") }
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for part in present {
            try FileManager.default.copyItem(at: game.appendingPathComponent(part).resolvingSymlinksInPath(), to: stage.appendingPathComponent(part))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = formatter.string(from: date)
        var zip = folder.appendingPathComponent(name + ".zip")
        var copy = 2
        while FileManager.default.fileExists(atPath: zip.path) {
            zip = folder.appendingPathComponent("\(name) \(copy).zip")
            copy += 1
        }
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", stage.path, zip.path])
        return zip
    }

    /// The game's backups, newest first.
    public static func backups(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "zip" }.sorted { date($0) > date($1) || (date($0) == date($1) && $0.lastPathComponent > $1.lastPathComponent) }
    }

    private static func date(_ url: URL) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
    }

    /// The files a backup holds, relative to the game folder.
    public static func contents(of backup: URL) throws -> [String] {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", backup.path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "not a backup") }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") }
    }

    /// Puts the backup's saves in place of the game's. What the game had is backed up into
    /// `keepingIn` first, so a restore never loses anything.
    public static func restore(_ backup: URL, into game: URL, keepingIn folder: URL, date: Date) throws {
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: unpacked) }
        do {
            try run("/usr/bin/ditto", ["-x", "-k", backup.path, unpacked.path])
        } catch {
            throw Failure(description: "not a backup")
        }
        let restored = parts.filter { FileManager.default.fileExists(atPath: unpacked.appendingPathComponent($0).path) }
        guard !restored.isEmpty else { throw Failure(description: "the file holds no saves") }
        if parts.contains(where: { FileManager.default.fileExists(atPath: game.appendingPathComponent($0).path) }) {
            try backUp(game, to: folder, date: date)
        }
        for part in restored {
            let target = game.appendingPathComponent(part)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: unpacked.appendingPathComponent(part), to: target)
        }
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "\(tool) failed") }
    }
}

/// The F12 screenshots the engine writes, named <title ID>-<yyyyMMdd-HHmmss>[-n].png, and the
/// launcher's clips beside them, named the same way but .mp4.
public enum Screenshots {
    /// The game's screenshots and clips, newest first.
    public static func list(titleID: String, in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { ["png", "mp4"].contains($0.pathExtension.lowercased()) && $0.lastPathComponent.hasPrefix(titleID + "-") }
            .sorted { $0.deletingPathExtension().lastPathComponent > $1.deletingPathExtension().lastPathComponent }
    }

    public static func isClip(_ file: URL) -> Bool {
        file.pathExtension.lowercased() == "mp4"
    }
}
