import AnyPS5Core
import AppKit
import SwiftUI

/// The pictures AnyPS5's Steam shortcuts wear, drawn offscreen in the Cosmic look: the deep blue
/// field with its glow, the dust and the waves of the app icon, the ring and play mark, the name.
/// A game's own come from its sce_sys art (pic0 as the backdrop, icon0 as the cover) with the
/// same finish. The Windows and Linux launcher draws the same pictures (lib/ui/steam_art.dart).
@MainActor
enum SteamArtist {
    static let deep = Color(red: 0.012, green: 0.024, blue: 0.090)
    static let middle = Color(red: 0.040, green: 0.150, blue: 0.420)
    static let bright = Color(red: 0.420, green: 0.640, blue: 1.000)
    static let white = Color(red: 0.957, green: 0.965, blue: 0.984)

    /// AnyPS5's own five pictures.
    static func launcher(accent: Color) -> [SteamArt: Data] {
        var art: [SteamArt: Data] = [:]
        art[.portrait] = png(.portrait) {
            ZStack {
                CosmicField(accent: accent, seed: 1)
                VStack(spacing: 0) {
                    Spacer().frame(height: 240)
                    PlayMark(radius: 132)
                    Spacer().frame(height: 60)
                    Wordmark(text: "AnyPS5", size: 88)
                    Caption(text: "PS5 GAMES · NATIVELY").padding(.top, 26)
                    Spacer()
                }
            }
        }
        art[.wide] = png(.wide) {
            ZStack {
                CosmicField(accent: accent, seed: 2)
                HStack(spacing: 0) {
                    PlayMark(radius: 112).frame(width: 500)
                    VStack(alignment: .center, spacing: 18) {
                        Wordmark(text: "AnyPS5", size: 104)
                        Caption(text: "PS5 GAMES · NATIVELY")
                    }
                    .frame(width: 420)
                    Spacer(minLength: 0)
                }
            }
        }
        art[.hero] = png(.hero) {
            ZStack {
                CosmicField(accent: accent, seed: 3)
                Circle().stroke(white.opacity(0.07), lineWidth: 46).frame(width: 720, height: 720).position(x: 1530, y: 330)
                Circle().stroke(accent.opacity(0.10), lineWidth: 46).frame(width: 500, height: 500).position(x: 1530, y: 330)
            }
        }
        art[.logo] = png(.logo, opaque: false) {
            HStack(spacing: 40) {
                PlayMark(radius: 140, glow: false)
                Wordmark(text: "AnyPS5", size: 200)
            }
        }
        art[.icon] = png(.icon, opaque: false) {
            ZStack {
                CosmicField(accent: accent, seed: 4, stars: 18)
                PlayMark(radius: 76, glow: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
        }
        return art
    }

    /// A game's five pictures from its sce_sys art (either may be missing).
    static func game(name: String, background: URL?, cover: URL?, accent: Color) -> [SteamArt: Data] {
        let backdrop = background.flatMap { NSImage(contentsOf: $0) }
        let icon = cover.flatMap { NSImage(contentsOf: $0) }
        @ViewBuilder func base(blur: CGFloat = 0, seed: UInt64) -> some View {
            if let backdrop {
                Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).blur(radius: blur, opaque: true)
            } else {
                CosmicField(accent: accent, seed: seed)
            }
        }
        @ViewBuilder func coverView(_ side: CGFloat, radius: CGFloat) -> some View {
            if let icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(white.opacity(0.18), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 22, y: 10)
            } else {
                PlayMark(radius: side * 0.33).frame(width: side, height: side)
            }
        }
        var art: [SteamArt: Data] = [:]
        art[.portrait] = png(.portrait) {
            ZStack {
                base(blur: 22, seed: 5).frame(width: 600, height: 900).clipped()
                LinearGradient(colors: [deep.opacity(0.35), deep.opacity(0.55), deep.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Spacer().frame(height: 110)
                    coverView(460, radius: 36)
                    Spacer().frame(height: 50)
                    Wordmark(text: name, size: 46, lines: 3).frame(width: 520, height: 160)
                    Spacer()
                    Badge().padding(.bottom, 34)
                }
            }
        }
        art[.wide] = png(.wide) {
            ZStack(alignment: .leading) {
                base(seed: 5).frame(width: 920, height: 430).clipped()
                LinearGradient(stops: [.init(color: deep.opacity(0.88), location: 0), .init(color: deep.opacity(0.55), location: 0.55), .init(color: deep.opacity(0.05), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                HStack(spacing: 0) {
                    coverView(300, radius: 26).padding(.leading, 44)
                    VStack(spacing: 28) {
                        Wordmark(text: name, size: 44, lines: 3)
                        Badge()
                    }
                    .frame(width: 500)
                    Spacer(minLength: 0)
                }
            }
        }
        art[.hero] = png(.hero) {
            ZStack {
                if backdrop != nil {
                    base(seed: 6).frame(width: 1920, height: 620).clipped()
                } else {
                    CosmicField(accent: accent, seed: 6)
                    if let icon { Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill).blur(radius: 40, opaque: true).frame(width: 1920, height: 620).clipped() }
                }
            }
        }
        art[.logo] = png(.logo, opaque: false) {
            Wordmark(text: name, size: 132, lines: 2).frame(width: 1280)
        }
        art[.icon] = png(.icon) {
            if let icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill).frame(width: 256, height: 256).clipped()
            } else {
                ZStack {
                    CosmicField(accent: accent, seed: 7, stars: 18)
                    PlayMark(radius: 76, glow: false)
                }
            }
        }
        return art
    }

    /// Renders `content` at the picture's size, one point to a pixel, as PNG.
    static func png<Content: View>(_ kind: SteamArt, opaque: Bool = true, @ViewBuilder _ content: () -> Content) -> Data? {
        let size = CGSize(width: kind.size.width, height: kind.size.height)
        let view = content()
            .frame(width: size.width, height: size.height)
            .background(opaque ? deep : Color.clear)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = opaque
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// The Cosmic field: deep blue rising from the bottom, a glow up right, dust, the icon's waves.
private struct CosmicField: View {
    let accent: Color
    let seed: UInt64
    var stars = 140

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: SteamArtist.deep, location: 0), .init(color: SteamArtist.middle, location: 0.62),
                                 .init(color: Color(red: 0.18, green: 0.34, blue: 0.79), location: 1)]),
                startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: size.width, y: 0)))
            let glow = CGPoint(x: size.width * 0.78, y: size.height * 0.18)
            context.fill(Path(rect), with: .radialGradient(
                Gradient(stops: [.init(color: SteamArtist.bright.opacity(0.42), location: 0), .init(color: accent.opacity(0.10), location: 0.45),
                                 .init(color: accent.opacity(0), location: 1)]),
                center: glow, startRadius: 0, endRadius: max(size.width, size.height) * 0.6))
            var random = SplitMix(seed: seed)
            let scale = (size.width * size.height).squareRoot() / 700
            for _ in 0..<stars {
                let point = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                let light = random.unit()
                let radius = (0.5 + light * 1.3) * scale
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(SteamArtist.white.opacity(0.12 + light * light * 0.6)))
            }
            for i in 0..<5 {
                let y = size.height * (0.62 + CGFloat(i) * 0.022)
                let lift = size.height * (0.07 - CGFloat(i) * 0.012)
                var path = Path()
                path.move(to: CGPoint(x: -10, y: y + lift * 0.4))
                path.addCurve(to: CGPoint(x: size.width + 10, y: y - lift * 0.5),
                              control1: CGPoint(x: size.width * 0.3, y: y - lift), control2: CGPoint(x: size.width * 0.62, y: y + lift * 1.2))
                context.stroke(path, with: .color(SteamArtist.white.opacity(i == 1 ? 0.34 : 0.14)),
                               style: StrokeStyle(lineWidth: max(1, scale * (i == 1 ? 2.2 : 1.3)), lineCap: .round))
            }
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [.init(color: SteamArtist.deep.opacity(0), location: 0.55), .init(color: SteamArtist.deep.opacity(0.55), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}

/// The ring and play mark of the app icon.
private struct PlayMark: View {
    let radius: CGFloat
    var glow = true

    var body: some View {
        ZStack {
            if glow {
                Circle().fill(SteamArtist.bright.opacity(0.30)).frame(width: radius * 2.3, height: radius * 2.3).blur(radius: radius * 0.35)
            }
            Circle().stroke(SteamArtist.white, lineWidth: radius * 0.12).frame(width: radius * 2, height: radius * 2)
                .shadow(color: .black.opacity(0.4), radius: radius * 0.06, y: radius * 0.03)
            PlayTriangle()
                .fill(SteamArtist.white)
                .overlay(PlayTriangle().stroke(SteamArtist.white, style: StrokeStyle(lineWidth: radius * 0.13, lineJoin: .round)))
                .frame(width: radius * 0.63, height: radius * 0.71)
                .offset(x: radius * 0.07)
        }
        .frame(width: radius * 2.4, height: radius * 2.4)
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Wordmark: View {
    let text: String
    let size: CGFloat
    var lines = 1

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .kerning(size * -0.01)
            .foregroundStyle(SteamArtist.white)
            .multilineTextAlignment(.center)
            .lineLimit(lines)
            .minimumScaleFactor(0.6)
            .shadow(color: .black.opacity(0.55), radius: size * 0.12, y: size * 0.03)
    }
}

private struct Caption: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 22, weight: .semibold)).kerning(5).foregroundStyle(SteamArtist.white.opacity(0.62))
    }
}

/// The small AnyPS5 sign on a game's capsules.
private struct Badge: View {
    var body: some View {
        HStack(spacing: 10) {
            PlayMark(radius: 15, glow: false).frame(width: 36, height: 36)
            Text("AnyPS5").font(.system(size: 26, weight: .bold)).foregroundStyle(SteamArtist.white.opacity(0.85))
        }
    }
}

/// A small seeded generator, so the dust lands the same way each time.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

/// `AnyPS5 --steam-art <folder> [<sce_sys>]`: the Steam pictures as files, for checking the design
/// without a window or a Steam account.
@MainActor
enum SteamArtPreview {
    static func run(output: URL, sceSys: URL?) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let accent = Color(red: 0.31, green: 0.58, blue: 1.0)
        func write(_ prefix: String, _ art: [SteamArt: Data?]) {
            for (kind, data) in art { try? data?.write(to: output.appendingPathComponent(prefix + kind.suffix)) }
        }
        write("launcher", SteamArtist.launcher(accent: accent))
        if let sceSys {
            write("game", SteamArtist.game(name: "Hollow Knight: Silksong", background: sceSys.appendingPathComponent("pic0.png"),
                                           cover: sceSys.appendingPathComponent("icon0.png"), accent: accent))
        }
        write("bare", SteamArtist.game(name: "A Game Without Any Pictures", background: nil, cover: nil, accent: accent))
    }
}
