import XCTest
@testable import AnyPS5Core

final class DeepLinkTests: XCTestCase {
    func link(_ text: String) -> DeepLink? { URL(string: text).flatMap(DeepLink.init) }

    func testAGameLinkSelectsItAndAPlayLinkPlaysIt() {
        XCTAssertEqual(link("anyps5://game/PPSA15065"), .game("PPSA15065"))
        XCTAssertEqual(link("anyps5://play/PPSA12544"), .play("PPSA12544"))
        XCTAssertEqual(link("ANYPS5://GAME/ppsa15065/"), .game("PPSA15065"), "case and a trailing slash do not matter")
    }

    func testTheLibraryAndSettingsOpen() {
        XCTAssertEqual(link("anyps5://library"), .library)
        XCTAssertEqual(link("anyps5://settings"), .settings)
    }

    func testOtherLinksAreNotOurs() {
        XCTAssertNil(link("https://example.com/game/PPSA15065"))
        XCTAssertNil(link("anyps5://game/"))
        XCTAssertNil(link("anyps5://game/../../etc"))
        XCTAssertNil(link("anyps5://delete/PPSA15065"))
    }

    func testALinkIsWrittenTheWayItIsRead() {
        XCTAssertEqual(DeepLink.game("PPSA15065").url.absoluteString, "anyps5://game/PPSA15065")
        XCTAssertEqual(DeepLink(url: DeepLink.play("CUSA00001").url), .play("CUSA00001"))
    }
}
