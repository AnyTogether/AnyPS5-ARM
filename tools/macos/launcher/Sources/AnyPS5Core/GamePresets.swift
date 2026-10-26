import Foundation

/// The console's Game Presets (Settings → Game Presets): the difficulty, performance or
/// resolution, camera inversion, subtitles and audio language a game that asks the console
/// (sceUserServiceGetGamePresets) starts with. Games that keep their own settings ignore them.
public struct GamePresets: Codable, Equatable, Sendable {
    public enum Difficulty: String, Codable, CaseIterable, Sendable {
        case gameDefault = "default", easiest, easy, normal, hard, hardest
    }

    public enum Priority: String, Codable, CaseIterable, Sendable {
        case gameDefault = "default", performance, resolution
    }

    public enum Subtitles: String, Codable, CaseIterable, Sendable {
        case gameDefault = "default", on, off
    }

    public var difficulty = Difficulty.gameDefault
    public var priority = Priority.gameDefault
    public var invertVerticalFirstPerson = false
    public var invertHorizontalFirstPerson = false
    public var invertVerticalThirdPerson = false
    public var invertHorizontalThirdPerson = false
    public var subtitles = Subtitles.gameDefault
    /// A console language number (ConsoleLanguage), nil for the game's default.
    public var audioLanguage: Int?

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field optional: a file from an older or newer launcher still loads.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        difficulty = (try? container.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? .gameDefault
        priority = (try? container.decodeIfPresent(Priority.self, forKey: .priority)) ?? .gameDefault
        invertVerticalFirstPerson = (try? container.decodeIfPresent(Bool.self, forKey: .invertVerticalFirstPerson)) ?? false
        invertHorizontalFirstPerson = (try? container.decodeIfPresent(Bool.self, forKey: .invertHorizontalFirstPerson)) ?? false
        invertVerticalThirdPerson = (try? container.decodeIfPresent(Bool.self, forKey: .invertVerticalThirdPerson)) ?? false
        invertHorizontalThirdPerson = (try? container.decodeIfPresent(Bool.self, forKey: .invertHorizontalThirdPerson)) ?? false
        subtitles = (try? container.decodeIfPresent(Subtitles.self, forKey: .subtitles)) ?? .gameDefault
        audioLanguage = try? container.decodeIfPresent(Int.self, forKey: .audioLanguage)
    }

    /// Whether nothing is set: games start as they would on a fresh console.
    public var isEmpty: Bool { self == GamePresets() }

    /// ANYPS5_GAME_PRESETS as the engine reads it: comma-separated key=value parts.
    public var engineValue: String {
        func flag(_ on: Bool) -> String { on ? "1" : "0" }
        return [
            "difficulty=" + difficulty.rawValue,
            "priority=" + priority.rawValue,
            "invert_1st_v=" + flag(invertVerticalFirstPerson),
            "invert_1st_h=" + flag(invertHorizontalFirstPerson),
            "invert_3rd_v=" + flag(invertVerticalThirdPerson),
            "invert_3rd_h=" + flag(invertHorizontalThirdPerson),
            "subtitles=" + subtitles.rawValue,
            "audio_language=" + (audioLanguage.map(String.init) ?? "default"),
        ].joined(separator: ",")
    }

    /// The environment a game starts with; empty when nothing is set.
    public var environment: [String: String] {
        isEmpty ? [:] : ["ANYPS5_GAME_PRESETS": engineValue]
    }
}

/// Where a profile's presets are kept: one small file of their own in the profile's folder
/// (ProfileStore.gamePresetsFile), removed with the profile.
public struct GamePresetsStore: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func load() -> GamePresets {
        guard let data = try? Data(contentsOf: file), let presets = try? JSONDecoder().decode(GamePresets.self, from: data) else { return GamePresets() }
        return presets
    }

    public func save(_ presets: GamePresets) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: file, options: .atomic)
    }
}

extension ProfileStore {
    /// The Game Presets of profile `id`, beside its picture in the profile's folder.
    public func gamePresetsFile(for id: String) -> URL {
        folder.appendingPathComponent(id).appendingPathComponent("GamePresets.json")
    }
}
