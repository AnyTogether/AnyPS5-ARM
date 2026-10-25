import AnyPS5Core
import AppKit
import SwiftUI

/// The Glass theme's see-through window: what is behind the launcher (the desktop picture, other
/// apps' windows) shows through it, blurred by the window server and tinted navy so the text
/// reads over anything. Liquid Glass (glassEffect, NSGlassEffectView) only refracts what is inside
/// the window, so the window's own backdrop is an NSVisualEffectView blending behind the window,
/// on macOS 26 as before it, with the Liquid Glass surfaces on top of it.
enum GlassWindow {
    /// The blur behind the window: the sidebar's material, dark, the most vivid of the system's
    /// (the wallpaper's colors glow through it, as in Finder's sidebar); it stays frosted while
    /// the launcher is not the key window. The text is kept readable on plates, not by it.
    static let material = NSVisualEffectView.Material.sidebar

    /// Makes the window see-through, or opaque again (the other themes, Reduce Transparency).
    static func apply(_ recipe: GlassWindowRecipe, to window: NSWindow) {
        let clear = recipe.translucent
        if window.isOpaque == clear { window.isOpaque = !clear }
        let color: NSColor = clear ? .clear : .black
        if window.backgroundColor != color { window.backgroundColor = color }
        window.titlebarAppearsTransparent = true
        // The shadow follows the window's shape, which changes with its opacity.
        window.invalidateShadow()
    }

    static func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.appearance = NSAppearance(named: .darkAqua)
        view.autoresizingMask = [.width, .height]
    }
}

/// Where the main window stands, for the views inside it.
@MainActor
final class GlassWindowState: ObservableObject {
    static let shared = GlassWindowState()

    /// In a full screen space there is no desktop behind the window: the desktop picture is
    /// drawn instead, blurred, so the glass never turns black.
    @Published var fullScreen = false
    /// The desktop picture of the window's screen, when it can be read without asking.
    @Published var wallpaper: URL?

    func update(for window: NSWindow) {
        let full = window.styleMask.contains(.fullScreen)
        if full != fullScreen { fullScreen = full }
        let picture = (window.screen ?? NSScreen.main).flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            .flatMap { GlassWindowRecipe.mayReadWallpaper($0, home: FileManager.default.homeDirectoryForCurrentUser) ? $0 : nil }
        if picture != wallpaper { wallpaper = picture }
    }
}

/// An invisible view in the main window that keeps the window's opacity in step with the look and
/// follows it in and out of full screen.
struct GlassWindowHook: NSViewRepresentable {
    let recipe: GlassWindowRecipe

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.recipe = recipe
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.recipe = recipe
    }

    final class HookView: NSView {
        var recipe = GlassWindowRecipe.opaque {
            didSet { if recipe != oldValue { applyToWindow() } }
        }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            applyToWindow()
            let names: [Notification.Name] = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                                              NSWindow.willEnterFullScreenNotification, NSWindow.didChangeScreenNotification]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        // Entering: the space is not there yet, but it will hold no desktop.
                        if notification.name == NSWindow.willEnterFullScreenNotification { GlassWindowState.shared.fullScreen = true }
                        else { GlassWindowState.shared.update(for: window) }
                        self?.applyToWindow()
                    }
                })
            }
        }

        private func applyToWindow() {
            guard let window else { return }
            GlassWindow.apply(recipe, to: window)
            GlassWindowState.shared.update(for: window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// The window server's blur of what is behind the window.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        GlassWindow.configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        GlassWindow.configure(view)
    }
}

/// The previews' stand-in for the desktop behind the window (ANYPS5_PREVIEW_WALLPAPER): a mock,
/// since an offscreen render has no window and nothing behind it.
struct MockDesktop: EnvironmentKey {
    static let defaultValue: NSImage? = nil
}

extension EnvironmentValues {
    var mockDesktop: NSImage? {
        get { self[MockDesktop.self] }
        set { self[MockDesktop.self] = newValue }
    }
}

/// The bottom of the see-through window: the blurred desktop, a light navy tint over it, light
/// from the top left and a still grain. No veil: text reads on its plates (Legible, the glass).
struct GlassWindowBackdrop: View {
    let recipe: GlassWindowRecipe
    @ObservedObject private var state = GlassWindowState.shared
    @ObservedObject private var artwork = Artwork.shared
    @Environment(\.previewRender) private var offscreen
    @Environment(\.mockDesktop) private var mockDesktop

    var body: some View {
        ZStack {
            if offscreen {
                if let mockDesktop { Image(nsImage: mockDesktop).resizable().aspectRatio(contentMode: .fill) }
            } else {
                BehindWindowBlur()
                // Full screen: no desktop is behind the window, so its picture is drawn instead.
                if state.fullScreen {
                    if let picture = artwork.frosted(state.wallpaper) {
                        Image(nsImage: picture).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else {
                        // Nothing to read (a live wallpaper, one in a protected folder): the
                        // Glass palette's own deep blue.
                        LinearGradient(colors: [Color(recipe: GlassRecipe.solid), Ice.scrim], startPoint: .topTrailing, endPoint: .bottomLeading)
                    }
                }
            }
            Ice.scrim.opacity(recipe.tint)
            RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: UnitPoint(x: 0.12, y: -0.1), startRadius: 0, endRadius: 1100)
            LinearGradient(colors: [.clear, Ice.cyan.opacity(0.03)], startPoint: .top, endPoint: .bottom)
            GrainLayer(strength: 0.03)
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
