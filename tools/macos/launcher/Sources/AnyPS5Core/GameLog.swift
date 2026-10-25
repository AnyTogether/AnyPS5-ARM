import Foundation

/// The game logs the launcher keeps in ~/Library/Logs/AnyPS5: one per game, appended to by
/// each start, and the output of the game's last unlock.
public enum GameLog {
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AnyPS5")
    }

    public static func file(titleID: String, in folder: URL = folder) -> URL {
        folder.appendingPathComponent("\(titleID).log")
    }

    public static func unlockFile(titleID: String, in folder: URL = folder) -> URL {
        folder.appendingPathComponent("\(titleID)-unlock.log")
    }

    /// Keeps what the unlock printed, and the error it stopped on, for the next report.
    public static func writeUnlockLog(_ lines: [String], failure: String?, titleID: String, in folder: URL = folder) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = (lines + (failure.map { [$0] } ?? [])).map { $0 + "\n" }.joined()
        try Data(text.utf8).write(to: unlockFile(titleID: titleID, in: folder), options: .atomic)
    }

    public static func readUnlockLog(titleID: String, in folder: URL = folder) -> String? {
        try? String(contentsOf: unlockFile(titleID: titleID, in: folder), encoding: .utf8)
    }

    /// A log grown past `limit` becomes <name>.previous.log before the next start, so one log
    /// never grows without end; the one before that is dropped.
    @discardableResult
    public static func rollForStart(_ file: URL, limit: Int64 = 32 << 20) -> Bool {
        guard size(of: file) > limit else { return false }
        let previous = file.deletingPathExtension().appendingPathExtension("previous.log")
        try? FileManager.default.removeItem(at: previous)
        return (try? FileManager.default.moveItem(at: file, to: previous)) != nil
    }

    /// While a game logs in detail: a log past `cap` is kept as <name>.trace-1.log (a clone, no
    /// copying) and starts again empty, so at most twice the cap stays on disk. The game writes
    /// with O_APPEND and goes on at the new end; lines written in the moment between the clone
    /// and the truncation are lost.
    @discardableResult
    public static func trim(_ file: URL, cap: Int64) -> Bool {
        guard size(of: file) > cap else { return false }
        let part = file.deletingPathExtension().appendingPathExtension("trace-1.log")
        try? FileManager.default.removeItem(at: part)
        guard (try? FileManager.default.copyItem(at: file, to: part)) != nil, let handle = try? FileHandle(forWritingTo: file) else { return false }
        defer { try? handle.close() }
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: Data("[anyps5-launcher] log rotated at \(cap >> 20) MiB; the lines before are in \(part.lastPathComponent)\n".utf8))
        return true
    }

    /// The last `bytes` of a log, as text.
    public static func tail(_ file: URL, bytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > UInt64(bytes) ? end - UInt64(bytes) : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }

    public static func size(of file: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// Detailed logging: the engine's most talkative switches that are safe to leave on for a whole
/// session. The engine has no single log level (its debug lines are compiled out unless built
/// with APS5_DEBUG_LOG, and APS5_TRACE_CALLS works only on Windows and Linux), so these are the
/// runtime switches it does have.
public enum TraceMode {
    public static let environment: [String: String] = [
        // Every line written as it comes, none coalesced and none lost in the queue at a crash.
        "APS5_LOG_SYNC": "1",
        "APS5_LOG_TIMESTAMPS": "1",
        // Who called exit() or _Exit() and with which status.
        "APS5_TRACE_EXIT": "1",
        // The code that checked a guest address it could not read, before it stops on it.
        "APS5_TRACE_UNREADABLE": "1",
        // The game's memory maps, unmaps and protections.
        "APS5_TRACE_MEMORY": "1",
        // Every save data call instead of the first three.
        "APS5_SAVEDATA_TRACE": "1",
        // Presented frames every ten seconds.
        "APS5_PROFILE_PRESENT": "1",
        // MoltenVK's errors, warnings and notes.
        "MVK_CONFIG_LOG_LEVEL": "3",
    ]

    /// A detailed log past this starts again (GameLog.trim), the earlier part kept beside it.
    public static let cap: Int64 = 256 << 20
}
