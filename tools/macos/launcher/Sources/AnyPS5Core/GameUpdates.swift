import Foundation

/// Why a folder cannot be a game's update.
public enum UpdateProblem: Equatable, Sendable {
    /// No eboot.bin and sce_sys/param.json in it.
    case notADump
    /// The dump of another title.
    case otherGame
    /// The game's own folder, or a dump no newer than the game.
    case notNewer
    /// The game has an update of this version or a newer one already.
    case haveNewer
    /// The game has an older update: its folder has to go first.
    case haveOlder
}

/// A dump of a game's update (its patch package), checked to be newer than the game.
public struct UpdateCandidate: Equatable, Sendable {
    public let folder: URL
    public let titleID: String
    /// param.json's contentVersion, such as 01.005.000.
    public let version: String

    public init(folder: URL, titleID: String, version: String) {
        self.folder = folder
        self.titleID = titleID
        self.version = version
    }

    public var shortVersion: String { GameAddons.shortVersion(version) }
}

/// A game's update added from a dump the player has: put beside the game as
/// `<game folder>-UPDATE`, the layout GameAddons reads (ANYPS5_UPDATE_DIR, and the files the
/// unlock takes from it), so the next unlock applies it and the game's own folder is never written
/// to. The same rules as AnyLauncher Port's game_updates.dart.
public enum GameUpdates {
    /// Where `game`'s update goes: beside it, named as its folder with -UPDATE.
    public static func target(_ game: Game) -> URL {
        game.folder.deletingLastPathComponent().appendingPathComponent(game.folder.lastPathComponent + "-UPDATE")
    }

    /// -1, 0 or 1 as version `a` is older, the same or newer than `b` (01.004.000 against
    /// 01.010.000: number by number).
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        func numbers(_ version: String) -> [Int] {
            version.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
        }
        let left = numbers(a), right = numbers(b)
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0
            let y = index < right.count ? right[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// Whether the dump of title `titleID` at `version` would be `game`'s update.
    public static func problem(with game: Game, titleID: String, version: String) -> UpdateProblem? {
        if titleID.uppercased() != game.titleID.uppercased() { return .otherGame }
        if compareVersions(version, game.version) <= 0 { return .notNewer }
        if let existing = game.update {
            return compareVersions(version, existing.version) <= 0 ? .haveNewer : .haveOlder
        }
        if FileManager.default.fileExists(atPath: target(game).path) { return .haveOlder }
        return nil
    }

    /// The update in `folder` for `game`, or why it is not one.
    public static func check(_ folder: URL, for game: Game) -> (update: UpdateCandidate?, problem: UpdateProblem?) {
        let chosen = folder.standardizedFileURL.path, own = game.folder.standardizedFileURL.path
        if chosen == own || own.hasPrefix(chosen + "/") || chosen.hasPrefix(own + "/") { return (nil, .notNewer) }
        guard let parameters = GameAddons.parameters(in: folder),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("eboot.bin").path),
              let titleID = parameters["titleId"] as? String, let version = parameters["contentVersion"] as? String else { return (nil, .notADump) }
        if let problem = problem(with: game, titleID: titleID, version: version) { return (nil, problem) }
        return (UpdateCandidate(folder: folder, titleID: titleID, version: version), nil)
    }

    /// Whether two paths are on one volume, so a move is a rename that takes no room.
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        func volume(_ url: URL) -> NSObject? {
            var probe = url
            while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
            return (try? probe.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let left = volume(a), let right = volume(b) else { return false }
        return left.isEqual(right)
    }

    /// Puts `update` beside `game`: moved when it is on the same volume (a rename), copied into a
    /// hidden folder and renamed when it is not, so a half-copied update is never read. Gives
    /// whether it was moved. `progress` hears the bytes copied and the whole.
    @discardableResult
    public static func install(_ update: UpdateCandidate, for game: Game, progress: ((Int64, Int64) -> Void)? = nil, cancel: UnpackCancel? = nil) throws -> Bool {
        let into = target(game)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: into.path) { throw ArchiveError("The game has an update folder already: \(into.path)") }
        if sameVolume(update.folder, into.deletingLastPathComponent()) {
            // rename(2): never a copy that FileManager.moveItem would make across volumes.
            if rename(update.folder.path, into.path) == 0 { return true }
        }
        let partial = into.deletingLastPathComponent().appendingPathComponent(".\(into.lastPathComponent).copying")
        try? fileManager.removeItem(at: partial)
        try copySync(from: update.folder, into: partial, progress: progress, cancelled: cancel.map { cancel in { cancel.cancelled } })
        do {
            try fileManager.moveItem(at: partial, to: into)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
        return false
    }

    /// Copies the folder `from` to `into` (made fresh), files and folders only; `into` is removed
    /// again on a failure or `UnpackCancelled`.
    public static func copySync(from: URL, into: URL, progress: ((Int64, Int64) -> Void)? = nil, cancelled: (() -> Bool)? = nil) throws {
        let fileManager = FileManager.default
        let base = from.standardizedFileURL.path
        do {
            var folders: [String] = [], files: [(String, Int64)] = []
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let walk = fileManager.enumerator(at: from, includingPropertiesForKeys: keys) else { throw ArchiveError("\(from.path) cannot be read") }
            for case let url as URL in walk {
                let values = try url.resourceValues(forKeys: Set(keys))
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(base + "/") else { continue }
                let relative = String(path.dropFirst(base.count + 1))
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true { folders.append(relative) } else if values.isRegularFile == true { files.append((relative, Int64(values.fileSize ?? 0))) }
            }
            let total = files.reduce(Int64(0)) { $0 + $1.1 }
            try fileManager.createDirectory(at: into, withIntermediateDirectories: true)
            for folder in folders { try fileManager.createDirectory(at: into.appendingPathComponent(folder), withIntermediateDirectories: true) }
            var done: Int64 = 0, reported: Int64 = 0
            progress?(0, total)
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: 8 * 1024 * 1024, alignment: 16)
            defer { buffer.deallocate() }
            for (relative, _) in files {
                let source = open(from.appendingPathComponent(relative).path, O_RDONLY | O_NOFOLLOW)
                guard source >= 0 else { throw ArchiveError("\(relative) cannot be read: \(String(cString: strerror(errno)))") }
                defer { close(source) }
                let target = into.appendingPathComponent(relative)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let output = open(target.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o644)
                guard output >= 0 else { throw ArchiveError("\(relative) cannot be written: \(String(cString: strerror(errno)))") }
                defer { close(output) }
                while true {
                    if cancelled?() == true { throw UnpackCancelled() }
                    let count = read(source, buffer, 8 * 1024 * 1024)
                    if count == 0 { break }
                    guard count > 0 else { throw ArchiveError("\(relative) cannot be read: \(String(cString: strerror(errno)))") }
                    var offset = 0
                    while offset < count {
                        let wrote = write(output, buffer + offset, count - offset)
                        guard wrote > 0 else { throw ArchiveError("\(relative) cannot be written: \(String(cString: strerror(errno)))") }
                        offset += wrote
                    }
                    done += Int64(count)
                    if done - reported >= GameArchives.reportEvery {
                        reported = done
                        progress?(done, total)
                    }
                }
            }
            progress?(total, total)
        } catch {
            try? fileManager.removeItem(at: into)
            throw error
        }
    }
}
