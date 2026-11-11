import AnyPS5Core
import SwiftUI

/// The sign of an Android device: a robot's head (half a disc, two antennae, two eyes), drawn
/// here, since SF Symbols has none and no logo file is shipped. Filled with the even-odd rule,
/// which leaves the eyes open.
struct AndroidGlyph: Shape {
    /// The name a row's `symbol` carries for this sign, where the others are SF Symbols.
    static let symbol = "anyps5.android"

    func path(in rect: CGRect) -> Path {
        // The head's flat edge sits on the rect's bottom, the antennae reach its top.
        let radius: CGFloat = min(rect.width / 2, rect.height / 1.36)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.closeSubpath()
        let sides: [CGFloat] = [-1, 1]
        for side in sides {
            let eye: CGFloat = radius * 0.11
            let eyeX: CGFloat = center.x + side * radius * 0.42
            let eyeY: CGFloat = center.y - radius * 0.44
            path.addEllipse(in: CGRect(x: eyeX - eye, y: eyeY - eye, width: eye * 2, height: eye * 2))
            // An antenna: a thin bar leaning outwards from just above the head.
            let alongX: CGFloat = side * 0.5
            let alongY: CGFloat = -0.866
            let half: CGFloat = radius * 0.055
            let across = CGPoint(x: 0.866 * half, y: side * 0.5 * half)
            let near = CGPoint(x: center.x + alongX * radius * 1.03, y: center.y + alongY * radius * 1.03)
            let far = CGPoint(x: center.x + alongX * radius * 1.36, y: center.y + alongY * radius * 1.36)
            path.move(to: CGPoint(x: near.x - across.x, y: near.y - across.y))
            path.addLine(to: CGPoint(x: far.x - across.x, y: far.y - across.y))
            path.addLine(to: CGPoint(x: far.x + across.x, y: far.y + across.y))
            path.addLine(to: CGPoint(x: near.x + across.x, y: near.y + across.y))
            path.closeSubpath()
        }
        return path
    }
}

extension AppModel {
    /// A paired device's name as people read it: a browser pad's "Android · Web" is "Android
    /// browser" in the launcher's language, the phone app's own name stays as it is.
    static func phoneTitle(_ name: String) -> String {
        let label = PhoneLabel(name)
        guard label.isBrowser else { return name }
        return label.browserDevice.map { T.format(.phoneBrowserName, $0) } ?? T.text(.phoneBrowserGeneric)
    }

    /// The sign before a paired device's name: SF Symbols for an iPhone, an iPad, a browser and a
    /// phone that says nothing about itself, the robot's head (AndroidGlyph) for Android.
    static func phoneSymbol(_ name: String) -> String {
        switch PhoneLabel(name).kind {
        case .android: return AndroidGlyph.symbol
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .browser: return "globe"
        case .phone: return "smartphone"
        }
    }
}
