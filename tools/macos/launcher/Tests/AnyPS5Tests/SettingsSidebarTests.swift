@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// Settings' categories on the left are taller than a small window: the list follows the
/// selection, so the selected category is whole on the screen without the mouse.
@MainActor
final class SettingsSidebarTests: XCTestCase {
    /// The list of categories: the scroll view furthest to the left.
    func sidebar(_ screen: LauncherWindow) throws -> NSScrollView {
        // Narrow and tall, unlike the rows beside it and the games behind it.
        let lists = screen.views(NSScrollView.self).filter { screen.frame($0).width < 400 && screen.frame($0).height > 150 }
            .sorted { screen.frame($0).minX < screen.frame($1).minX }
        return try XCTUnwrap(lists.first, "no list of categories in Settings: \(screen.views(NSScrollView.self).map { screen.frame($0) })")
    }

    /// The part of the list on the screen, from its top.
    func shown(_ list: NSScrollView) -> ClosedRange<CGFloat> {
        let visible = list.documentVisibleRect
        let height = list.documentView?.bounds.height ?? 0
        let top = list.documentView?.isFlipped == false ? height - visible.maxY : visible.minY
        return top...(top + visible.height)
    }

    func testTheCategoriesFollowTheSelectionDownAndUp() throws {
        let model = try LauncherFixture.model()
        model.open(.settings)
        let screen = try LauncherWindow(model, width: 1100, height: 700)
        defer { screen.close() }
        let count = model.panelCategories().count
        XCTAssertGreaterThan(count, 12)
        let list = try sidebar(screen)
        let total = list.documentView?.bounds.height ?? 0
        XCTAssertGreaterThan(total, list.documentVisibleRect.height + 60, "the categories have to be taller than the window for this test")
        let scale = min(1.45, max(0.68, min(1100.0 / 1600, 700.0 / 900)))
        /// Where a category's row is in the list.
        func row(_ index: Int) -> ClosedRange<CGFloat> {
            let top = (4 + CGFloat(index) * 58) * scale
            return top...(top + 52 * scale)
        }
        for index in 1..<count {
            XCTAssertTrue(model.panelCommand(.down))
            XCTAssertEqual(model.panelCategory, index)
            screen.wait(0.5)
            let visible = shown(list), wanted = row(index)
            XCTAssertTrue(visible.lowerBound <= wanted.lowerBound + 1 && wanted.upperBound <= visible.upperBound + 1,
                          "going down, category \(index) is at \(wanted) but the list shows \(visible)")
        }
        for index in stride(from: count - 2, through: 0, by: -1) {
            XCTAssertTrue(model.panelCommand(.up))
            screen.wait(0.5)
            let visible = shown(list), wanted = row(index)
            XCTAssertTrue(visible.lowerBound <= wanted.lowerBound + 1 && wanted.upperBound <= visible.upperBound + 1,
                          "going up, category \(index) is at \(wanted) but the list shows \(visible)")
        }
    }
}
