import AnyPS5Core
import AppKit
import SwiftUI

// A game's start as the console shows it, as on Windows and Linux (AnyPS5 Desktop's
// start_cover.dart and _handOff): the game's cover stays up while it loads. Once its window is
// there the cover goes: in full screen a panel of it above the game's window fades away over the
// game (Desktop's layered window on Windows), in a window it goes on the launcher's home. It never
// stays while the game plays: the game closing, a menu opening and the caps all let it go.

/// The Start animation of a start, as it was when Play was pressed; `began` is when the game's
/// process started, which the display delay counts from.
struct StartCoverChoice: Equatable {
    var animation: Bool
    var overGame: Bool
    var began: Date?
}

/// One hand-off: a menu let it go (`dismissed`), or the game ended (`gone`).
@MainActor
final class StartCoverTurn {
    var dismissed = false
    var gone = false
}

/// What the cover over the game is drawn in: a panel on the game's screen (StartCoverPanel), a
/// stand-in in the tests.
@MainActor
protocol StartCoverSurface: AnyObject {
    var alpha: Double { get set }
    func close()
}

extension AppModel {
    /// Whether `game`'s start shows its cover: as chosen when Play was pressed while it starts,
    /// else its settings now (the fonts' wait before the start).
    func showsCover(_ game: Game) -> Bool {
        if coverGame?.id == game.id { return true }
        if starting?.id == game.id, let startCover { return startCover.animation }
        return launchSettings(for: game).startAnimation
    }

    /// Reduced motion here, in the system or by a battery profile: the short fade and no zoom.
    var coverReducedMotion: Bool {
        Motion.reduced || preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The cover's leave from the home screen: Desktop's 450 ms ease in, the short fade with
    /// reduced motion.
    func coverLeave(reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : .easeIn(duration: coverTiming.entrance)
    }

    /// From the game's window showing to it having settled: the cover stays, then goes (over the
    /// game in full screen, on the home screen in a window), and only then does the launcher step
    /// aside (Hide the launcher while a game runs). Never keeps the cover once the game closed.
    func handOff(_ game: Game, app: NSRunningApplication, overGame: Bool, began: Date) async {
        coverTurn?.dismissed = true
        let turn = StartCoverTurn()
        coverTurn = turn
        coverHandedOver = false
        coverGame = game
        let pid = app.processIdentifier
        let timing = coverTiming
        let reduced = coverReducedMotion
        var settle = StartCoverSettle(began: began, delay: timing.displayDelay)
        let gone = { [weak self] () -> Bool in
            guard let self else { return true }
            return turn.gone || !self.gameAlive(pid) || self.running?.app.processIdentifier != pid
        }
        let surface = overGame ? makeCoverSurface(game, accent, gameWindowFrame(pid) ?? .null) : nil
        bringGameFront(app)
        if let surface {
            // The panel took the cover's place: the launcher's goes at once, under it.
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                coverHandedOver = true
                coverGame = nil
            }
            var hold = StartCoverHold(timing: timing, reducedMotion: reduced)
            let shown = Date()
            var checked = -Double.infinity
            var settled = false
            var ended = false
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(shown)
                // The windows are listed a few times a second only.
                if elapsed - checked >= 0.1 {
                    checked = elapsed
                    ended = gone()
                    settled = turn.dismissed || settle.check(gameWindowFrame(pid))
                }
                guard let opacity = hold.opacity(at: elapsed, settled: settled, gone: ended) else { break }
                surface.alpha = opacity
                try? await Task.sleep(for: .milliseconds(16))
            }
            surface.close()
        } else {
            // In a window, or no panel over the game: the cover waits on the home screen.
            let deadline = began.addingTimeInterval(timing.windowWait)
            while !Task.isCancelled, !turn.dismissed, !gone(), Date() < deadline, !settle.check(gameWindowFrame(pid)) {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        // Another start's cover is not this one's to take away.
        if coverTurn === turn {
            coverTurn = nil
            coverHandedOver = false
            if coverGame != nil { withAnimation(coverLeave(reduced: reduced)) { coverGame = nil } }
        }
        guard !gone() else { return }
        if persists { tellLowPower(about: game) }
        if preferences.hideWhilePlaying { hideWindows() }
    }

    /// A menu opened over the cover: it goes, and the panel over the game is let go.
    func dropCover() {
        guard let turn = coverTurn, !turn.dismissed else { return }
        turn.dismissed = true
        if coverGame != nil { withAnimation(coverLeave(reduced: coverReducedMotion)) { coverGame = nil } }
    }

    /// The game ended: no cover is left, the panel over the game goes into its fade at once.
    func endCover() {
        coverTurn?.gone = true
        coverTurn?.dismissed = true
        coverTurn = nil
        coverHandedOver = false
        if coverGame != nil { withAnimation(Motion.overlay) { coverGame = nil } }
    }

    /// The frame of `pid`'s largest window on the normal layer, in the window server's
    /// coordinates (the main screen's top left corner is 0, 0); nil while it has none. A window on
    /// a Space not shown yet (a full screen one) counts, as for hasWindow.
    nonisolated static func windowFrame(of pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else { return nil }
        return windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerPID] as? pid_t) == pid, (window[kCGWindowLayer] as? Int) == 0,
                  let bounds = window[kCGWindowBounds] as? [String: CGFloat] else { return nil }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            return frame.width > 200 && frame.height > 150 ? frame : nil
        }
        .max { $0.width * $0.height < $1.width * $1.height }
    }
}

/// The cover over the game: a borderless panel over the whole of the game's screen, above every
/// window (the full-screen game's too, as the trophy banner is), on every Space, that never takes
/// the keyboard, the mouse or the front from the game. It draws the same cover as the launcher.
@MainActor
final class StartCoverPanel: StartCoverSurface {
    private let panel: NSPanel

    private init(panel: NSPanel) {
        self.panel = panel
    }

    var alpha: Double {
        get { panel.alphaValue }
        set { panel.alphaValue = newValue }
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// The panel shown over the screen `window` (the window server's frame of the game's window)
    /// is on, the main screen when no screen holds it (it has no frame yet); nil without a screen.
    static func make(game: Game, accent: Color, window: CGRect) -> StartCoverPanel? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let index = window.isNull ? nil : StartCoverPlace.screen(of: window, screens: screens.map(\.frame), primaryHeight: primary.frame.height)
        let frame = index.map { screens[$0].frame } ?? (NSScreen.main ?? primary).frame
        // The launcher's cover read these already; the panel must not draw without them.
        for (url, size) in [(game.background, 1920), (game.icon, 400)] where url != nil && Artwork.shared.image(url, maxPixels: size) == nil {
            Artwork.shared.prepare(url, maxPixels: size)
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let scale = min(1.45, max(0.68, min(frame.width / 1600, frame.height / 900)))
        let cover = StartCoverView(game: game, accent: accent, status: T.text(.startingText), entrance: false)
            .environment(\.scale, scale)
            .preferredColorScheme(.dark)
        panel.contentView = NSHostingView(rootView: cover)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        return StartCoverPanel(panel: panel)
    }
}

/// The cover in the launcher's window, from the press of Play (and the fonts' wait before it)
/// until the game's window has settled. Esc or ○ gives the start up while it has no window.
struct StartCoverLayer: View {
    let game: Game
    @EnvironmentObject private var model: AppModel
    @Environment(\.look) private var look
    @Environment(\.stillBackground) private var stillBackground

    var body: some View {
        let fonts = model.starting == nil && model.coverGame == nil && model.fontWait?.id == game.id
        let waiting = model.starting?.id == game.id
        StartCoverView(game: game, accent: model.accent,
                       status: fonts ? TF.format(.gettingText, game.name, model.cjkDownloadSize) : T.text(.startingText),
                       progress: fonts ? (model.cjkProgress ?? 0) : nil,
                       elapsed: waiting, cancel: waiting || fonts,
                       // Offscreen (the previews) there is no entrance to wait for.
                       entrance: stillBackground == nil, reduceMotion: look.reduceMotion)
    }
}

/// The cover itself, as on Windows and Linux: the game's wide artwork over the whole window (its
/// icon enlarged and blurred when it has none), darker towards the bottom, and there the icon, the
/// name, a line of text and the accent's moving line. It comes in over 450 ms with a slight zoom
/// out; reduced motion only fades it in.
struct StartCoverView: View {
    let game: Game
    let accent: Color
    var status: String
    /// The fonts' download; nil is the moving line.
    var progress: Double?
    /// The time since it appeared, beside the line (the Mac's start screen had it).
    var elapsed = false
    var cancel = false
    var entrance = true
    var reduceMotion = false
    @Environment(\.scale) private var scale
    @State private var shown = false
    @State private var since = Date()

    /// The zoom it comes in from.
    static func entranceScale(reducedMotion: Bool) -> CGFloat { reducedMotion ? 1 : 1.04 }

    static func entranceAnimation(reducedMotion: Bool) -> Animation {
        reducedMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: StartCoverTiming.standard.entrance)
    }

    var body: some View {
        let visible = shown || !entrance
        ZStack {
            // Under the entrance: the cover is never see-through.
            Color.black
            ZStack(alignment: .bottomLeading) {
                artwork
                LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .black.opacity(0.35), location: 0.5),
                                       .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
                details
                    .padding(EdgeInsets(top: 48 * scale, leading: 72 * scale, bottom: 64 * scale, trailing: 72 * scale))
            }
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : Self.entranceScale(reducedMotion: reduceMotion))
            if cancel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Hint(keys: "esc / ○", label: T.text(.cancel))
                    }
                }
                .padding(EdgeInsets(top: 48 * scale, leading: 72 * scale, bottom: 60 * scale, trailing: 72 * scale))
            }
        }
        .clipped()
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear {
            since = Date()
            guard entrance else { return }
            withAnimation(Self.entranceAnimation(reducedMotion: reduceMotion)) { shown = true }
        }
    }

    @ViewBuilder private var artwork: some View {
        GeometryReader { proxy in
            Group {
                if let background = game.background {
                    ArtworkImage(url: background, maxPixels: 1920)
                } else if let icon = game.icon {
                    ArtworkImage(url: icon, maxPixels: 400)
                        .scaleEffect(1.6)
                        .blur(radius: 36 * scale, opaque: true)
                } else {
                    RadialGradient(colors: [accent.opacity(0.28), .clear], center: .bottomLeading, startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var details: some View {
        HStack(alignment: .bottom, spacing: 28 * scale) {
            if let icon = game.icon {
                ArtworkImage(url: icon, maxPixels: 400)
                    .frame(width: 120 * scale, height: 120 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 18 * scale, y: 6 * scale)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(game.name)
                    .font(.display(44 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.bottom, 10 * scale)
                Text(status)
                    .font(.display(16 * scale))
                    .lineSpacing(5 * scale)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: 560 * scale, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22 * scale)
                HStack(spacing: 14 * scale) {
                    Group {
                        if let progress {
                            ProgressLine(fraction: progress, color: accent)
                        } else {
                            IndeterminateLine(color: accent)
                        }
                    }
                    .frame(width: 320 * scale)
                    if let progress {
                        Text(TF.format(.gettingProgress, Int(progress * 100)))
                            .font(.display(14 * scale, .semibold)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                    } else if elapsed {
                        TimelineView(.periodic(from: since, by: 1)) { context in
                            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                                .font(.display(14 * scale, .semibold)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
    }
}
