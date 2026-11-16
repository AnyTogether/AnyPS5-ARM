import AppKit
import SwiftUI

/// The start animation, as on Windows and Linux: a dark screen with a spotlight and four dots,
/// the tiles popping in one after the other, then the top bar, the selected game's details and
/// the button hints. It plays once per run, the first time the home screen shows with nothing over
/// it (after the profile picker at launch, with the picked profile's settings). With reduced
/// motion, or a game starting or running at that moment, it does not play in that run. `enabled`
/// is off until the app starts, so the tests and the previews never wait for it.
enum StartupIntro {
    static var enabled = false
    static var played = false

    static let duration: TimeInterval = 2.6

    /// The moment, as a fraction of `duration`, each part starts and ends.
    static let curtainFade = (0.18, 0.55)
    static let topBar = (0.50, 0.75)
    static let hero = (0.62, 0.90)
    static let hints = (0.75, 0.95)

    /// A tile's own span: the tiles start 3 % of the animation apart from 30 %, ten steps at most.
    static func tile(_ index: Int) -> (Double, Double) {
        let from = 0.30 + Double(min(index, 9)) * 0.03
        return (from, from + 0.22)
    }

    enum Start: Equatable {
        /// Already played, not the real launcher, or a preview: nothing happens.
        case none
        /// Something is over the home screen (the profile picker at launch): later.
        case wait
        /// Not in this run.
        case skip
        case play
    }

    static func decide(enabled: Bool, played: Bool, offscreen: Bool, covered: Bool, gameBusy: Bool, reduceMotion: Bool) -> Start {
        guard enabled, !played, !offscreen else { return .none }
        if covered { return .wait }
        if gameBusy || reduceMotion { return .skip }
        return .play
    }

    /// How far the animation is, 0 to 1; 1 once it is over or when it does not play.
    static func progress(since start: Date?, now: Date) -> Double {
        guard let start else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }

    /// A part's own progress within `span`, with the launcher's settle curve (Motion.settle on
    /// Windows and Linux: a strong ease-out).
    static func reveal(_ progress: Double, span: (Double, Double)) -> Double {
        settle.transform(interval(progress, span))
    }

    /// The curtain's fade, 0 while it covers, 1 once it is gone.
    static func curtainGone(_ progress: Double) -> Double {
        easeInOut.transform(interval(progress, curtainFade))
    }

    static func interval(_ progress: Double, _ span: (Double, Double)) -> Double {
        min(1, max(0, (progress - span.0) / (span.1 - span.0)))
    }

    static let settle = CubicCurve(0.22, 1, 0.36, 1)
    static let easeInOut = CubicCurve(0.42, 0, 0.58, 1)
}

/// A cubic Bézier timing curve from (0, 0) to (1, 1), as Flutter's Cubic.
struct CubicCurve {
    let a: Double, b: Double, c: Double, d: Double

    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    private static func point(_ p1: Double, _ p2: Double, _ m: Double) -> Double {
        3 * p1 * (1 - m) * (1 - m) * m + 3 * p2 * (1 - m) * m * m + m * m * m
    }

    func transform(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var low = 0.0, high = 1.0
        while true {
            let mid = (low + high) / 2
            let x = Self.point(a, c, mid)
            if abs(t - x) < 0.0001 || high - low < 1e-9 { return Self.point(b, d, mid) }
            if x < t { low = mid } else { high = mid }
        }
    }
}

/// A part of the home screen coming in: it fades, slides (by a fraction of its own height) and
/// grows into place within its span of the animation. At the end it is exactly as without it.
struct IntroReveal: ViewModifier {
    let progress: Double
    let span: (Double, Double)
    var slide: CGFloat = 0
    var scaleFrom: CGFloat = 1

    func body(content: Content) -> some View {
        let t = StartupIntro.reveal(progress, span: span)
        let shift = slide * CGFloat(1 - t)
        content
            .scaleEffect(scaleFrom + (1 - scaleFrom) * CGFloat(t))
            .visualEffect { view, proxy in view.offset(y: proxy.size.height * shift) }
            .opacity(t)
    }
}

extension View {
    func introReveal(_ progress: Double, span: (Double, Double), slide: CGFloat = 0, scaleFrom: CGFloat = 1) -> some View {
        modifier(IntroReveal(progress: progress, span: span, slide: slide, scaleFrom: scaleFrom))
    }
}

/// Over the home screen at the start: the theme's deep color with a spotlight from the top left
/// and four dots breathing, then fading away to show the background and the tiles.
struct IntroCurtain: View {
    let progress: Double
    let deep: Color
    @Environment(\.scale) private var scale

    var body: some View {
        let gone = StartupIntro.curtainGone(progress)
        if gone < 1 {
            GeometryReader { proxy in
                ZStack {
                    deep
                    RadialGradient(colors: [.white.opacity(0.15), .white.opacity(0)], center: UnitPoint(x: 0.225, y: -0.075),
                                   startRadius: 0, endRadius: 1.25 * min(proxy.size.width, proxy.size.height))
                    HStack(spacing: 22 * scale) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(Color.white.opacity(IntroCurtain.dot(index, progress: progress)))
                                .frame(width: 8 * scale, height: 8 * scale)
                        }
                    }
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.25)
                }
            }
            .opacity(1 - gone)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// A dot's brightness: each breathes a little after the one before it.
    static func dot(_ index: Int, progress: Double) -> Double {
        0.3 + 0.7 * (0.5 + 0.5 * sin(progress * 22 - Double(index) * 1.1))
    }
}
