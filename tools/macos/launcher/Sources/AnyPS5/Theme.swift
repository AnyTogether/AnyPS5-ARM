import SwiftUI

/// The three built-in looks. Each is an animated background (see BackgroundRenderer) with the
/// colors the interface draws over it.
enum Theme: Int, Codable, CaseIterable, Identifiable {
    case cosmic
    case aurora
    case sunset

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cosmic: return T.text(.themeCosmic)
        case .aurora: return T.text(.themeAurora)
        case .sunset: return T.text(.themeSunset)
        }
    }

    /// Deep, middle and bright tones the shader blends; also the fallback when Metal is missing.
    var palette: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .cosmic: return (SIMD3(0.012, 0.024, 0.090), SIMD3(0.040, 0.150, 0.420), SIMD3(0.420, 0.640, 1.000))
        case .aurora: return (SIMD3(0.006, 0.030, 0.045), SIMD3(0.020, 0.300, 0.300), SIMD3(0.560, 1.000, 0.780))
        case .sunset: return (SIMD3(0.060, 0.010, 0.040), SIMD3(0.520, 0.110, 0.220), SIMD3(1.000, 0.640, 0.330))
        }
    }

    var defaultAccent: AccentColor {
        switch self {
        case .cosmic: return .blue
        case .aurora: return .mint
        case .sunset: return .coral
        }
    }

    var gradient: LinearGradient {
        let (deep, middle, _) = palette
        return LinearGradient(colors: [Color(rgb: middle), Color(rgb: deep)], startPoint: .top, endPoint: .bottom)
    }
}

enum AccentColor: String, Codable, CaseIterable, Identifiable {
    case blue, mint, coral, violet, gold, white

    var id: String { rawValue }

    var title: String {
        let turkish = T.language == .turkish
        switch self {
        case .blue: return turkish ? "Mavi" : "Blue"
        case .mint: return turkish ? "Nane" : "Mint"
        case .coral: return turkish ? "Mercan" : "Coral"
        case .violet: return turkish ? "Mor" : "Violet"
        case .gold: return turkish ? "Altın" : "Gold"
        case .white: return turkish ? "Beyaz" : "White"
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
