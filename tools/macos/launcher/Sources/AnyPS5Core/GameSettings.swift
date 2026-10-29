import Foundation

/// Settings › Default Display: how a game starts that made no display choice of its own (Game
/// Settings › Display, Window Size and Vertical Sync left at Default). The built-in values are the
/// ones every game started with before there were defaults. The same as AnyPS5 Desktop's.
public struct DisplayDefaults: Codable, Equatable, Sendable {
    public var fullscreen: Bool
    /// The share of the display the window takes, in percent.
    public var windowSize: Int
    public var vsync: Bool

    public static let minimumWindowSize = 30

    public init(fullscreen: Bool = false, windowSize: Int = 75, vsync: Bool = true) {
        self.fullscreen = fullscreen
        self.windowSize = windowSize
        self.vsync = vsync
    }

    public var isBuiltIn: Bool { self == DisplayDefaults() }

    /// A value missing or of the wrong kind is the built-in one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let builtIn = DisplayDefaults()
        fullscreen = (try? container.decodeIfPresent(Bool.self, forKey: .fullscreen)) ?? builtIn.fullscreen
        windowSize = ((try? container.decodeIfPresent(Int.self, forKey: .windowSize)) ?? nil).map { min(100, max(Self.minimumWindowSize, $0)) } ?? builtIn.windowSize
        vsync = (try? container.decodeIfPresent(Bool.self, forKey: .vsync)) ?? builtIn.vsync
    }
}

/// The per-game choices the launcher passes to a started game as environment variables. Stored
/// as JSON with the same keys as AnyPS5 Desktop's, so a settings file reads the same everywhere.
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

    /// Written in every file since display choices can follow DisplayDefaults: there the display
    /// keys are present only for a game's own choices. A file without it (an older launcher's)
    /// always had them all; see init(from:).
    public static let version = 2

    /// A WIDTHxHEIGHT the title's patches can set, nil for the title's default.
    public var resolution: String?
    /// The game's own display choices; nil follows Settings › Default Display (withDefaults).
    public var ownFullscreen: Bool?
    /// The share of the display the window takes, in percent.
    public var ownWindowSize: Int?
    public var ownVsync: Bool?

    /// The display as the game starts: its own choice, else the built-in default. A game is
    /// started with withDefaults applied, so these are the user's defaults there. Setting one
    /// makes it the game's own choice.
    public var fullscreen: Bool {
        get { ownFullscreen ?? DisplayDefaults().fullscreen }
        set { ownFullscreen = newValue }
    }
    public var windowSize: Int {
        get { ownWindowSize ?? DisplayDefaults().windowSize }
        set { ownWindowSize = newValue }
    }
    public var vsync: Bool {
        get { ownVsync ?? DisplayDefaults().vsync }
        set { ownVsync = newValue }
    }

    /// Whether the game made no display choice of its own.
    public var followsDisplayDefaults: Bool { ownFullscreen == nil && ownWindowSize == nil && ownVsync == nil }

    /// These settings with `defaults` in place of the display choices the game did not make.
    public func withDefaults(_ defaults: DisplayDefaults) -> GameSettings {
        var settings = self
        settings.ownFullscreen = ownFullscreen ?? defaults.fullscreen
        settings.ownWindowSize = ownWindowSize ?? defaults.windowSize
        settings.ownVsync = ownVsync ?? defaults.vsync
        return settings
    }

    /// These settings with every display choice back to following the defaults.
    public func followingDisplayDefaults() -> GameSettings {
        var settings = self
        settings.ownFullscreen = nil
        settings.ownWindowSize = nil
        settings.ownVsync = nil
        return settings
    }
    public var overlay = Overlay.off
    /// nil is minimal; optional so settings saved before it existed still decode.
    public var overlayStyle: OverlayStyle?
    public var style: OverlayStyle { overlayStyle ?? .minimal }
    /// A generated frame between each two of the game's (ANYPS5_FRAME_GEN), with vertical sync;
    /// nil is off.
    public var frameGeneration: Bool?
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
    /// The engine toolkit that unlocks this game (EngineChoice: "builtin", "custom" or a
    /// downloaded version); nil follows the launcher's default.
    public var engine: String?
    /// Detailed logging (TraceMode) on every start; nil is off.
    public var trace: Bool?
    /// Gyro aiming (Controls → Gyro Aiming, ANYPS5_GYRO_AIM); nil is off.
    public var gyro: GyroAiming?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case settingsVersion, ownDisplay
        case resolution, ownFullscreen = "fullscreen", ownWindowSize = "windowSize", ownVsync = "vsync"
        case overlay, overlayStyle, frameGeneration, language, controls, tuning, shaderCache, phoneLayout, engine, trace, gyro
    }

    /// The JSONEncoder of the launcher's own preferences sets this: there every display key is
    /// written as before (an older launcher needs them all), with "ownDisplay" naming the game's
    /// own choices among them.
    public static let legacyDisplayKeys = CodingUserInfoKey(rawValue: "anyps5.legacyDisplayKeys")!

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        var fullscreen = try container.decodeIfPresent(Bool.self, forKey: .ownFullscreen)
        var windowSize = try container.decodeIfPresent(Int.self, forKey: .ownWindowSize)
        var vsync = try container.decodeIfPresent(Bool.self, forKey: .ownVsync)
        if let own = try container.decodeIfPresent([String].self, forKey: .ownDisplay) {
            if !own.contains(CodingKeys.ownFullscreen.stringValue) { fullscreen = nil }
            if !own.contains(CodingKeys.ownWindowSize.stringValue) { windowSize = nil }
            if !own.contains(CodingKeys.ownVsync.stringValue) { vsync = nil }
        } else if (try container.decodeIfPresent(Int.self, forKey: .settingsVersion) ?? 1) < Self.version {
            // A file from before the defaults wrote every display key, changed or not: a value
            // that is the old built-in one was most likely never chosen, so it follows the
            // defaults (which start as those same values: nothing changes until they do).
            // Windowed with a size of its own was chosen, though.
            let builtIn = DisplayDefaults()
            if windowSize == builtIn.windowSize { windowSize = nil }
            if fullscreen == builtIn.fullscreen && windowSize == nil { fullscreen = nil }
            if vsync == builtIn.vsync { vsync = nil }
        }
        ownFullscreen = fullscreen
        ownWindowSize = windowSize
        ownVsync = vsync
        overlay = try container.decodeIfPresent(Overlay.self, forKey: .overlay) ?? .off
        overlayStyle = try container.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle)
        frameGeneration = try container.decodeIfPresent(Bool.self, forKey: .frameGeneration)
        language = try container.decodeIfPresent(Int.self, forKey: .language)
        controls = try container.decodeIfPresent([String: [String]].self, forKey: .controls)
        tuning = try container.decodeIfPresent(InputTuning.self, forKey: .tuning)
        shaderCache = try container.decodeIfPresent(Bool.self, forKey: .shaderCache)
        phoneLayout = try container.decodeIfPresent(String.self, forKey: .phoneLayout)
        engine = try container.decodeIfPresent(String.self, forKey: .engine)
        trace = try container.decodeIfPresent(Bool.self, forKey: .trace)
        gyro = try container.decodeIfPresent(GyroAiming.self, forKey: .gyro)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .settingsVersion)
        if encoder.userInfo[Self.legacyDisplayKeys] as? Bool == true {
            try container.encode(fullscreen, forKey: .ownFullscreen)
            try container.encode(windowSize, forKey: .ownWindowSize)
            try container.encode(vsync, forKey: .ownVsync)
            let own: [(Any?, CodingKeys)] = [(ownFullscreen, .ownFullscreen), (ownWindowSize, .ownWindowSize), (ownVsync, .ownVsync)]
            try container.encode(own.filter { $0.0 != nil }.map(\.1.stringValue), forKey: .ownDisplay)
        } else {
            try container.encodeIfPresent(ownFullscreen, forKey: .ownFullscreen)
            try container.encodeIfPresent(ownWindowSize, forKey: .ownWindowSize)
            try container.encodeIfPresent(ownVsync, forKey: .ownVsync)
        }
        try container.encodeIfPresent(resolution, forKey: .resolution)
        try container.encode(overlay, forKey: .overlay)
        try container.encodeIfPresent(overlayStyle, forKey: .overlayStyle)
        try container.encodeIfPresent(frameGeneration, forKey: .frameGeneration)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(controls, forKey: .controls)
        try container.encodeIfPresent(tuning, forKey: .tuning)
        try container.encodeIfPresent(shaderCache, forKey: .shaderCache)
        try container.encodeIfPresent(phoneLayout, forKey: .phoneLayout)
        try container.encodeIfPresent(engine, forKey: .engine)
        try container.encodeIfPresent(trace, forKey: .trace)
        try container.encodeIfPresent(gyro, forKey: .gyro)
    }

    /// The game reads the controllers (through SDL2) only while its window is in front: with the
    /// launcher brought over it with PS, the pad drives the launcher alone. The engine asks SDL for
    /// background events with a plain SDL_SetHint, which the same name in the environment overrides
    /// (an SDL hint from the environment wins over every priority but OVERRIDE).
    public static let backgroundPadEnvironment = ["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "0"]

    /// The environment a game starts with; `inputFile` is the anyps5-input.ini written for it,
    /// `screenshots` and `fonts` the launcher's folders for F12 screenshots and system fonts;
    /// `trace` turns detailed logging on for this start even when the setting is off.
    public func environment(launcherLanguage: Int, inputFile: URL? = nil, screenshots: URL? = nil, fonts: URL? = nil, trace: Bool = false) -> [String: String] {
        var environment: [String: String] = [
            "ANYPS5_FULLSCREEN": fullscreen ? "1" : "0",
            "ANYPS5_WINDOW_SIZE": String(min(100, max(DisplayDefaults.minimumWindowSize, windowSize))),
            "ANYPS5_PRESENT_MODE": vsync || frameGeneration == true ? "fifo" : "immediate",
            "ANYPS5_LANGUAGE": String(language ?? launcherLanguage),
        ]
        environment.merge(Self.backgroundPadEnvironment) { own, _ in own }
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
        if frameGeneration == true { environment["ANYPS5_FRAME_GEN"] = "1" }
        if let aim = gyro?.environment { environment["ANYPS5_GYRO_AIM"] = aim }
        if trace || self.trace == true { environment.merge(TraceMode.environment) { own, _ in own } }
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
