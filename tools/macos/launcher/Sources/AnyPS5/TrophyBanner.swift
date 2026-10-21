import AnyPS5Core
import AppKit
import SwiftUI

/// The card that drops in at the top of the screen when a game earns a trophy: a borderless panel
/// above every window, the full-screen game's included, that never takes the keyboard or the mouse
/// from the game.
@MainActor
final class TrophyBanner {
    static let shared = TrophyBanner()
    static let size = CGSize(width: 560, height: 150)

    private var queue: [TrophySet.Trophy] = []
    private var panel: NSPanel?
    private var showing = false
    private var sounds = true

    func show(_ trophy: TrophySet.Trophy, sounds: Bool) {
        self.sounds = sounds
        queue.append(trophy)
        next()
    }

    private func next() {
        guard !showing, !queue.isEmpty, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        showing = true
        let trophy = queue.removeFirst()
        let size = TrophyBanner.size
        // Below the notch and the menu bar, centered.
        let top = screen.frame.maxY - screen.safeAreaInsets.top
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: false)
        panel.contentView = NSHostingView(rootView: TrophyToast(trophy: trophy) { [weak self] in self?.finish() })
        panel.orderFrontRegardless()
        if sounds { Sounds.shared.play(.unlocked) }
    }

    private func finish() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        showing = false
        next()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// The trophy card: it slides down with a spring, the icon pops in, and after a few seconds it
/// rises away again. `still` draws it settled, for the offscreen previews.
struct TrophyToast: View {
    let trophy: TrophySet.Trophy
    var still = false
    let done: () -> Void
    @State private var shown = false
    @State private var popped = false

    var body: some View {
        let visible = shown || still
        VStack {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(trophy.grade.color.opacity(0.35)).blur(radius: 14).frame(width: 64, height: 64)
                        .opacity(popped || still ? 1 : 0)
                    TrophyIcon(data: trophy.icon, key: "banner/" + trophy.id, size: 60, earned: true)
                        .scaleEffect(popped || still ? 1 : 0.6)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(T.text(.trophyEarned), systemImage: "trophy.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(trophy.grade.color)
                    Text(trophy.name.isEmpty ? T.text(.trophyHidden) : trophy.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(trophy.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [trophy.grade.color, trophy.grade.color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .padding(.trailing, 6)
            }
            .padding(14)
            .frame(width: 480)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.07).opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                LinearGradient(colors: [trophy.grade.color.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            .offset(y: visible ? 14 : -TrophyBanner.size.height)
            .opacity(visible ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(width: TrophyBanner.size.width, height: TrophyBanner.size.height)
        .onAppear {
            guard !still else { return }
            withAnimation(Motion.reduced ? .easeOut(duration: 0.25) : .spring(response: 0.55, dampingFraction: 0.78)) { shown = true }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.18)) { popped = true }
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeIn(duration: 0.3)) { shown = false }
                try? await Task.sleep(for: .seconds(0.35))
                done()
            }
        }
    }
}
