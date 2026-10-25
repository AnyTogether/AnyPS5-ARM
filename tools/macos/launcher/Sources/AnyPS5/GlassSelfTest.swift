import AnyPS5Core
import AppKit
import SwiftUI

/// `AnyPS5 --glass-selftest` builds the launcher's window for every theme without ever putting it
/// on screen and checks how it is made: Glass see-through (not opaque, a clear background, the
/// window server's blur behind it, active while not key, the navy tint at the slider's value),
/// Reduce Transparency, the slider at 0 % and the other themes opaque and black as before.
/// What the blur looks like over a real desktop needs eyes on a live window.
@MainActor
enum GlassSelfTest {
    struct Case {
        let name: String
        let theme: Theme
        var transparency: Int?
        var reduceTransparency = false
    }

    static let cases = [
        Case(name: "Glass, default transparency", theme: .glass),
        Case(name: "Glass, 100 %", theme: .glass, transparency: 100),
        Case(name: "Glass, 40 %", theme: .glass, transparency: 40),
        Case(name: "Glass, 0 % (solid)", theme: .glass, transparency: 0),
        Case(name: "Glass, Reduce Transparency", theme: .glass, reduceTransparency: true),
        Case(name: "Cosmic", theme: .cosmic, transparency: 100),
        Case(name: "Aurora", theme: .aurora),
        Case(name: "Sunset", theme: .sunset),
    ]

    static func run() -> Int32 {
        let app = NSApplication.shared
        // No Dock icon, no menu bar, never active: nothing of this shows.
        app.setActivationPolicy(.prohibited)
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print("  \(ok ? "PASS" : "FAIL")  \(what)")
            if !ok { failures += 1 }
        }

        for test in cases {
            print(test.name)
            Look.forceSolid = test.reduceTransparency
            var preferences = Preferences()
            preferences.onboarded = true
            preferences.sounds = false
            preferences.theme = test.theme
            preferences.glassTransparency = test.transparency
            let model = AppModel(preferences: preferences)
            model.preview(games: [], root: FileManager.default.temporaryDirectory)

            // The launcher's own window style: titled, full-size content under a hidden title bar.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
            let host = NSHostingView(rootView: RootView().environmentObject(model).frame(width: 1280, height: 720))
            window.contentView = host
            for _ in 0..<4 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            check(!window.isVisible, "the window never went on screen")

            let expected = GlassWindowRecipe.make(glass: test.theme.isGlass, reduceTransparency: test.reduceTransparency, transparency: test.transparency)
            let blurs = subviews(of: host).compactMap { $0 as? NSVisualEffectView }.filter { $0.blendingMode == .behindWindow }
            check(Look.current.window == expected, "the look carries the window recipe (see-through \(expected.translucent), tint \(String(format: "%.2f", expected.tint)))")
            if expected.translucent {
                check(!window.isOpaque, "window.isOpaque is false")
                check(window.backgroundColor.alphaComponent == 0, "window.backgroundColor is clear")
                check(blurs.count == 1, "one NSVisualEffectView blending behind the window (found \(blurs.count))")
                if let blur = blurs.first {
                    check(blur.state == .active, "the blur stays active when the window is not key")
                    check(blur.material == GlassWindow.material, "the blur's material is the sidebar's, the most vivid")
                    check(blur.appearance?.name == .darkAqua, "the blur is dark")
                    check(blur.frame.size == host.bounds.size, "the blur fills the window (\(Int(blur.frame.width))x\(Int(blur.frame.height)))")
                }
                let tint = GlassWindowRecipe.tint(transparency: test.transparency ?? GlassWindowRecipe.defaultTransparency)
                check(abs(expected.tint - tint) < 0.0001 && tint >= GlassWindowRecipe.minimumTint, "light navy tint \(String(format: "%.2f", tint)), the text on plates of \(GlassWindowRecipe.plateOpacity)")
                check(subviews(of: host).contains { $0 is BackgroundView } == false, "no theme background drawn over the desktop")
                check(Look.current.rendering != .solid, "glass surfaces stay glass")
            } else {
                check(window.isOpaque, "window.isOpaque is true")
                check(window.backgroundColor == .black, "window.backgroundColor is black")
                check(blurs.isEmpty, "no blur behind the window")
                if test.theme.isGlass { check(Look.current.rendering == .solid, "solid surfaces") }
            }
            window.contentView = nil
            window.close()
        }
        Look.forceSolid = false

        // Full screen has no desktop behind the window: the desktop picture stands in for it.
        print("Full screen")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        GlassWindowState.shared.update(for: window)
        check(GlassWindowState.shared.fullScreen == false, "a window outside full screen draws no picture")
        if let picture = GlassWindowState.shared.wallpaper {
            check(Artwork.frost(picture) != nil, "the desktop picture reads and frosts: \(picture.path)")
        } else {
            let raw = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            print("  NOTE  no readable desktop picture (\(raw?.path ?? "none")): full screen falls back to the Glass blue")
        }
        window.close()

        print(failures == 0 ? "All checks passed." : "\(failures) checks failed.")
        return failures == 0 ? 0 : 1
    }

    private static func subviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(subviews(of:))
    }
}
