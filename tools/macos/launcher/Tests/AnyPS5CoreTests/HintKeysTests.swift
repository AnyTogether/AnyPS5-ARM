import XCTest
@testable import AnyPS5Core

final class HintKeysTests: XCTestCase {
    /// A pill whose glyphs all mean one thing is one button giving that command.
    func testAPillOfOneCommandIsOneButton() {
        XCTAssertEqual(HintKeys.single("↩ / ✕"), .select)
        XCTAssertEqual(HintKeys.single("esc / ○"), .back)
        XCTAssertEqual(HintKeys.single("O / △"), .options)
        XCTAssertEqual(HintKeys.single("PS"), .home)
    }

    /// The arrows, Q and E, or arrows beside Enter: each glyph is a button of its own.
    func testAPillOfSeveralCommandsIsNoSingleButton() {
        XCTAssertNil(HintKeys.single("← → ↑ ↓"))
        XCTAssertNil(HintKeys.single("Q E / L1 R1"))
        XCTAssertNil(HintKeys.single("← → ↩ / ✕"))
        XCTAssertNil(HintKeys.single("PS / esc / ○"))
    }

    func testEveryGlyphGivesTheCommandOfItsKey() {
        XCTAssertEqual(HintKeys.tokens("← → ↑ ↓").map(\.command), [.left, .right, .up, .down])
        XCTAssertEqual(HintKeys.tokens("Q E / L1 R1"), [
            .init("Q", .previousGame), .init("E", .nextGame), .init("/", nil), .init("L1", .previousGame), .init("R1", .nextGame),
        ])
        XCTAssertEqual(HintKeys.tokens("← → ↩ / ✕").map(\.command), [.left, .right, .select, nil, .select])
        XCTAssertEqual(HintKeys.tokens("PS / esc / ○").map(\.command), [.home, nil, .back, nil, .back])
    }

    /// The pills name the same keys Input reads: O options, Q and E the games, Esc back.
    func testTheGlyphsAgreeWithTheKeys() {
        XCTAssertEqual(HintKeys.command(for: "o"), .options)
        XCTAssertEqual(HintKeys.command(for: "Q"), .previousGame)
        XCTAssertEqual(HintKeys.command(for: "E"), .nextGame)
        XCTAssertEqual(HintKeys.command(for: "esc"), .back)
        XCTAssertNil(HintKeys.command(for: "/"))
        XCTAssertNil(HintKeys.command(for: "F12"))
    }

    /// Every hint the launcher draws, so that a new glyph without a command is caught here.
    func testEveryHintTheLauncherShowsIsClickable() {
        let shown = ["← → ↑ ↓", "Q E / L1 R1", "↩ / ✕", "esc / ○", "O / △", "↑ ↓", "← →", "← → ↩ / ✕", "PS / esc / ○", "PS"]
        for keys in shown {
            let tokens = HintKeys.tokens(keys)
            XCTAssertFalse(tokens.contains { $0.text != "/" && $0.command == nil }, "\(keys) has a glyph a click cannot press")
        }
    }
}
