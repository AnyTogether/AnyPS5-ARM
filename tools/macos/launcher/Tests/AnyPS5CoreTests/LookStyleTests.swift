import XCTest
@testable import AnyPS5Core

final class LookStyleTests: XCTestCase {
    /// What the launcher keeps of the choice: the preferences hold the look by number.
    private struct Saved: Codable, Equatable {
        var theme: LookStyle
        var name: String
    }

    /// Preferences and theme files hold the look by number: the old ones keep theirs, Glass is 3.
    func testNumbersStayPut() {
        XCTAssertEqual(LookStyle.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(LookStyle.cosmic.rawValue, 0)
        XCTAssertEqual(LookStyle.sunset.rawValue, 2)
        XCTAssertEqual(LookStyle.glass.rawValue, 3)
        XCTAssertEqual(LookStyle.allCases.filter(\.isGlass), [.glass])
    }

    func testGlassIsSavedAndComesBack() throws {
        let data = try JSONEncoder().encode(Saved(theme: .glass, name: "Robin"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self).contains("\"theme\":3"), true)
        XCTAssertEqual(try JSONDecoder().decode(Saved.self, from: data), Saved(theme: .glass, name: "Robin"))
    }

    /// A number from a newer launcher is Cosmic, and the rest of the settings are kept.
    func testAnUnknownLookIsCosmicNotLostSettings() throws {
        let saved = try JSONDecoder().decode(Saved.self, from: Data(#"{"theme":42,"name":"Robin"}"#.utf8))
        XCTAssertEqual(saved, Saved(theme: .cosmic, name: "Robin"))
        XCTAssertEqual(LookStyle.style(-1), .cosmic)
        XCTAssertEqual(LookStyle.style(3), .glass)
    }

    /// A theme made in the Studio on Glass keeps Glass as its background.
    func testAStudioThemeCanBeGlass() throws {
        let (deep, middle, bright) = LookStyle.glass.palette
        var design = ThemeDesign(name: "Frost", author: "Utku", style: LookStyle.glass.rawValue,
                                 deep: ThemeDesign.hex(deep), middle: ThemeDesign.hex(middle), bright: ThemeDesign.hex(bright), accent: "#8AD8FF")
        XCTAssertEqual(design.deep, "#04101C")
        XCTAssertEqual(design.middle, "#1C4F73")
        XCTAssertEqual(design.bright, "#CFEFFF")
        var knobs = ThemeKnobs(design)
        knobs.hue += 10
        knobs.apply(to: &design)
        let back = try JSONDecoder().decode(ThemeDesign.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(LookStyle.style(back.style), .glass)
    }

    func testHowGlassIsDrawn() {
        XCTAssertEqual(GlassRendering.choose(reduceTransparency: false, liquidAvailable: true, offscreen: false), .liquid)
        XCTAssertEqual(GlassRendering.choose(reduceTransparency: false, liquidAvailable: false, offscreen: false), .frosted)
        // Liquid Glass draws nothing offscreen, so the previews get the drawn frost.
        XCTAssertEqual(GlassRendering.choose(reduceTransparency: false, liquidAvailable: true, offscreen: true), .frosted)
        XCTAssertEqual(GlassRendering.choose(reduceTransparency: true, liquidAvailable: true, offscreen: false), .solid)
        XCTAssertEqual(GlassRendering.choose(reduceTransparency: true, liquidAvailable: false, offscreen: true), .solid)
    }

    // MARK: Contrast (WCAG 2.1 AA: 4.5:1 for text, 3:1 for large text)

    typealias RGB = GlassRecipe.RGB
    let white = RGB(1, 1, 1)
    /// Key art can be anything: the brightest pixels are the worst case for white text.
    let backdrops = [RGB(1, 1, 1), RGB(1, 1, 0), RGB(0, 1, 1), RGB(1, 0.4, 0.3), RGB(0.5, 0.5, 0.5), RGB(0, 0, 0)]

    func testTheArithmeticIsWCAGs() {
        XCTAssertEqual(GlassRecipe.contrast(white, RGB(0, 0, 0)), 21, accuracy: 0.01)
        XCTAssertEqual(GlassRecipe.contrast(white, white), 1, accuracy: 0.0001)
        XCTAssertEqual(GlassRecipe.luminance(RGB(0.5, 0.5, 0.5)), 0.214, accuracy: 0.001)
    }

    func testWhiteTextReadsOnEveryGlassSurface() {
        for backdrop in backdrops {
            let surface = GlassRecipe.surface(over: backdrop)
            XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, surface), 4.5, "surface over \(backdrop)")
            // The card dropping in over a game, over any frame of it.
            let banner = GlassRecipe.over(white, GlassRecipe.sheenOpacity, GlassRecipe.over(GlassRecipe.surfaceBase, GlassRecipe.bannerOpacity, backdrop))
            XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, banner), 4.5, "banner over \(backdrop)")
            // A full-screen panel's frost.
            let screen = GlassRecipe.over(GlassRecipe.scrim, GlassRecipe.screenOpacity, backdrop)
            XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, screen), 4.5, "panel over \(backdrop)")
        }
    }

    /// The game's big title sits on the key art itself, under the scrim and the left-hand gradient.
    func testTheHeroTitleReadsOnTheKeyArt() {
        for backdrop in backdrops {
            let behind = GlassRecipe.over(GlassRecipe.scrim, 0.5, GlassRecipe.over(GlassRecipe.scrim, GlassRecipe.scrimOpacity, backdrop))
            XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, behind), 4.5, "title over \(backdrop)")
        }
    }

    func testInkReadsOnTheFocusedChip() {
        for backdrop in backdrops {
            XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(GlassRecipe.ink, GlassRecipe.chip(over: backdrop)), 7, "chip over \(backdrop)")
        }
    }

    func testSolidSurfacesForReduceTransparency() {
        XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, GlassRecipe.solid), 7)
    }

    /// Light accents (Ice, White) take dark ink on their badges; the darker ones keep white.
    func testInkOnAccents() {
        XCTAssertTrue(GlassRecipe.prefersDarkInk(on: RGB(0.54, 0.85, 1.0)))
        XCTAssertTrue(GlassRecipe.prefersDarkInk(on: RGB(0.94, 0.94, 0.94)))
        XCTAssertFalse(GlassRecipe.prefersDarkInk(on: RGB(0.2, 0.3, 0.8)))
        XCTAssertFalse(GlassRecipe.prefersDarkInk(on: RGB(0.6, 0.1, 0.2)))
    }

    // MARK: The see-through window

    /// Glass opens the window onto the desktop; Reduce Transparency, the slider at 0 % and every
    /// other look keep it opaque.
    func testOnlyGlassLetsTheDesktopThrough() {
        XCTAssertEqual(GlassWindowRecipe.make(glass: true, reduceTransparency: false, transparency: nil).translucent, true)
        XCTAssertEqual(GlassWindowRecipe.make(glass: true, reduceTransparency: true, transparency: nil), .opaque)
        XCTAssertEqual(GlassWindowRecipe.make(glass: true, reduceTransparency: false, transparency: 0), .opaque)
        XCTAssertEqual(GlassWindowRecipe.make(glass: false, reduceTransparency: false, transparency: 100), .opaque)
        XCTAssertEqual(GlassWindowRecipe.make(glass: true, reduceTransparency: false, transparency: nil).tint,
                       GlassWindowRecipe.tint(transparency: GlassWindowRecipe.defaultTransparency))
    }

    /// The slider runs from a solid pane down to the floor and never below it.
    func testTheTintRunsFromSolidToTheFloor() {
        XCTAssertEqual(GlassWindowRecipe.tint(transparency: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(GlassWindowRecipe.tint(transparency: 100), GlassWindowRecipe.tintFloor, accuracy: 0.0001)
        XCTAssertEqual(GlassWindowRecipe.tint(transparency: 250), GlassWindowRecipe.tintFloor, accuracy: 0.0001)
        XCTAssertGreaterThan(GlassWindowRecipe.tint(transparency: 40), GlassWindowRecipe.tint(transparency: 60))
        // A real see-through: more than a third of the desktop's light comes through at the floor.
        XCTAssertLessThan(GlassWindowRecipe.tintFloor, 0.66)
    }

    /// Whatever is behind the window (a white page, a snowy or a dark wallpaper), the text on the
    /// tinted desktop reads at every slider step, with no help from the blur.
    func testTextReadsOverAnyDesktopAtAnyTransparency() {
        for transparency in stride(from: 0, through: 100, by: 10) {
            let tint = GlassWindowRecipe.tint(transparency: transparency)
            for backdrop in backdrops {
                let behind = GlassRecipe.over(GlassRecipe.scrim, tint, backdrop)
                XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, behind), 4.5, "white at \(transparency) % over \(backdrop)")
                XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(GlassRecipe.over(white, 0.7, behind), behind), 3, "70 % white at \(transparency) % over \(backdrop)")
                // Glass surfaces on the tinted desktop, and the focused chip's ink.
                XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(white, GlassRecipe.surface(over: behind)), 4.5)
                XCTAssertGreaterThanOrEqual(GlassRecipe.contrast(GlassRecipe.ink, GlassRecipe.chip(over: behind)), 7)
            }
        }
    }

    /// The desktop picture is read only where macOS asks no permission for it.
    func testTheWallpaperIsReadOnlyWithoutAPrompt() {
        let home = URL(fileURLWithPath: "/Users/robin")
        XCTAssertTrue(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic"), home: home))
        XCTAssertTrue(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sequoia.heic"), home: home))
        XCTAssertTrue(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Users/robin/Pictures/lake.jpg"), home: home))
        XCTAssertTrue(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Users/robin/Desktopper/lake.jpg"), home: home))
        XCTAssertFalse(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Users/robin/Desktop/lake.jpg"), home: home))
        XCTAssertFalse(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Users/robin/Downloads/a/b.png"), home: home))
        XCTAssertFalse(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Users/robin/Library/Mobile Documents/com~apple~CloudDocs/x.heic"), home: home))
        XCTAssertFalse(GlassWindowRecipe.mayReadWallpaper(URL(fileURLWithPath: "/Volumes/USB/x.jpg"), home: home))
        XCTAssertFalse(GlassWindowRecipe.mayReadWallpaper(URL(string: "https://example.com/x.jpg")!, home: home))
    }
}
