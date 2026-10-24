import AnyPS5Core
import XCTest

final class ListFocusTests: XCTestCase {
    func testTheFocusFollowsItsItem() {
        // Focused on "call-mira" (index 2); a game invite and its decline row arrive at the top.
        let before = ["me", "find", "call-mira", "add"]
        let after = ["invite-s1", "decline-s1", "me", "find", "call-mira", "add"]
        XCTAssertEqual(ListFocus.index(of: before[2], in: after, fallback: 2), 4)
        // Rows above it went away.
        XCTAssertEqual(ListFocus.index(of: "call-mira", in: ["call-mira", "add"], fallback: 2), 0)
    }

    func testAnItemThatWentKeepsThePlace() {
        XCTAssertEqual(ListFocus.index(of: "accept-f1", in: ["me", "find", "add"], fallback: 1), 1)
        XCTAssertEqual(ListFocus.index(of: "accept-f1", in: ["me", "find"], fallback: 5), 1)
        XCTAssertEqual(ListFocus.index(of: nil, in: ["me", "find"], fallback: 1), 1)
        XCTAssertEqual(ListFocus.index(of: "x", in: [], fallback: 3), 0)
    }
}
