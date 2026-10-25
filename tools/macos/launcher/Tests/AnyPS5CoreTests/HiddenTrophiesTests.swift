import Foundation
import XCTest
@testable import AnyPS5Core

final class HiddenTrophiesTests: XCTestCase {
    private func trophy(_ number: Int, hidden: Bool, earned: Bool = false) -> TrophySet.Trophy {
        TrophySet.Trophy(serviceLabel: 0, number: number, grade: .bronze, hidden: hidden, name: "Name \(number)", detail: "Detail", icon: nil,
                         unlocked: earned ? Date(timeIntervalSince1970: 1_700_000_000) : nil, progress: nil)
    }

    func testAHiddenTrophyStaysHiddenUntilShown() {
        var hidden = HiddenTrophies(always: false)
        let secret = trophy(3, hidden: true)
        XCTAssertTrue(hidden.secret(secret, game: "PPSA01234"))
        XCTAssertTrue(hidden.toggle(secret, game: "PPSA01234"))
        XCTAssertFalse(hidden.secret(secret, game: "PPSA01234"))
        XCTAssertTrue(hidden.secret(secret, game: "PPSA09999"), "showing it in one game's list shows nothing in another's")
        XCTAssertTrue(hidden.toggle(secret, game: "PPSA01234"))
        XCTAssertTrue(hidden.secret(secret, game: "PPSA01234"), "△ again hides it")
    }

    func testOnlyAHiddenTrophyNotEarnedCanBeShown() {
        var hidden = HiddenTrophies(always: false)
        XCTAssertFalse(hidden.toggle(trophy(1, hidden: false), game: "g"))
        XCTAssertFalse(hidden.toggle(trophy(2, hidden: true, earned: true), game: "g"))
        XCTAssertFalse(hidden.secret(trophy(2, hidden: true, earned: true), game: "g"))
        XCTAssertFalse(hidden.secret(trophy(1, hidden: false), game: "g"))
        XCTAssertEqual(hidden.shown, [])
    }

    func testTheSettingShowsEveryHiddenTrophy() {
        var hidden = HiddenTrophies(always: true)
        let secret = trophy(4, hidden: true)
        XCTAssertFalse(hidden.secret(secret, game: "g"))
        XCTAssertFalse(hidden.canToggle(secret))
        XCTAssertFalse(hidden.toggle(secret, game: "g"), "nothing to show or hide with the setting on")
    }

    func testAnEarnedTrophyIsNeverSecret() {
        // Earned while hidden: its name, description and icon show, whatever was chosen before.
        let earned = trophy(5, hidden: true, earned: true)
        for always in [false, true] {
            var hidden = HiddenTrophies(always: always, shown: [HiddenTrophies.key(game: "g", trophy: earned)])
            XCTAssertFalse(hidden.secret(earned, game: "g"), "always \(always)")
            XCTAssertFalse(hidden.secret(earned, game: "other"), "always \(always)")
            XCTAssertFalse(hidden.toggle(earned, game: "g"), "nothing to hide again")
        }
        // Only the unearned hidden one is masked.
        let hidden = HiddenTrophies(always: false)
        let list = [trophy(1, hidden: false), trophy(2, hidden: true), trophy(3, hidden: true, earned: true), trophy(4, hidden: false, earned: true)]
        XCTAssertEqual(list.filter { hidden.secret($0, game: "g") }.map(\.number), [2])
    }
}
