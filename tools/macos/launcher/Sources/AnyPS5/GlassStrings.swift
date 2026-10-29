import Foundation

/// The Glass theme's see-through window: its settings' texts, in both languages.
enum TG {
    enum Key: String, CaseIterable {
        case transparency = "glassTransparency", transparencyDetail = "glassTransparencyDetail", transparencyReduced = "glassTransparencyReduced"
        case artworkBehind = "glassArtwork", artworkBehindDetail = "glassArtworkBehindDetail", desktop = "glassDesktop"
    }

    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static let english: [Key: String] = [
        .transparency: "Glass Transparency",
        .transparencyDetail: "How much of your desktop and the windows behind shows through, blurred; text stays readable at every step, 0 % is solid",
        .transparencyReduced: "Reduce Transparency is on in System Settings → Accessibility → Display, so Glass is solid",
        .artworkBehind: "Show Game Art Behind",
        .artworkBehindDetail: "Lays the selected game's key art over the desktop, frosted",
        .desktop: "Your desktop, see-through",
    ]

    static let turkish: [Key: String] = [
        .transparency: "Cam Saydamlığı",
        .transparencyDetail: "Masaüstünün ve arkadaki pencerelerin ne kadarı bulanık görünsün; yazılar her adımda okunur, %0 tam opak",
        .transparencyReduced: "Sistem Ayarları → Erişilebilirlik → Ekran'da Saydamlığı Azalt açık, bu yüzden Cam opak",
        .artworkBehind: "Oyun Görselini Arkada Göster",
        .artworkBehindDetail: "Seçili oyunun görselini masaüstünün üstüne buzlu olarak serer",
        .desktop: "Masaüstün, saydam",
    ]
}
