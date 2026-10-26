import Foundation

/// Each profile's saves and trophies for a game. The engine reads and writes them in the game
/// folder (_sd, _sd_mem, _trophy, one engine user for everyone); the launcher keeps the playing
/// profile's there and every other profile's parked in `_profiles/<id>`, and swaps them with
/// renames on the same volume before the profile plays. A mark file says whose are in place; a
/// folder without one holds the saves from before profiles, the first profile's.
///
/// A swap cut short is put right by the next one: whatever the mark, the in-place parts are
/// parked under their owner first, then the mark changes, then the profile's parts come back.
public enum ProfileSaves {
    public static let parts = SaveBackup.parts
    static let markName = ".anyps5-profile"
    static let parkName = "_profiles"

    public static func owner(of game: URL, legacyOwner: String) -> String {
        let mark = (try? String(contentsOf: game.appendingPathComponent(markName), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return mark.flatMap { $0.isEmpty ? nil : $0 } ?? legacyOwner
    }

    /// Where a profile's saves wait while another plays.
    public static func parked(_ profile: String, in game: URL) -> URL {
        game.appendingPathComponent(parkName).appendingPathComponent(profile)
    }

    /// Puts `profile`'s saves in the game folder, parking the ones there now under their owner.
    public static func activate(_ profile: String, in game: URL, legacyOwner: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: game.path) else { return }
        let owner = owner(of: game, legacyOwner: legacyOwner)
        if owner != profile {
            try park(owner, in: game)
            try mark(game, profile)
        } else if !fileManager.fileExists(atPath: game.appendingPathComponent(markName).path) {
            try mark(game, profile)
        }
        let parked = parked(profile, in: game)
        for part in parts where fileManager.fileExists(atPath: parked.appendingPathComponent(part).path) {
            let target = game.appendingPathComponent(part)
            // Something of the profile's own already in place (the game ran meanwhile): it stays,
            // the parked copy is kept aside.
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.moveItem(at: parked.appendingPathComponent(part), to: aside(parked.appendingPathComponent(part)))
                continue
            }
            try fileManager.moveItem(at: parked.appendingPathComponent(part), to: target)
        }
        // The parking place goes once nothing is left in it.
        if (try? fileManager.contentsOfDirectory(atPath: parked.path))?.isEmpty == true { try? fileManager.removeItem(at: parked) }
        let root = game.appendingPathComponent(parkName)
        if (try? fileManager.contentsOfDirectory(atPath: root.path))?.isEmpty == true { try? fileManager.removeItem(at: root) }
    }

    /// Deletes a profile's saves for the game, in place or parked (back them up first).
    public static func remove(_ profile: String, in game: URL, legacyOwner: String) throws {
        let fileManager = FileManager.default
        if owner(of: game, legacyOwner: legacyOwner) == profile {
            try park(profile, in: game)
        }
        let parked = parked(profile, in: game)
        if fileManager.fileExists(atPath: parked.path) { try fileManager.removeItem(at: parked) }
        let root = game.appendingPathComponent(parkName)
        if (try? fileManager.contentsOfDirectory(atPath: root.path))?.isEmpty == true { try? fileManager.removeItem(at: root) }
    }

    /// The in-place parts into `profile`'s parking place; one parked already is kept aside.
    private static func park(_ profile: String, in game: URL) throws {
        let fileManager = FileManager.default
        let parked = parked(profile, in: game)
        let present = parts.filter { fileManager.fileExists(atPath: game.appendingPathComponent($0).path) }
        guard !present.isEmpty else { return }
        try fileManager.createDirectory(at: parked, withIntermediateDirectories: true)
        for part in present {
            let target = parked.appendingPathComponent(part)
            if fileManager.fileExists(atPath: target.path) { try fileManager.moveItem(at: target, to: aside(target)) }
            try fileManager.moveItem(at: game.appendingPathComponent(part), to: target)
        }
    }

    private static func mark(_ game: URL, _ profile: String) throws {
        try Data(profile.utf8).write(to: game.appendingPathComponent(markName), options: .atomic)
    }

    /// `_sd.<date>` beside it: never overwritten, never lost.
    private static func aside(_ item: URL) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var candidate = item.deletingLastPathComponent().appendingPathComponent("\(item.lastPathComponent).\(stamp)")
        var count = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            count += 1
            candidate = item.deletingLastPathComponent().appendingPathComponent("\(item.lastPathComponent).\(stamp)-\(count)")
        }
        return candidate
    }
}
