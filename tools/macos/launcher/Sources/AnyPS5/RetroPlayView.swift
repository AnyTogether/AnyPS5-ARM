import AnyPS5Core
import AppKit
import SwiftUI

/// A PS1 game playing in the launcher's window through the emulator host, as on Windows and Linux
/// (AnyPS5 Desktop's lib/ui/retro_host/retro_play_view.dart): its picture over the whole window,
/// the loading screen while it starts, and its error screen when it stopped on one.
struct RetroPlayView: View {
    let play: RetroPlay
    @ObservedObject var host: RetroHostGame
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let status = host.status
        let problem = play.problem
        ZStack {
            Color.black
            RetroFrameLayer(picture: host.picture)
                .aspectRatio(host.aspect, contentMode: .fit)
            if let problem {
                RetroGameNotice(name: TRetro.format(.retroHostStopped, play.game.name), icon: play.game.icon, text: TRetro.text(problem),
                                action: TRetro.text(.retroHostBack),
                                optionsAction: problem == .retroHostBiosDetail ? TRetro.text(.retroHostBiosFolder) : nil)
                    .transition(.opacity)
            } else if play.loading && !play.closing {
                RetroGameNotice(name: play.game.name, icon: play.game.icon, text: AppModel.retroLoadingText(status),
                                progress: status?.progressPercent.map { Double($0) / 100 }, working: true)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(Motion.fade, value: problem)
    }
}

/// The game's picture: the newest frame the host drew, set on a layer as it comes, stretched to
/// the box the core's display aspect ratio gives it, its pixels not smoothed. Nothing but black
/// before the first frame.
struct RetroFrameLayer: NSViewRepresentable {
    let picture: RetroFramePicture

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .linear
        view.layer = layer
        attach(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        attach(view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        view.layer?.contents = nil
    }

    /// Each new picture goes straight to the layer, without drawing the screen again.
    private func attach(_ view: NSView) {
        let picture = picture
        view.layer?.contents = picture.image
        picture.onImage = { [weak view] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view?.layer?.contents = picture.image
            CATransaction.commit()
        }
    }
}

/// A game's name and icon over a dimmed screen with a line of words: what it is loading, with a
/// progress line (an endless one while the progress is not known), or why it stopped, with the
/// keys that go on.
struct RetroGameNotice: View {
    let name: String
    let icon: URL?
    let text: String
    var progress: Double?
    var working = false
    var action: String?
    var optionsAction: String?
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VStack(spacing: 0) {
                if let icon {
                    ArtworkImage(url: icon, maxPixels: 400)
                        .frame(width: 160 * scale, height: 160 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
                        .shadow(color: model.accent.opacity(0.35), radius: 24 * scale)
                        .padding(.bottom, 28 * scale)
                }
                Text(name)
                    .font(.display(36 * scale, .light))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(text)
                    .font(.display(16 * scale))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4 * scale)
                    .frame(maxWidth: 560 * scale)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12 * scale)
                if working {
                    RetroProgressLine(fraction: progress, accent: model.accent)
                        .frame(width: 260 * scale, height: 4 * scale)
                        .padding(.top, 24 * scale)
                }
                if let action {
                    HStack(spacing: 28 * scale) {
                        Hint(keys: "↩ / ✕", label: action)
                        if let optionsAction { Hint(keys: "O / △", label: optionsAction) }
                    }
                    .padding(.top, 28 * scale)
                }
            }
            .padding(.horizontal, 40 * scale)
        }
        .ignoresSafeArea()
    }
}

/// A thin line of how far the game has loaded; while that is not known, a short piece of it
/// travels along, still with reduced motion.
private struct RetroProgressLine: View {
    let fraction: Double?
    let accent: Color
    @State private var travel = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                if let fraction {
                    Capsule().fill(accent)
                        .frame(width: max(proxy.size.height, proxy.size.width * min(1, max(0, fraction))))
                        .animation(Motion.focus, value: fraction)
                } else {
                    Capsule().fill(accent)
                        .frame(width: proxy.size.width * 0.3)
                        .offset(x: Motion.reduced ? proxy.size.width * 0.35 : (travel ? proxy.size.width * 0.7 : 0))
                        .onAppear {
                            guard !Motion.reduced else { return }
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { travel = true }
                        }
                }
            }
        }
    }
}

/// The small label in the window's bottom corner while a PS1 game runs on a host that was not
/// checked: "Unchecked emulator (test build)", over the game, its loading and error screens and
/// every layer above them, so that no screenshot of the game passes for a release. Only a debug
/// build draws it; a release is compiled without it.
struct RetroUncheckedMark: View {
    @Environment(\.scale) private var scale

    var body: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "flask").font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.7, blue: 0.3))
                    Text(TRetro.text(.retroHostUnchecked))
                        .font(.display(12 * scale, .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 6 * scale)
                .background(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).fill(Color.black.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous).strokeBorder(Color(red: 1, green: 0.7, blue: 0.3).opacity(0.45), lineWidth: 1))
                Spacer()
            }
        }
        .padding(20 * scale)
        .allowsHitTesting(false)
        .accessibilityIdentifier("retro-unchecked-mark")
    }
}
