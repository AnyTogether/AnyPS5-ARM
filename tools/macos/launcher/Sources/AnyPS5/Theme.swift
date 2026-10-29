import AnyPS5Core
import SwiftUI

/// The built-in looks (LookStyle in the core, where their numbers and colors are tested). Each is
/// an animated background (see BackgroundRenderer) with the colors the interface draws over it.
typealias Theme = LookStyle

extension LookStyle {
    var title: String {
        switch self {
        case .cosmic: return T.text(.themeCosmic)
        case .aurora: return T.text(.themeAurora)
        case .sunset: return T.text(.themeSunset)
        case .glass: return T.text(.themeGlass)
        }
    }

    var defaultAccent: AccentColor {
        switch self {
        case .cosmic: return .blue
        case .aurora: return .mint
        case .sunset: return .coral
        case .glass: return .ice
        }
    }

    var gradient: LinearGradient {
        let (deep, middle, _) = palette
        return LinearGradient(colors: [Color(rgb: middle), Color(rgb: deep)], startPoint: .top, endPoint: .bottom)
    }
}

enum AccentColor: String, Codable, CaseIterable, Identifiable {
    case blue, mint, coral, violet, gold, white, ice

    var id: String { rawValue }

    /// An accent a newer launcher saved and this one does not know is Blue, not settings lost.
    init(from decoder: Decoder) throws {
        self = AccentColor(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .blue
    }

    var title: String {
        switch self {
        case .blue: return T.text(.accentBlue)
        case .mint: return T.text(.accentMint)
        case .coral: return T.text(.accentCoral)
        case .violet: return T.text(.accentViolet)
        case .gold: return T.text(.accentGold)
        case .white: return T.text(.accentWhite)
        case .ice: return T.text(.accentIce)
        }
    }

    var color: Color {
        switch self {
        case .blue: return Color(red: 0.31, green: 0.58, blue: 1.0)
        case .mint: return Color(red: 0.36, green: 0.92, blue: 0.74)
        case .coral: return Color(red: 1.0, green: 0.50, blue: 0.40)
        case .violet: return Color(red: 0.66, green: 0.52, blue: 1.0)
        case .gold: return Color(red: 1.0, green: 0.80, blue: 0.36)
        case .white: return Color(white: 0.94)
        case .ice: return Color(red: 0.54, green: 0.85, blue: 1.0)
        }
    }
}

extension Color {
    init(rgb: SIMD3<Float>) {
        self.init(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

/// Springs used across the interface: quick to respond, no wobble on small moves.
enum Motion {
    static var reduced = false

    static var focus: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.82) }
    static var layout: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86) }
    static var fade: Animation { .easeInOut(duration: reduced ? 0.15 : 0.55) }
    static var overlay: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9) }
}
