@testable import AnyPS5
import AnyPS5Core
import XCTest

/// Captures updating live from the socket: a friend's new post, counts that changed and a post
/// taken down, with the focus staying on the post it was on.
@MainActor
final class CapturesLiveTests: XCTestCase {
    static let mira = TogetherPerson(userId: "f1", handle: "mira", displayName: "Mira", avatar: nil)

    func post(_ id: String, likes: Int = 1) -> TogetherPost {
        TogetherPost(id: id, author: Self.mira, media: [], likes: likes, createdAt: Date())
    }

    func event(_ type: String, _ data: [String: Any]) throws -> TogetherSocket.Event {
        TogetherSocket.Event(id: UUID().uuidString, type: type, json: try JSONSerialization.data(withJSONObject: data))
    }

    func postJSON(_ id: String) -> [String: Any] {
        ["id": id, "author": ["userId": "f1", "handle": "mira", "displayName": "Mira", "avatar": NSNull()], "caption": NSNull(), "visibility": "friends",
         "commentsOff": false, "game": NSNull(), "media": [], "likes": 0, "liked": false, "comments": 0, "mine": false, "source": "launcher",
         "createdAt": "2026-11-09T10:00:00.000Z", "editedAt": NSNull()]
    }

    func model(_ posts: [TogetherPost]) throws -> AppModel {
        let model = try LauncherFixture.model()
        model.captures.feed.load(TogetherPostPage(items: posts, next: nil))
        return model
    }

    func testANewPostGoesOnTopAndTheFocusStays() throws {
        let model = try model([post("0002"), post("0001")])
        model.captures.index = 1
        model.togetherEvent(try event("post.new", postJSON("0003")))
        XCTAssertEqual(model.captures.feed.items.map(\.id), ["0003", "0002", "0001"])
        XCTAssertEqual(model.focusedCapture?.id, "0001", "still the same post")
        XCTAssertEqual(model.captures.index, 2)
    }

    func testCountsAndARemovedPost() throws {
        let model = try model([post("0003"), post("0002"), post("0001")])
        model.captures.index = 2
        model.togetherEvent(try event("post.counts", ["postId": "0001", "likes": 8, "comments": 2]))
        XCTAssertEqual(model.focusedCapture?.likes, 8)
        XCTAssertEqual(model.focusedCapture?.comments, 2)

        model.togetherEvent(try event("post.removed", ["postId": "0002"]))
        XCTAssertEqual(model.focusedCapture?.id, "0001", "one above it went: the focus stays on it")

        model.captures.action = 2
        model.togetherEvent(try event("post.removed", ["postId": "0001"]))
        XCTAssertEqual(model.focusedCapture?.id, "0003", "the focused post went: the one that takes its place")
        XCTAssertEqual(model.captures.index, 0)
        XCTAssertEqual(model.captures.action, 0)
    }

    func testAFeedNotReadYetIsLeftAlone() throws {
        let model = try LauncherFixture.model()
        XCTAssertFalse(model.captures.feed.loaded)
        model.togetherEvent(try event("post.new", postJSON("0001")))
        XCTAssertFalse(model.captures.feed.loaded, "the first read brings it anyway")
        XCTAssertTrue(model.captures.feed.items.isEmpty)
    }
}
