import XCTest
@testable import AnyPS5Core

final class TogetherPostsTests: TogetherSignedInCase {
    static let ayse: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull()]
    static let me: [String: Any] = ["userId": "u1", "handle": "utku", "displayName": "Utku", "avatar": "https://cdn.test/u.webp", "privateName": "Utku H."]

    static func image(_ id: String) -> [String: Any] {
        ["id": id, "kind": "image", "width": 1920, "height": 1080, "durationMs": NSNull(),
         "url": "https://cdn.test/\(id).webp?sig=1", "thumb": "https://cdn.test/\(id)-640.webp?sig=1", "poster": NSNull()]
    }

    static func clip(_ id: String, ms: Int = 42_000) -> [String: Any] {
        ["id": id, "kind": "clip", "width": 1280, "height": 720, "durationMs": ms,
         "url": "https://cdn.test/\(id).mp4?sig=1", "thumb": NSNull(), "poster": "https://cdn.test/\(id)-poster.jpg?sig=1"]
    }

    static func post(_ id: String, author: [String: Any] = ayse, media: [[String: Any]]? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var post: [String: Any] = [
            "id": id, "author": author, "caption": "Night walk", "visibility": "friends", "commentsOff": false,
            "game": ["titleId": "PPSA01234", "names": ["en": "Stray", "tr": "Stray TR"], "iconUrl": NSNull()],
            "media": media ?? [image("m-\(id)")], "likes": 3, "liked": false, "comments": 2, "mine": false,
            "source": "launcher", "createdAt": "2026-10-26T10:00:00.000Z", "editedAt": NSNull(),
        ]
        post.merge(extra) { _, new in new }
        return post
    }

    static func comment(_ id: String, post: String = "p1", replyTo: Any = NSNull(), canDelete: Bool = false, replies: [[String: Any]]? = nil) -> [String: Any] {
        var comment: [String: Any] = ["id": id, "postId": post, "author": ayse, "text": "GG \(id)", "replyTo": replyTo,
                                      "createdAt": "2026-10-26T11:00:00Z", "canDelete": canDelete]
        if let replies { comment["replies"] = replies }
        return comment
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder.together.decode(type, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: Decoding

    func testAPostWithPicturesDecodes() throws {
        let post = try Self.decode(TogetherPost.self, Self.post("p1", media: [Self.image("a"), Self.image("b")]))
        XCTAssertEqual(post.id, "p1")
        XCTAssertEqual(post.author.handle, "ayse")
        XCTAssertNil(post.author.avatar)
        XCTAssertEqual(post.caption, "Night walk")
        XCTAssertEqual(post.game?.titleId, "PPSA01234")
        XCTAssertEqual(post.game?.name(in: "tr"), "Stray TR")
        XCTAssertEqual(post.visibility, .friends)
        XCTAssertEqual(post.media.map(\.id), ["a", "b"])
        XCTAssertEqual(post.media[0].still, "https://cdn.test/a-640.webp?sig=1", "a picture shows its thumbnail")
        XCTAssertEqual(post.media[0].aspect ?? 0, 16 / 9, accuracy: 0.001)
        XCTAssertNil(post.clip)
        XCTAssertEqual(post.likes, 3)
        XCTAssertFalse(post.liked)
        XCTAssertEqual(post.comments, 2)
        XCTAssertEqual(post.source, "launcher")
        XCTAssertNil(post.editedAt)
        XCTAssertEqual(post.createdAt, ISO8601DateFormatter().date(from: "2026-10-26T10:00:00Z"))
    }

    func testAClipPostAndFieldsLeftOut() throws {
        var json = Self.post("p2", author: Self.me, media: [Self.clip("c")], extra: ["visibility": "public", "mine": true, "caption": NSNull(), "game": NSNull(), "source": NSNull()])
        json.removeValue(forKey: "commentsOff")
        json.removeValue(forKey: "editedAt")
        let post = try Self.decode(TogetherPost.self, json)
        XCTAssertEqual(post.visibility, .public)
        XCTAssertTrue(post.mine)
        XCTAssertNil(post.caption)
        XCTAssertNil(post.game)
        XCTAssertNil(post.source)
        XCTAssertFalse(post.commentsOff)
        XCTAssertEqual(post.author.privateName, "Utku H.")
        XCTAssertEqual(post.clip?.durationMs, 42_000)
        XCTAssertEqual(post.clip?.still, "https://cdn.test/c-poster.jpg?sig=1", "a clip shows its poster")
    }

    func testUnknownVisibilityAndHiddenMedia() throws {
        var hidden = Self.image("h")
        hidden["hidden"] = true
        let post = try Self.decode(TogetherPost.self, Self.post("p3", media: [Self.image("a"), hidden], extra: ["visibility": "circle"]))
        XCTAssertEqual(post.visibility, .friends, "a visibility this launcher does not know reads as the narrower one")
        XCTAssertEqual(post.shown.map(\.id), ["a"])
    }

    func testCommentsWithOneLevelOfReplies() throws {
        let page = try Self.decode(TogetherCommentPage.self, ["items": [
            Self.comment("c2", canDelete: true, replies: [Self.comment("r1", replyTo: "c2"), Self.comment("r2", replyTo: "c2", canDelete: true)]),
            Self.comment("c1"),
        ], "next": "c1"])
        XCTAssertEqual(page.next, "c1")
        XCTAssertEqual(page.items.map(\.id), ["c2", "c1"])
        XCTAssertTrue(page.items[0].canDelete)
        XCTAssertEqual(page.items[0].replies.map(\.id), ["r1", "r2"])
        XCTAssertEqual(page.items[0].replies[0].replyTo, "c2")
        XCTAssertNil(page.items[0].replyTo)
        XCTAssertEqual(page.items[1].replies, [], "no replies key reads as none")
        XCTAssertEqual(page.items[0].text, "GG c2")
    }

    // MARK: Requests

    func testPostingSendsTheDraft() async throws {
        FakeTogether.handler = { _, _ in (201, Self.post("p9", author: Self.me, extra: ["mine": true])) }
        let draft = TogetherPostDraft(caption: "  Look at this  ", visibility: .public, titleId: "PPSA01234")
        let post = try await client.createPost(media: ["m1"], draft: draft)
        XCTAssertEqual(last(), "POST /api/v1/posts")
        let sent = try XCTUnwrap(body())
        XCTAssertEqual(sent["media"] as? [String], ["m1"])
        XCTAssertEqual(sent["caption"] as? String, "Look at this")
        XCTAssertEqual(sent["visibility"] as? String, "public")
        XCTAssertEqual(sent["titleId"] as? String, "PPSA01234")
        XCTAssertEqual(sent["source"] as? String, "launcher")
        XCTAssertNil(sent["commentsOff"])
        XCTAssertTrue(post.mine)
    }

    func testTheDraftsBody() {
        let plain = TogetherPostDraft(titleId: "CUSA1")
        let body = plain.body(media: ["m1"])
        XCTAssertEqual(body["visibility"] as? String, "friends", "Friends unless Public is picked")
        XCTAssertNil(body["caption"], "an empty caption is left out")
        XCTAssertNil(body["titleId"], "a title ID the server would refuse is left out")
        XCTAssertEqual(body["source"] as? String, "launcher")
        let long = TogetherPostDraft(caption: String(repeating: "a", count: 600), commentsOff: true).body(media: ["m1"])
        XCTAssertEqual((long["caption"] as? String)?.count, 500)
        XCTAssertEqual(long["commentsOff"] as? Bool, true)
        XCTAssertTrue(TogetherPostDraft.isTitleId("PPSA12544"))
        XCTAssertFalse(TogetherPostDraft.isTitleId("ppsa12544"))
    }

    func testTheCapturesFeedPages() async throws {
        FakeTogether.handler = { _, _ in (200, ["items": [Self.post("p2"), Self.post("p1")], "next": "p1"]) }
        let first = try await client.captures()
        XCTAssertEqual(last(), "GET /api/v1/me/captures")
        XCTAssertEqual(first.items.map(\.id), ["p2", "p1"])
        XCTAssertEqual(first.next, "p1")
        FakeTogether.handler = { _, _ in (200, ["items": [], "next": NSNull()]) }
        let older = try await client.captures(before: "p1", limit: 20)
        XCTAssertEqual(last(), "GET /api/v1/me/captures?before=p1&limit=20")
        XCTAssertNil(older.next)
    }

    func testLikingAndTakingItBack() async throws {
        FakeTogether.handler = { _, _ in (200, ["likes": 4, "liked": true]) }
        let liked = try await client.setLiked(true, post: "p1")
        XCTAssertEqual(last(), "PUT /api/v1/posts/p1/like")
        XCTAssertEqual(liked, TogetherLikes(likes: 4, liked: true))
        FakeTogether.handler = { _, _ in (200, ["likes": 3, "liked": false]) }
        let unliked = try await client.setLiked(false, post: "p1")
        XCTAssertEqual(last(), "DELETE /api/v1/posts/p1/like")
        XCTAssertFalse(unliked.liked)
    }

    func testCommentRequests() async throws {
        FakeTogether.handler = { _, _ in (200, ["items": [Self.comment("c1")], "next": NSNull()]) }
        _ = try await client.comments(on: "p1")
        XCTAssertEqual(last(), "GET /api/v1/posts/p1/comments")
        _ = try await client.comments(on: "p1", before: "c5")
        XCTAssertEqual(last(), "GET /api/v1/posts/p1/comments?before=c5")

        FakeTogether.handler = { _, _ in (201, Self.comment("r1", replyTo: "c1", canDelete: true)) }
        let reply = try await client.comment(on: "p1", text: " Nice one \n", replyTo: "c1")
        XCTAssertEqual(last(), "POST /api/v1/posts/p1/comments")
        XCTAssertEqual(body()?["text"] as? String, "Nice one")
        XCTAssertEqual(body()?["replyTo"] as? String, "c1")
        XCTAssertEqual(reply.replyTo, "c1")
        _ = try await client.comment(on: "p1", text: "top")
        XCTAssertNil(body()?["replyTo"])

        FakeTogether.handler = { _, _ in (204, [String: Any]()) }
        try await client.deleteComment("c1", on: "p1")
        XCTAssertEqual(last(), "DELETE /api/v1/posts/p1/comments/c1")
        try await client.deletePost("p1")
        XCTAssertEqual(last(), "DELETE /api/v1/posts/p1")
    }

    // MARK: The clip limit

    func testTheClipLimit() {
        let mib = 1_048_576
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 30_000, bytes: 10 * mib), .fits)
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 60_000, bytes: 25 * mib), .fits, "exactly the limits fit")
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 60_400, bytes: mib), .fits, "a frame late is still taken")
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 61_000, bytes: mib), .tooLong(ms: 61_000))
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 90_000, bytes: 40 * mib), .tooLong(ms: 90_000), "too long is said before too big")
        XCTAssertEqual(TogetherClipCheck.check(durationMs: 20_000, bytes: 26 * mib), .tooBig(bytes: 26 * mib))
        XCTAssertEqual(TogetherClipCheck.check(durationMs: nil, bytes: 5 * mib, maxBytes: 4 * mib), .tooBig(bytes: 5 * mib), "the server's own limit counts")
        XCTAssertTrue(TogetherClipCheck.tooLong(ms: 61_000).blocks)
        XCTAssertFalse(TogetherClipCheck.tooBig(bytes: 26 * mib).blocks, "a big clip is made smaller first")
        XCTAssertFalse(TogetherClipCheck.fits.blocks)
    }

    // MARK: Refusals

    func testRefusalsByCode() async throws {
        func refusal(_ status: Int, _ json: [String: Any]) async -> TogetherPostRefusal? {
            // Problem details as the server sends them: the status inside too.
            let problem = json.merging(["status": status]) { old, _ in old }
            FakeTogether.handler = { _, _ in (status, problem) }
            do {
                _ = try await client.createPost(media: ["m1"], draft: TogetherPostDraft())
                return nil
            } catch {
                return TogetherPostRefusal(error)
            }
        }
        let cases: [(Int, [String: Any], TogetherPostRefusal)] = [
            (403, ["code": "comments_off", "title": "Comments are off"], .commentsOff),
            (400, ["code": "link_blocked", "title": "Links to x are not allowed", "domain": "x.test"], .linkBlocked),
            (403, ["code": "account_muted", "title": "Muted"], .accountMuted),
            (403, ["code": "restricted_by_family", "title": "Off", "feature": "media_sharing"], .family(.mediaSharing)),
            (403, ["code": "restricted_by_family", "title": "Friends", "feature": "profile_visibility"], .family(.profileVisibility)),
            (403, ["code": "restricted_by_family", "title": "Family"], .family(.family)),
            (429, ["code": "rate_limited", "title": "Slow down"], .rateLimited),
            (503, ["code": "storage_disabled", "title": "No files"], .storageDisabled),
            (400, ["code": "bad_media", "title": "At most 60 seconds", "maxMs": 60_000, "maxBytes": 26_214_400], .clipTooLong),
            (400, ["code": "bad_media", "title": "Damaged"], .badMedia),
            (413, ["code": "quota_exceeded", "title": "Full", "used": 1, "limit": 2, "needed": 3], .quotaFull),
            (404, ["code": "not_found", "title": "No such post"], .gone),
        ]
        for (status, json, expected) in cases {
            let got = await refusal(status, json)
            XCTAssertEqual(got, expected, "\(json["code"] ?? "")")
        }
        let other = await refusal(400, ["code": "bad_request", "title": "media: one to four pictures"])
        XCTAssertNil(other, "anything else is said as the server put it")
        XCTAssertNil(TogetherPostRefusal(URLError(.notConnectedToInternet)))
    }

    // MARK: The feed and the comments as held

    func testTheFeedPagesAndLikesAtOnce() throws {
        var feed = TogetherCaptures()
        feed.load(try Self.decode(TogetherPostPage.self, ["items": [Self.post("0003"), Self.post("0002")], "next": "0002"]))
        XCTAssertTrue(feed.loaded)
        XCTAssertEqual(feed.next, "0002")
        feed.loadOlder(try Self.decode(TogetherPostPage.self, ["items": [Self.post("0002"), Self.post("0001")], "next": NSNull()]))
        XCTAssertEqual(feed.items.map(\.id), ["0003", "0002", "0001"], "a post read twice is kept once")
        XCTAssertNil(feed.next)
        feed.upsert(try Self.decode(TogetherPost.self, Self.post("0004")))
        XCTAssertEqual(feed.items.first?.id, "0004", "a new post goes on top")

        let before = feed.toggleLike("0003")
        XCTAssertEqual(before, TogetherLikes(likes: 3, liked: false))
        XCTAssertEqual(feed.items[1].likes, 4)
        XCTAssertTrue(feed.items[1].liked)
        feed.setLikes(try XCTUnwrap(before), for: "0003")
        XCTAssertEqual(feed.items[1].likes, 3, "a failure puts the likes back")
        XCTAssertFalse(feed.items[1].liked)
        XCTAssertNil(feed.toggleLike("nope"))

        feed.addComments(1, to: "0003")
        XCTAssertEqual(feed.items[1].comments, 3)
        feed.addComments(-5, to: "0003")
        XCTAssertEqual(feed.items[1].comments, 0)
        feed.remove("0003")
        XCTAssertNil(feed.index(of: "0003"))
    }

    func testTheCommentThread() throws {
        var thread = TogetherCommentThread(postId: "p1")
        thread.load(try Self.decode(TogetherCommentPage.self, ["items": [
            Self.comment("c2", replies: [Self.comment("r1", replyTo: "c2")]),
            Self.comment("c1"),
        ], "next": "c1"]))
        XCTAssertEqual(thread.lines.map(\.id), ["c2", "r1", "c1"])
        XCTAssertEqual(thread.lines.map(\.isReply), [false, true, false])
        XCTAssertEqual(thread.lines[1].parent, "c2")

        thread.loadOlder(try Self.decode(TogetherCommentPage.self, ["items": [Self.comment("c1"), Self.comment("c0")], "next": NSNull()]))
        XCTAssertEqual(thread.items.map(\.id), ["c2", "c1", "c0"])
        XCTAssertNil(thread.next)

        thread.add(try Self.decode(TogetherComment.self, Self.comment("c3", canDelete: true)))
        thread.add(try Self.decode(TogetherComment.self, Self.comment("r2", replyTo: "c2", canDelete: true)))
        thread.add(try Self.decode(TogetherComment.self, Self.comment("r2", replyTo: "c2", canDelete: true)))
        XCTAssertEqual(thread.lines.map(\.id), ["c3", "c2", "r1", "r2", "c1", "c0"], "a new comment on top, a reply last under its own")

        XCTAssertEqual(thread.remove("r1"), 1)
        XCTAssertEqual(thread.remove("c2"), 2, "a top-level comment takes its replies with it")
        XCTAssertEqual(thread.remove("nope"), 0)
        XCTAssertEqual(thread.lines.map(\.id), ["c3", "c1", "c0"])
        XCTAssertEqual(thread.comment("c3")?.canDelete, true)
    }
}
