import CryptoKit
import Foundation

/// A game's saves and trophies kept in step through a folder other Macs see too (iCloud Drive,
/// or any synced or shared folder). The folder holds the latest saves as one zip with who wrote
/// them, when, and a digest of what they hold; each Mac remembers the digest it last synced. A
/// side that alone changed since then is taken; where both did, the newer wins, and the other is
/// kept: a download backs up the Mac's saves first, an upload keeps the replaced zip in Older.
public struct SaveSync: Sendable {
    public enum Outcome: Equatable, Sendable {
        case unchanged
        case uploaded
        case downloaded(from: String)
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// What the folder says of the saves in it.
    struct Info: Codable {
        var mac: String
        var date: Date
        var digest: String
    }

    /// What this Mac last synced.
    struct State: Codable {
        var digest: String
    }

    public let game: URL
    public let cloud: URL
    public let backups: URL
    public let mac: String

    /// `game` is the game folder (its saves in _sd, _sd_mem, _trophy), `cloud` the game's folder
    /// in the sync folder, `backups` where this Mac's saves go before a download replaces them.
    public init(game: URL, cloud: URL, backups: URL, mac: String) {
        self.game = game
        self.cloud = cloud
        self.backups = backups
        self.mac = mac
    }

    /// The game's folder in a sync folder: <sync>/AnyPS5/Saves/<title ID>.
    public static func folder(in sync: URL, titleID: String) -> URL {
        sync.appendingPathComponent("AnyPS5/Saves/\(titleID)")
    }

    /// iCloud Drive's folder, where it is set up on this Mac.
    public static var iCloudDrive: URL? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    var zip: URL { cloud.appendingPathComponent("saves.zip") }
    var infoFile: URL { cloud.appendingPathComponent("info.json") }
    var older: URL { cloud.appendingPathComponent("Older") }
    var stateFile: URL { game.deletingLastPathComponent().appendingPathComponent("anyps5-sync.json") }

    public func sync(date: Date) throws -> Outcome {
        let local = SaveSync.digest(of: game)
        let info = try readInfo()
        let state = (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder.sync.decode(State.self, from: $0) }
        switch (local, info) {
        case (nil, nil):
            return .unchanged
        case (_?, nil):
            return try upload(date: date)
        case (nil, let info?):
            return try download(info, date: date)
        case let (local?, info?):
            if local == info.digest {
                try record(local)
                return .unchanged
            }
            let localChanged = local != state?.digest
            let cloudChanged = info.digest != state?.digest
            if localChanged && !cloudChanged { return try upload(date: date) }
            if cloudChanged && !localChanged { return try download(info, date: date) }
            return SaveSync.lastChange(in: game) > info.date ? try upload(date: date) : try download(info, date: date)
        }
    }

    private func upload(date: Date) throws -> Outcome {
        guard let digest = SaveSync.digest(of: game) else { return .unchanged }
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        let made = try SaveBackup.backUp(game, to: stage, date: date)
        if FileManager.default.fileExists(atPath: zip.path) {
            try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
            let kept = older.appendingPathComponent("\(SaveSync.stamp(FileManager.default.modificationDate(of: zip) ?? date)).zip")
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.moveItem(at: zip, to: kept)
            for extra in SaveBackup.backups(in: older).dropFirst(5) { try? FileManager.default.removeItem(at: extra) }
        }
        try FileManager.default.moveItem(at: made, to: zip)
        try JSONEncoder.sync.encode(Info(mac: mac, date: date, digest: digest)).write(to: infoFile, options: .atomic)
        try record(digest)
        return .uploaded
    }

    private func download(_ info: Info, date: Date) throws -> Outcome {
        try SaveSync.materialize(zip)
        try SaveBackup.restore(zip, into: game, keepingIn: backups, date: date)
        try record(SaveSync.digest(of: game) ?? info.digest)
        return .downloaded(from: info.mac)
    }

    private func readInfo() throws -> Info? {
        try? SaveSync.materialize(infoFile)
        guard let data = try? Data(contentsOf: infoFile) else { return nil }
        guard let info = try? JSONDecoder.sync.decode(Info.self, from: data) else { throw Failure(description: "the sync folder's info.json cannot be read") }
        return info
    }

    private func record(_ digest: String) throws {
        try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.sync.encode(State(digest: digest)).write(to: stateFile, options: .atomic)
    }

    /// A file iCloud Drive keeps only in the cloud (a .<name>.icloud placeholder) is fetched first.
    static func materialize(_ file: URL) throws {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let placeholder = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        guard FileManager.default.fileExists(atPath: placeholder.path) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: file)
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: file.path) {
            guard Date() < deadline else { throw Failure(description: "iCloud Drive did not bring \(file.lastPathComponent) down in time") }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// A digest of every save and trophy file, by its path and contents; nil without any.
    static func digest(of game: URL) -> String? {
        var hasher = SHA256()
        var any = false
        for part in SaveBackup.parts {
            let folder = game.appendingPathComponent(part).resolvingSymlinksInPath()
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            let files = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            for file in files.sorted(by: { $0.path < $1.path }) {
                guard let data = try? Data(contentsOf: file) else { continue }
                hasher.update(data: Data((part + "/" + file.path.dropFirst(folder.path.count)).utf8))
                hasher.update(data: data)
                any = true
            }
        }
        return any ? hasher.finalize().map { String(format: "%02x", $0) }.joined() : nil
    }

    /// When a save or trophy file last changed.
    static func lastChange(in game: URL) -> Date {
        var latest = Date.distantPast
        for part in SaveBackup.parts {
            let folder = game.appendingPathComponent(part).resolvingSymlinksInPath()
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let file as URL in enumerator {
                if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > latest { latest = date }
            }
        }
        return latest
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}

private extension FileManager {
    func modificationDate(of file: URL) -> Date? {
        (try? attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}

private extension JSONEncoder {
    static var sync: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sync: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
