import Foundation

/// The per-game choices the launcher passes to a started game as environment variables.
public struct GameSettings: Codable, Equatable, Sendable {
    public enum Overlay: String, Codable, CaseIterable, Sendable {
        case off, topLeft, topRight, bottomLeft, bottomRight

        var position: String? {
            switch self {
            case .off: return nil
            case .topLeft: return "tl"
            case .topRight: return "tr"
            case .bottomLeft: return "bl"
            case .bottomRight: return "br"
            }
        }
    }

    /// How the performance overlay looks: one line of figures, or the panel with its graph.
    public enum OverlayStyle: String, Codable, CaseIterable, Sendable {
        case minimal, detailed
    }

    /// A WIDTHxHEIGHT the title's patches can set, nil for the title's default.
    public var resolution: String?
    public var fullscreen = false
    /// The share of the display the window takes, in percent.
    public var windowSize = 75
    public var vsync = true
    public var overlay = Overlay.off
    /// nil is minimal; optional so settings saved before it existed still decode.
    public var overlayStyle: OverlayStyle?
    public var style: OverlayStyle { overlayStyle ?? .minimal }
    /// The console language number (ANYPS5_LANGUAGE), nil to follow the launcher's language.
    public var language: Int?
    /// Keys moved from the launcher's layout (Controls), by pad action. Optional so settings saved
    /// before it existed still decode.
    public var controls: [String: [String]]?
    /// Stick, mouse and keyboard stick settings, nil for the engine's defaults.
    public var tuning: InputTuning?
    /// False turns off the shader and pipeline caches (ANYPS5_NO_SHADER_CACHE).
    public var shaderCache: Bool?
    /// The phone's pad layout for this game, as the phone sent it (its JSON); nil for the default.
    public var phoneLayout: String?

    public init() {}

    /// The environment a game starts with; `inputFile` is the anyps5-input.ini written for it,
    /// `screenshots` and `fonts` the launcher's folders for F12 screenshots and system fonts.
    public func environment(launcherLanguage: Int, inputFile: URL? = nil, screenshots: URL? = nil, fonts: URL? = nil) -> [String: String] {
        var environment: [String: String] = [
            "ANYPS5_FULLSCREEN": fullscreen ? "1" : "0",
            "ANYPS5_WINDOW_SIZE": String(min(100, max(30, windowSize))),
            "ANYPS5_PRESENT_MODE": vsync ? "fifo" : "immediate",
            "ANYPS5_LANGUAGE": String(language ?? launcherLanguage),
        ]
        if let position = overlay.position {
            environment["ANYPS5_OVERLAY"] = "1"
            environment["ANYPS5_OVERLAY_POS"] = position
            environment["ANYPS5_OVERLAY_STYLE"] = style.rawValue
        }
        if let resolution { environment["APS5_RESOLUTION"] = resolution }
        if let inputFile { environment["ANYPS5_INPUT_CONFIG"] = inputFile.path }
        if let screenshots { environment["ANYPS5_SCREENSHOTS"] = screenshots.path }
        if let fonts { environment["ANYPS5_SYSTEM_FONTS"] = fonts.path }
        if shaderCache == false { environment["ANYPS5_NO_SHADER_CACHE"] = "1" }
        return environment
    }

    /// Writes the game's keyboard and mouse layout to `file` for ANYPS5_INPUT_CONFIG.
    public func writeInputFile(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Controls.file(controls ?? [:], tuning: tuning ?? InputTuning()).utf8).write(to: file, options: .atomic)
    }
}

/// Console language numbers (sceSystemServiceParamGetInt) a game can be started with.
public enum ConsoleLanguage {
    public static let all: [(number: Int, name: String)] = [
        (19, "Türkçe"), (1, "English (US)"), (18, "English (UK)"), (4, "Deutsch"), (2, "Français"),
        (3, "Español"), (20, "Español (Latinoamérica)"), (5, "Italiano"), (17, "Português (Brasil)"),
        (7, "Português"), (8, "Русский"), (16, "Polski"), (6, "Nederlands"), (0, "日本語"), (9, "한국어"),
        (11, "简体中文"), (10, "繁體中文"), (21, "العربية"),
    ]

    /// The locale tag of a console language number, as the engine's trophy library maps them.
    public static func tag(_ number: Int) -> String? {
        let tags = ["ja-JP", "en-US", "fr-FR", "es-ES", "de-DE", "it-IT", "nl-NL", "pt-PT", "ru-RU", "ko-KR", "zh-Hant",
                    "zh-Hans", "fi-FI", "sv-SE", "da-DK", "no-NO", "pl-PL", "pt-BR", "en-GB", "tr-TR", "es-419", "ar-AE"]
        return tags.indices.contains(number) ? tags[number] : nil
    }
}
