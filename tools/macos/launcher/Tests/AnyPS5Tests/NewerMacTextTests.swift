@testable import AnyPS5
import AnyPS5Core
import XCTest

/// An engine built for a newer macOS than this Mac's says so before it unlocks or starts a game,
/// in the launcher's language.
final class NewerMacTextTests: XCTestCase {
    override func setUp() {
        T.texts = T.load([T.sourceFolder])
    }

    func testTheEngineAndTheGameNameBothVersions() {
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertEqual(AppModel.newerMacText(SystemMinimum.Version(26, 0), running: SystemMinimum.Version(15, 7, 1)),
                       "This engine needs macOS 26.0 or newer and this Mac has macOS 15.7.1. Choose another engine in Settings › Engine or update macOS.")
        XCTAssertEqual(AppModel.gameNewerMacText("Astro Bot", SystemMinimum.Version(26, 0), running: SystemMinimum.Version(14, 6)),
                       "Astro Bot was unlocked with an engine that needs macOS 26.0 or newer and this Mac has macOS 14.6. Choose another engine for it in Settings › Engine and unlock it again.")
        T.language = .turkish
        XCTAssertEqual(AppModel.newerMacText(SystemMinimum.Version(26, 0), running: SystemMinimum.Version(15, 7, 1)),
                       "Bu motor macOS 26.0 ya da daha yenisini istiyor ama bu Mac'te macOS 15.7.1 var. Ayarlar › Motor'dan başka bir motor seçin ya da macOS'i güncelleyin.")
        XCTAssertTrue(AppModel.gameNewerMacText("Astro Bot", SystemMinimum.Version(26, 0), running: SystemMinimum.Version(14, 6)).hasPrefix("Astro Bot, macOS 26.0 "))
    }
}
