import Foundation

/// An add-on (DLC) the player dumped beside a game: a folder the engine mounts as /addcontN.
public struct GameAddon: Hashable, Sendable {
    public let folder: URL
    /// The entitlement label the game asks for (16 letters and digits at most).
    public let label: String
    /// The name in the add-on's param.json, else its label.
    public let name: String
}

/// A game update the player dumped beside a game: its files take the place of the game's.
public struct GameUpdate: Hashable, Sendable {
    public let folder: URL
    /// param.json's contentVersion, such as 01.004.000.
    public let version: String

    /// The version as the game page shows it: 01.004.000 is 01.004.
    public var shortVersion: String { GameAddons.shortVersion(version) }
}

/// Finds the updates and add-ons beside each game, in the layouts shadPS4 users already keep:
///
///     PPSA01234/                     the game
///     PPSA01234-UPDATE/ (or -patch)  its update, a dump of the patch package
///     PPSA01234-DLC/<label>/         one folder per add-on, named by its label or content ID
///     UP0000-PPSA01234_00-<label>/   an add-on in a folder named by its content ID
///
/// The game's own folder name or its title ID both work before the suffix. Only what is on the
/// disk is reported.
public enum GameAddons {
    static let updateSuffixes = ["-update", "-patch"]
    static let addonSuffixes = ["-dlc"]

    /// The environment the engine reads them from (ANYPS5_UPDATE_DIR, ANYPS5_ADDCONT_DIRS).
    public static func environment(for game: Game) -> [String: String] {
        var environment: [String: String] = [:]
        if let update = game.update { environment["ANYPS5_UPDATE_DIR"] = update.folder.path }
        if !game.addons.isEmpty { environment["ANYPS5_ADDCONT_DIRS"] = game.addons.map(\.folder.path).joined(separator: ":") }
        return environment
    }

    /// Takes the folders the games' updates and add-ons live in out of the games and the
    /// incomplete dumps of `survey`.
    static func attach(to survey: inout GameLibrary.Survey) {
        let claimed = survey.games.flatMap { game -> [String] in
            var folders = game.addons.map(\.folder)
            folders += game.addons.map { $0.folder.deletingLastPathComponent() }.filter { folder in addonSuffixes.contains { folder.lastPathComponent.lowercased().hasSuffix($0) } }
            if let update = game.update { folders.append(update.folder) }
            return folders.map { $0.standardizedFileURL.path }
        }
        guard !claimed.isEmpty else { return }
        func isClaimed(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.path
            return claimed.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        survey.games.removeAll { isClaimed($0.folder) }
        survey.incomplete.removeAll(where: isClaimed)
    }

    /// The update and add-ons beside the game in `folder`.
    static func look(beside folder: URL, titleID: String) -> (update: GameUpdate?, addons: [GameAddon]) {
        let parent = folder.deletingLastPathComponent()
        let fileManager = FileManager.default
        guard let siblings = try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return (nil, []) }
        let directories = siblings.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && $0.standardizedFileURL != folder.standardizedFileURL }
        let stems = Set([folder.lastPathComponent.lowercased(), titleID.lowercased()])
        func named(_ suffixes: [String]) -> [URL] {
            let names = Set(stems.flatMap { stem in suffixes.map { stem + $0 } })
            return directories.filter { names.contains($0.lastPathComponent.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        let update = named(updateSuffixes).lazy.compactMap { candidate in
            parameters(in: candidate).map { GameUpdate(folder: candidate, version: $0["contentVersion"] as? String ?? "") }
        }.first
        var addons: [GameAddon] = []
        func add(_ candidate: URL) {
            guard let addon = addon(in: candidate), !addons.contains(where: { $0.label == addon.label }) else { return }
            addons.append(addon)
        }
        for root in named(addonSuffixes) {
            let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                add(entry)
            }
        }
        for candidate in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = candidate.lastPathComponent
            guard labelOfContentID(name) != nil, contentIDTitle(name)?.caseInsensitiveCompare(titleID) == .orderedSame,
                  !fileManager.fileExists(atPath: candidate.appendingPathComponent("eboot.bin").path) else { continue }
            add(candidate)
        }
        return (update, addons)
    }

    /// The add-on in `folder`, nil when no entitlement label can be told from it.
    static func addon(in folder: URL) -> GameAddon? {
        let parameters = parameters(in: folder)
        guard let label = (parameters?["contentId"] as? String).flatMap(labelOfContentID) ?? label(ofFolderNamed: folder.lastPathComponent) else { return nil }
        return GameAddon(folder: folder, label: label, name: parameters.flatMap(title) ?? label)
    }

    /// The label of a folder named by its content ID or by the label itself.
    static func label(ofFolderNamed name: String) -> String? {
        labelOfContentID(name) ?? (validLabel(name) ? name : nil)
    }

    /// "UP0000-PPSA01234_00-ABCDEFGHIJKLMNOP": the entitlement label is the part after the last dash.
    static func labelOfContentID(_ id: String) -> String? {
        let characters = Array(id)
        guard characters.count == 36, characters[6] == "-", characters[16] == "_", characters[19] == "-" else { return nil }
        let label = String(characters[20...])
        return validLabel(label) ? label : nil
    }

    static func contentIDTitle(_ id: String) -> String? {
        let characters = Array(id)
        guard characters.count == 36 else { return nil }
        return String(characters[7..<16])
    }

    static func validLabel(_ label: String) -> Bool {
        !label.isEmpty && label.count <= 16 && label.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    static func parameters(in folder: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("sce_sys/param.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func title(_ parameters: [String: Any]) -> String? {
        let localized = parameters["localizedParameters"] as? [String: Any] ?? [:]
        let language = localized["defaultLanguage"] as? String ?? "en-US"
        let names = (localized[language] as? [String: Any]) ?? (localized["en-US"] as? [String: Any]) ?? [:]
        guard let name = names["titleName"] as? String, !name.isEmpty else { return nil }
        return name
    }

    /// 01.004.000 is 01.004; a version without a trailing .000 stays as it is.
    public static func shortVersion(_ version: String) -> String {
        version.hasSuffix(".000") && version.filter({ $0 == "." }).count == 2 ? String(version.dropLast(4)) : version
    }
}
