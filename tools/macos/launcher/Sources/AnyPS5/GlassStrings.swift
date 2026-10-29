import Foundation

/// The Glass theme's see-through window: its settings' texts, from the language files (l10n).
enum TG {
    enum Key: String, CaseIterable {
        case transparency = "glassTransparency", transparencyDetail = "glassTransparencyDetail", transparencyReduced = "glassTransparencyReduced"
        case artworkBehind = "glassArtwork", artworkBehindDetail = "glassArtworkBehindDetail", desktop = "glassDesktop"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }
}
