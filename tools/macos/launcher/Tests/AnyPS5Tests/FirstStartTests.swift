@testable import AnyPS5
import AnyPS5Core
import AppKit
import MetalKit
import SwiftUI
import XCTest

/// The first start as it comes up, before any key: every language and every theme is on the
/// screen, the arrows move through them and the choice is the one kept.
@MainActor
final class FirstStartTests: XCTestCase {
    func fresh(_ language: Language = .english) throws -> AppModel {
        try LauncherFixture.model(games: 1) {
            $0.onboarded = false
            $0.libraryFolders = []
            $0.language = language
        }
    }

    /// ANYPS5_TEST_SHOTS=<folder> keeps the screens the tests draw (CI uploads them).
    var shots: URL? {
        guard let folder = ProcessInfo.processInfo.environment["ANYPS5_TEST_SHOTS"], !folder.isEmpty else { return nil }
        let url = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testTheLanguageStepFitsTheWindowWithEveryLanguage() throws {
        let model = try fresh()
        XCTAssertGreaterThan(Language.allCases.count, 20, "the built-in languages")
        let host = NSHostingView(rootView: OnboardingView().environmentObject(model).environment(\.scale, 1))
        let wanted = host.fittingSize
        XCTAssertLessThanOrEqual(wanted.width, 1600, "the step asks for more width than the window has: its cards run off the screen")
        XCTAssertLessThanOrEqual(wanted.height, 900)
    }

    func testTheThemeStepFitsTheWindow() throws {
        let model = try fresh()
        model.onboardingStep = 1
        let host = NSHostingView(rootView: OnboardingView().environmentObject(model).environment(\.scale, 1))
        XCTAssertLessThanOrEqual(host.fittingSize.width, 1600)
    }

    func testTheArrowsMoveThroughTheLanguagesAndTheChoiceIsKept() throws {
        let model = try fresh()
        let languages = Language.allCases
        XCTAssertEqual(model.onboardingChoice, languages.firstIndex(of: .english), "the language it starts in is the one chosen")
        model.onboardingChoice = 0
        XCTAssertTrue(model.onboardingCommand(.right))
        XCTAssertEqual(model.onboardingChoice, 1)
        XCTAssertEqual(model.preferences.language, languages[1], "the step is drawn in the language the selection is on")
        XCTAssertTrue(model.onboardingCommand(.down))
        XCTAssertEqual(model.onboardingChoice, 8, "down goes a row of seven down")
        XCTAssertEqual(model.preferences.language, languages[8])
        XCTAssertTrue(model.onboardingCommand(.up))
        XCTAssertEqual(model.onboardingChoice, 1)
        XCTAssertTrue(model.onboardingCommand(.up))
        XCTAssertEqual(model.onboardingChoice, 1, "no row above the first")
        model.onboardingChoice = languages.count - 1
        XCTAssertTrue(model.onboardingCommand(.down))
        XCTAssertEqual(model.onboardingChoice, languages.count - 1, "no row under the last")
        let turkish = try XCTUnwrap(languages.firstIndex(of: .turkish))
        model.onboardingChoice = turkish
        XCTAssertTrue(model.onboardingCommand(.select))
        XCTAssertEqual(model.preferences.language, .turkish)
        XCTAssertEqual(model.onboardingStep, 1)
    }

    func testTheArrowsMoveThroughTheThemesAndTheChoiceIsKept() throws {
        let model = try fresh()
        model.onboardingStep = 1
        XCTAssertEqual(model.onboardingChoice, model.preferences.theme.rawValue)
        model.onboardingChoice = 0
        XCTAssertTrue(model.onboardingCommand(.right))
        XCTAssertEqual(model.preferences.theme, Theme(rawValue: 1), "the theme under the selection is shown at once")
        XCTAssertTrue(model.onboardingCommand(.right))
        XCTAssertTrue(model.onboardingCommand(.select))
        XCTAssertEqual(model.preferences.theme, Theme(rawValue: 2))
        XCTAssertEqual(model.onboardingStep, 2)
        XCTAssertTrue(model.onboardingCommand(.back))
        XCTAssertEqual(model.onboardingStep, 1)
        XCTAssertEqual(model.onboardingChoice, 2, "back on the step, the choice is where it was left")
    }

    /// A theme card that is not the selected one is a paused background: it has to draw its
    /// picture without ever having been the selected one.
    func testAThemeCardNotSelectedDrawsItsPicture() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal device here") }
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 330, height: 186)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: frame)
        window.contentView = content
        // As SwiftUI makes it: configured (paused) before it has a size or a window.
        let card = BackgroundView()
        card.configure(theme: .aurora, paused: true, speed: 1)
        let selected = BackgroundView()
        selected.configure(theme: .cosmic, paused: false, speed: 1)
        card.frame = NSRect(x: 0, y: 0, width: 165, height: 186)
        selected.frame = NSRect(x: 165, y: 0, width: 165, height: 186)
        content.addSubview(card)
        content.addSubview(selected)
        // On CI the window is shown, so the system's own display pass is what is tested; elsewhere
        // no window may come up, and the offscreen layout and display stand in for it.
        let shown = ProcessInfo.processInfo.environment["CI"] == "true"
        if shown { window.orderFrontRegardless() }
        defer { window.orderOut(nil) }
        for _ in 0..<12 {
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        print("theme cards: window shown \(shown), selected drew \(selected.frames) frames, the paused card \(card.frames)")
        XCTAssertGreaterThan(card.frames, 0, "a paused card drew nothing (the selected one drew \(selected.frames) frames, window shown: \(shown))")
    }

    /// The four screens as they come up, in English and in Turkish, kept as pictures when
    /// ANYPS5_TEST_SHOTS says where.
    func testTheFirstStartScreensDraw() throws {
        let still = BackgroundView.still(theme: .cosmic, width: 1600, height: 900, time: 200) ?? NSImage(size: NSSize(width: 16, height: 9), flipped: false) { rect in
            NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.14, alpha: 1).setFill()
            rect.fill()
            return true
        }
        for theme in Theme.allCases where PreviewRenderer.stills[theme] == nil {
            PreviewRenderer.stills[theme] = BackgroundView.still(theme: theme, width: 660, height: 372, time: 200)
        }
        let folder = shots ?? FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-first-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for language in [Language.english, .turkish] {
            let model = try fresh(language)
            for step in 0..<2 {
                let file = folder.appendingPathComponent("first-start-\(step == 0 ? "language" : "theme")-\(language.code).png")
                PreviewRenderer.render(model.preferences, [], URL(fileURLWithPath: NSTemporaryDirectory()), still, file) { $0.onboardingStep = step }
                let size = try XCTUnwrap(NSImage(contentsOf: file)?.representations.first, "no picture of step \(step) in \(language.code)")
                XCTAssertEqual(size.pixelsWide, Int(PreviewRenderer.size.width))
            }
        }
    }
}
