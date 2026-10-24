import Foundation

/// The Theme Studio's knobs: the background's hue, how far its highlight turns from it, how
/// light it is, and the accent's hue. They make the four colors, and are read back from any
/// theme's colors, so an installed theme can be changed with them too.
public struct ThemeKnobs: Equatable, Sendable {
    /// Degrees, 0 to 355.
    public var hue: Double
    /// Degrees the bright tone turns from the hue, -90 to 90.
    public var highlight: Double
    /// 1 (dark) to 10 (light).
    public var depth: Int
    public var accentHue: Double

    public init(hue: Double, highlight: Double, depth: Int, accentHue: Double) {
        self.hue = hue
        self.highlight = highlight
        self.depth = depth
        self.accentHue = accentHue
    }

    public init(_ design: ThemeDesign) {
        let palette = design.palette
        let middle = Self.hsb(palette.1), bright = Self.hsb(palette.2), accent = Self.hsb(design.accentRGB)
        hue = middle.hue.rounded()
        var turn = bright.hue - middle.hue
        if turn > 180 { turn -= 360 }
        if turn < -180 { turn += 360 }
        highlight = min(90, max(-90, turn.rounded()))
        depth = min(10, max(1, Int(((middle.brightness - 0.15) / 0.05).rounded())))
        accentHue = accent.hue.rounded()
    }

    public func apply(to design: inout ThemeDesign) {
        let level = Double(min(10, max(1, depth)))
        design.deep = ThemeDesign.hex(ThemeDesign.hsb(hue, 0.85, 0.05 + level * 0.008))
        design.middle = ThemeDesign.hex(ThemeDesign.hsb(hue, 0.80, 0.15 + level * 0.05))
        design.bright = ThemeDesign.hex(ThemeDesign.hsb(hue + highlight, 0.55, 1))
        design.accent = ThemeDesign.hex(ThemeDesign.hsb(accentHue, 0.68, 1))
    }

    static func hsb(_ color: SIMD3<Float>) -> (hue: Double, saturation: Double, brightness: Double) {
        let r = Double(color.x), g = Double(color.y), b = Double(color.z)
        let high = max(r, g, b), low = min(r, g, b), range = high - low
        var hue = 0.0
        if range > 0 {
            if high == r { hue = 60 * ((g - b) / range).truncatingRemainder(dividingBy: 6) }
            else if high == g { hue = 60 * ((b - r) / range + 2) }
            else { hue = 60 * ((r - g) / range + 4) }
        }
        if hue < 0 { hue += 360 }
        return (hue, high == 0 ? 0 : range / high, high)
    }
}
