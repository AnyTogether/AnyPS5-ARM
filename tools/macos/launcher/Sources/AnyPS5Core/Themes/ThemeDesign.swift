import Foundation

/// A look someone made for the launcher (and the phone): one of the animated backgrounds in
/// their own colors, an accent, and maybe a picture or video behind it all and menu music.
/// Shared as one `.anyps5theme` file, a zip of theme.json and the files it names.
public struct ThemeDesign: Codable, Equatable, Hashable, Identifiable, Sendable {
    public static let fileExtension = "anyps5theme"

    public var id: String
    public var name: String
    public var author: String
    public var version: Int
    /// The animated background: 0 cosmic, 1 aurora, 2 sunset.
    public var style: Int
    /// Deep, middle and bright tones of the background, and the accent, as #RRGGBB.
    public var deep: String
    public var middle: String
    public var bright: String
    public var accent: String
    /// File names inside the theme's folder.
    public var background: String?
    public var music: String?

    public init(id: String = UUID().uuidString.lowercased(), name: String, author: String, version: Int = 1, style: Int, deep: String, middle: String, bright: String, accent: String,
                background: String? = nil, music: String? = nil) {
        self.id = id
        self.name = name
        self.author = author
        self.version = version
        self.style = style
        self.deep = deep
        self.middle = middle
        self.bright = bright
        self.accent = accent
        self.background = background
        self.music = music
    }

    public var palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (Self.rgb(deep) ?? SIMD3(0.012, 0.024, 0.09), Self.rgb(middle) ?? SIMD3(0.04, 0.15, 0.42), Self.rgb(bright) ?? SIMD3(0.42, 0.64, 1))
    }

    public var accentRGB: SIMD3<Float> { Self.rgb(accent) ?? SIMD3(0.31, 0.58, 1) }

    /// Whether the background file is a video, by its name.
    public var backgroundIsVideo: Bool {
        guard let background else { return false }
        return ["mp4", "mov", "m4v"].contains((background as NSString).pathExtension.lowercased())
    }

    public static func rgb(_ hex: String) -> SIMD3<Float>? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return SIMD3(Float((value >> 16) & 0xFF) / 255, Float((value >> 8) & 0xFF) / 255, Float(value & 0xFF) / 255)
    }

    public static func hex(_ color: SIMD3<Float>) -> String {
        func byte(_ value: Float) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.x), byte(color.y), byte(color.z))
    }

    /// A color from hue (0-360), saturation and brightness (0-1).
    public static func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> SIMD3<Float> {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return SIMD3(Float(r + m), Float(g + m), Float(b + m))
    }
}
