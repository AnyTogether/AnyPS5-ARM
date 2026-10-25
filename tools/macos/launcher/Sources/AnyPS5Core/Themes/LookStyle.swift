import Foundation

/// The built-in looks, each an animated background with the colors the interface draws over it.
/// Saved by number (preferences, theme files), so a new look only ever goes at the end.
public enum LookStyle: Int, CaseIterable, Identifiable, Sendable, Codable {
    case cosmic
    case aurora
    case sunset
    /// Frosted ice: the background and the game's key art seen through layers of glass.
    case glass

    public var id: Int { rawValue }

    /// A number from a theme file or an older or newer launcher's preferences: one this launcher
    /// does not know is Cosmic, never a failure that loses the rest of the settings.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = LookStyle(rawValue: raw) ?? .cosmic
    }

    public static func style(_ raw: Int) -> LookStyle { LookStyle(rawValue: raw) ?? .cosmic }

    /// Deep, middle and bright tones the background blends.
    public var palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .cosmic: return (SIMD3(0.012, 0.024, 0.090), SIMD3(0.040, 0.150, 0.420), SIMD3(0.420, 0.640, 1.000))
        case .aurora: return (SIMD3(0.006, 0.030, 0.045), SIMD3(0.020, 0.300, 0.300), SIMD3(0.560, 1.000, 0.780))
        case .sunset: return (SIMD3(0.060, 0.010, 0.040), SIMD3(0.520, 0.110, 0.220), SIMD3(1.000, 0.640, 0.330))
        case .glass: return (SIMD3(0.016, 0.063, 0.110), SIMD3(0.110, 0.310, 0.450), SIMD3(0.812, 0.937, 1.000))
        }
    }

    /// Surfaces are layered glass rather than dark panels.
    public var isGlass: Bool { self == .glass }
}

/// How the Glass look draws its surfaces here and now.
public enum GlassRendering: Equatable, Sendable {
    /// macOS 26's Liquid Glass: real refraction of what is behind, in a live window.
    case liquid
    /// Drawn frost: a blurring material where there is a window, translucent layers with a lit
    /// rim offscreen and on older macOS.
    case frosted
    /// Reduce Transparency: opaque surfaces with the same rim.
    case solid

    public static func choose(reduceTransparency: Bool, liquidAvailable: Bool, offscreen: Bool) -> GlassRendering {
        if reduceTransparency { return .solid }
        // Liquid Glass draws nothing at all in an offscreen render, not even what it holds.
        if offscreen || !liquidAvailable { return .frosted }
        return .liquid
    }
}

/// The Glass look's layers as numbers, and the WCAG contrast arithmetic that keeps text on them
/// readable over any key art.
public enum GlassRecipe {
    public typealias RGB = SIMD3<Double>

    /// Navy laid over the frosted key art everywhere; the gradients that darken behind the text
    /// only add to it.
    public static let scrim = RGB(0.016, 0.063, 0.110)
    public static let scrimOpacity = 0.42
    /// A surface's own dark base, under its white sheen.
    public static let surfaceBase = RGB(0.024, 0.071, 0.125)
    public static let surfaceOpacity = 0.48
    /// The sheen's strongest white, at the lit corner.
    public static let sheenOpacity = 0.09
    /// The card over a game (trophy, notice, call): any game frame may be behind it.
    public static let bannerOpacity = 0.72
    /// A full-screen panel's frost (settings, library, profile).
    public static let screenOpacity = 0.62
    /// The focused element: a bright frosted chip with dark ink.
    public static let chipLow = 0.80
    public static let ink = RGB(0.027, 0.078, 0.133)
    /// Reduce Transparency's opaque surface.
    public static let solid = RGB(0.039, 0.102, 0.165)

    /// `top` at `opacity` over `bottom`, blended as the screen does, in sRGB.
    public static func over(_ top: RGB, _ opacity: Double, _ bottom: RGB) -> RGB {
        top * opacity + bottom * (1 - opacity)
    }

    /// WCAG 2 relative luminance of an sRGB color.
    public static func luminance(_ color: RGB) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// A surface over a backdrop pixel: the scrim, the surface's base, then its sheen.
    public static func surface(over backdrop: RGB) -> RGB {
        let scrimmed = over(scrim, scrimOpacity, backdrop)
        return over(RGB(1, 1, 1), sheenOpacity, over(surfaceBase, surfaceOpacity, scrimmed))
    }

    /// A surface on the see-through window: its base raised to a plate's, then its sheen.
    public static func plateSurface(over backdrop: RGB) -> RGB {
        over(RGB(1, 1, 1), sheenOpacity, over(surfaceBase, GlassWindowRecipe.plateOpacity, backdrop))
    }

    /// The focused chip at its darkest point, over a backdrop pixel.
    public static func chip(over backdrop: RGB) -> RGB { over(RGB(1, 1, 1), chipLow, backdrop) }

    /// Ink that reads on a fill: dark on light colors (the Ice accent, the White one), else white.
    public static func prefersDarkInk(on fill: RGB) -> Bool {
        contrast(ink, fill) > contrast(RGB(1, 1, 1), fill)
    }
}

/// The Glass look's window: see-through to the desktop and the windows behind it, blurred by the
/// system under a light navy tint, so the wallpaper's colors glow through. The text is not kept
/// readable by darkening the whole window but where it sits: on plates (a soft dark plate behind
/// bare text, the cards' and buttons' own glass), each dark enough on its own.
public struct GlassWindowRecipe: Equatable, Sendable {
    /// Whether the window lets what is behind it through (else it is opaque, as in other themes).
    public var translucent: Bool
    /// The navy tint's opacity over the blurred desktop (1 when opaque).
    public var tint: Double

    public static let opaque = GlassWindowRecipe(translucent: false, tint: 1)

    /// Settings → Appearance → Glass Transparency when the user has not moved it, in percent.
    public static let defaultTransparency = 90

    /// The tint at 100 %: a breath of navy, so the glass still reads as Glass's blue.
    public static let minimumTint = 0.04

    /// The least a plate under text lays over the desktop: white text keeps WCAG AA (4.5:1) and
    /// text at 70 % white keeps 3:1 over a pure white desktop (a white window behind, a snowy
    /// wallpaper), counting nothing for the window's tint or the blur's darkening. Brighter
    /// backdrops do not exist, so no sampling of the screen behind the window is needed (which
    /// would ask for Screen Recording).
    public static let plateFloor: Double = {
        let white = GlassRecipe.RGB(1, 1, 1)
        func reads(_ plate: Double) -> Bool {
            let behind = GlassRecipe.over(GlassRecipe.scrim, plate, white)
            return GlassRecipe.contrast(white, behind) >= 4.5
                && GlassRecipe.contrast(GlassRecipe.over(white, 0.7, behind), behind) >= 3
        }
        var plate = 0.0
        while !reads(plate) { plate += 0.01 }
        return (plate * 100).rounded() / 100
    }()

    /// The plates' core as drawn: over the floor, for the soft edge of a blurred plate.
    public static let plateOpacity = 0.62

    /// The tint for a transparency in percent: 100 is the minimum, 0 a solid pane.
    public static func tint(transparency: Int) -> Double {
        let fraction = Double(min(100, max(0, transparency))) / 100
        return minimumTint + (1 - minimumTint) * (1 - fraction)
    }

    /// Glass lets the desktop through unless Reduce Transparency is on or the slider is at 0 %;
    /// every other look keeps its opaque window.
    public static func make(glass: Bool, reduceTransparency: Bool, transparency: Int?) -> GlassWindowRecipe {
        let transparency = transparency ?? defaultTransparency
        guard glass, !reduceTransparency, transparency > 0 else { return .opaque }
        return GlassWindowRecipe(translucent: true, tint: tint(transparency: transparency))
    }

    /// Whether the launcher may read the desktop picture (for full screen, where no desktop is
    /// behind the window) without macOS asking the user: pictures in Desktop, Documents,
    /// Downloads, iCloud Drive or on other volumes need a permission, the system's do not.
    public static func mayReadWallpaper(_ url: URL, home: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.standardizedFileURL.path
        let home = home.standardizedFileURL.path
        if path.hasPrefix("/Volumes/") { return false }
        let protected = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage", "Library/Containers"]
        return !protected.contains { path == home + "/" + $0 || path.hasPrefix(home + "/" + $0 + "/") }
    }
}
