import CoreGraphics
import Foundation

/// A game's start as the console shows it, as on Windows and Linux (AnyPS5 Desktop's
/// desktop.dart and app_model.dart's _handOff): the game's cover stays up while it loads and
/// goes once its window has settled. In full screen a panel of the cover above the game fades
/// away over it; in a window the cover goes on the launcher's home. These are Desktop's timings.
public struct StartCoverTiming: Equatable, Sendable {
    /// How long the cover over the game fades away over (coverFade).
    public var fade: TimeInterval
    /// The same with reduced motion.
    public var reducedFade: TimeInterval
    /// The longest the cover stays opaque over the opened window waiting for it to settle
    /// (coverHoldLimit).
    public var holdLimit: TimeInterval
    /// How long the cover stays opaque after the window settled, so its first frames are drawn
    /// before it goes (coverSettle).
    public var settle: TimeInterval
    /// The longest the cover waits on the home screen for the game's window to settle, from the
    /// process's start (coverWindowWait).
    public var windowWait: TimeInterval
    /// The engine sizes its own window, so there is no display step to wait for: the window is
    /// settled a second after the process started at the earliest (Desktop's `display == null`).
    public var displayDelay: TimeInterval
    /// The cover's entrance, and its leave from the home screen.
    public var entrance: TimeInterval

    public init(fade: TimeInterval = 0.7, reducedFade: TimeInterval = 0.12, holdLimit: TimeInterval = 6, settle: TimeInterval = 0.25,
                windowWait: TimeInterval = 20, displayDelay: TimeInterval = 1, entrance: TimeInterval = 0.45) {
        self.fade = fade
        self.reducedFade = reducedFade
        self.holdLimit = holdLimit
        self.settle = settle
        self.windowWait = windowWait
        self.displayDelay = displayDelay
        self.entrance = entrance
    }

    public static let standard = StartCoverTiming()

    /// The fade over the game: very short with reduced motion.
    public func fade(reducedMotion: Bool) -> TimeInterval { reducedMotion ? reducedFade : fade }

    /// The cover's opacity `sinceRelease` seconds after it was let go: 1 before that (negative),
    /// then an ease in and out down to 0 over `fade`. A zero fade goes at once.
    public static func opacity(sinceRelease: TimeInterval, fade: TimeInterval) -> Double {
        if sinceRelease < 0 { return 1 }
        if fade <= 0 { return 0 }
        let t = min(1, max(0, sinceRelease / fade))
        return 1 - t * t * (3 - 2 * t)
    }
}

/// The cover over the game from the moment it is on screen: opaque until the game's window has
/// settled (or `holdLimit` has passed), `settle` more, then the fade. A game that closed lets it
/// go at once, into the fade without the hold.
public struct StartCoverHold: Sendable {
    public let timing: StartCoverTiming
    public let fade: TimeInterval
    public private(set) var releaseAt: TimeInterval?

    public init(timing: StartCoverTiming = .standard, reducedMotion: Bool) {
        self.timing = timing
        self.fade = timing.fade(reducedMotion: reducedMotion)
    }

    /// The opacity `elapsed` seconds after the cover showed; nil once it has gone.
    public mutating func opacity(at elapsed: TimeInterval, settled: Bool, gone: Bool) -> Double? {
        if releaseAt == nil {
            if gone {
                releaseAt = elapsed
            } else if settled || elapsed >= timing.holdLimit {
                releaseAt = elapsed + timing.settle
            }
        }
        let opacity = releaseAt.map { StartCoverTiming.opacity(sinceRelease: elapsed - $0, fade: fade) } ?? 1
        return opacity <= 0 ? nil : opacity
    }
}

/// Whether the game's window has settled: the process began at least `delay` ago and the
/// window's frame stayed the same for `stillChecks` checks in a row (a full screen switch or a
/// resize moves it until it is done).
public struct StartCoverSettle: Sendable {
    public static let stillChecks = 2
    public let began: Date
    public let delay: TimeInterval
    private var last: CGRect?
    private var still = 0

    public init(began: Date, delay: TimeInterval) {
        self.began = began
        self.delay = delay
    }

    /// One look at the window's frame (nil: no window now).
    public mutating func check(_ frame: CGRect?, now: Date = Date()) -> Bool {
        guard let frame else {
            last = nil
            still = 0
            return false
        }
        still = frame == last ? still + 1 : 0
        last = frame
        return still >= Self.stillChecks && now.timeIntervalSince(began) >= delay
    }
}

/// Which screen the cover over the game goes on.
public enum StartCoverPlace {
    /// The index of the screen in `screens` (AppKit's frames, the main screen's bottom left
    /// corner at 0, 0) that holds most of `window` (the window server's frame, the main screen's
    /// top left corner at 0, 0, y going down); nil when none holds any of it.
    public static func screen(of window: CGRect, screens: [CGRect], primaryHeight: CGFloat) -> Int? {
        let flipped = CGRect(x: window.minX, y: primaryHeight - window.maxY, width: window.width, height: window.height)
        let areas = screens.map { screen -> CGFloat in
            let common = screen.intersection(flipped)
            return common.isNull ? 0 : common.width * common.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }
}
