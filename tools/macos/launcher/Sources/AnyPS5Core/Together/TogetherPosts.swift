import Foundation

/// Captures on AnyTogether: screenshots and clips players share as posts, liked and commented on
/// by the people who may see them. A post holds one to four pictures or one clip, uploaded first
/// as media (`uploadMedia`); the server decides on every read who sees what.

/// Who sees a post: the author's friends (and the author), or anyone signed in who is not blocked
/// either way. A child's posts are always for friends.
public enum TogetherPostVisibility: String, CaseIterable, Codable, Sendable {
    case friends
    case `public`
}

/// What a post takes (`postLimits` on the server).
public enum TogetherPostLimits {
    /// The longest clip a post takes.
    public static let clipMs = 60_000
    /// The server lets a clip run this much over (a recording that ends a frame late).
    public static let clipSlackMs = 500
    /// A clip's bytes when the server does not say (`mediaLimits.clip`).
    public static let clipBytes = 25 * 1_048_576
    public static let images = 4
    public static let caption = 500
    public static let comment = 500
}

/// Whether a clip fits a post, checked before anything goes up.
public enum TogetherClipCheck: Equatable, Sendable {
    case fits
    /// Longer than a post takes: it cannot be posted as it is.
    case tooLong(ms: Int)
    /// More bytes than a clip may have: it is made smaller first (MediaPrep.clip).
    case tooBig(bytes: Int)

    public static func check(durationMs: Int?, bytes: Int, maxBytes: Int = TogetherPostLimits.clipBytes, maxMs: Int = TogetherPostLimits.clipMs) -> TogetherClipCheck {
        if let durationMs, durationMs > maxMs + TogetherPostLimits.clipSlackMs { return .tooLong(ms: durationMs) }
        if bytes > maxBytes { return .tooBig(bytes: bytes) }
        return .fits
    }

    /// Posting is refused before the upload.
    public var blocks: Bool {
        if case .tooLong = self { return true }
        return false
    }
}

/// A post as the reader may see it (`PostView`).
public struct TogetherPost: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let author: TogetherPerson
    public let caption: String?
    public let game: TogetherActivity.Game?
    public let visibility: TogetherPostVisibility
    public let commentsOff: Bool
    /// Signed links that work 12 to 24 hours: read the post again rather than keep them.
    public let media: [TogetherMedia]
    public var likes: Int
    public var liked: Bool
    /// Comments and replies the reader may see.
    public var comments: Int
    /// The reader wrote it: they may delete it.
    public let mine: Bool
    /// "launcher", "phone", "web" or nil.
    public let source: String?
    public let createdAt: Date
    public let editedAt: Date?

    public init(id: String, author: TogetherPerson, caption: String? = nil, game: TogetherActivity.Game? = nil, visibility: TogetherPostVisibility = .friends,
                commentsOff: Bool = false, media: [TogetherMedia], likes: Int = 0, liked: Bool = false, comments: Int = 0, mine: Bool = false,
                source: String? = nil, createdAt: Date, editedAt: Date? = nil) {
        self.id = id
        self.author = author
        self.caption = caption
        self.game = game
        self.visibility = visibility
        self.commentsOff = commentsOff
        self.media = media
        self.likes = likes
        self.liked = liked
        self.comments = comments
        self.mine = mine
        self.source = source
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    enum CodingKeys: String, CodingKey { case id, author, caption, game, visibility, commentsOff, media, likes, liked, comments, mine, source, createdAt, editedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        author = try c.decode(TogetherPerson.self, forKey: .author)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        game = try c.decodeIfPresent(TogetherActivity.Game.self, forKey: .game)
        // A visibility this launcher does not know yet reads as the narrower one.
        visibility = (try c.decodeIfPresent(String.self, forKey: .visibility)).flatMap(TogetherPostVisibility.init(rawValue:)) ?? .friends
        commentsOff = try c.decodeIfPresent(Bool.self, forKey: .commentsOff) ?? false
        media = try c.decodeIfPresent([TogetherMedia].self, forKey: .media) ?? []
        likes = try c.flexibleInt(.likes) ?? 0
        liked = try c.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        comments = try c.flexibleInt(.comments) ?? 0
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
    }

    /// The clip, when the post is one.
    public var clip: TogetherMedia? { media.first { $0.kind == "clip" } }
    /// What is shown: everything but what a moderator hid (which only the owner still gets).
    public var shown: [TogetherMedia] { media.filter { $0.hidden != true } }
}

public struct TogetherPostPage: Decodable, Equatable, Sendable {
    public let items: [TogetherPost]
    /// Pass as `before` for the next, older page; nil at the end.
    public let next: String?

    public init(items: [TogetherPost], next: String?) {
        self.items = items
        self.next = next
    }
}

/// A post's likes after one was given or taken back.
public struct TogetherLikes: Decodable, Equatable, Sendable {
    public let likes: Int
    public let liked: Bool

    public init(likes: Int, liked: Bool) {
        self.likes = likes
        self.liked = liked
    }
}

/// A comment (`CommentView`): top-level ones carry their replies, oldest first, one level deep.
public struct TogetherComment: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let postId: String
    public let author: TogetherPerson
    public let text: String
    /// The top-level comment this answers; nil for a top-level one.
    public let replyTo: String?
    public let createdAt: Date
    /// The reader may delete it: its author, or the post's.
    public let canDelete: Bool
    public var replies: [TogetherComment]

    public init(id: String, postId: String, author: TogetherPerson, text: String, replyTo: String? = nil, createdAt: Date, canDelete: Bool = false, replies: [TogetherComment] = []) {
        self.id = id
        self.postId = postId
        self.author = author
        self.text = text
        self.replyTo = replyTo
        self.createdAt = createdAt
        self.canDelete = canDelete
        self.replies = replies
    }

    enum CodingKeys: String, CodingKey { case id, postId, author, text, replyTo, createdAt, canDelete, replies }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        postId = try c.decode(String.self, forKey: .postId)
        author = try c.decode(TogetherPerson.self, forKey: .author)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        replyTo = try c.decodeIfPresent(String.self, forKey: .replyTo)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
        replies = try c.decodeIfPresent([TogetherComment].self, forKey: .replies) ?? []
    }
}

public struct TogetherCommentPage: Decodable, Equatable, Sendable {
    public let items: [TogetherComment]
    public let next: String?

    public init(items: [TogetherComment], next: String?) {
        self.items = items
        self.next = next
    }
}

/// A post being written in the gallery: its caption, who sees it and the game it is from.
public struct TogetherPostDraft: Equatable, Sendable {
    public var caption: String
    public var visibility: TogetherPostVisibility
    /// The game the capture is from; sent only when it is a title ID the server takes.
    public var titleId: String?
    public var commentsOff: Bool

    public static let source = "launcher"

    public init(caption: String = "", visibility: TogetherPostVisibility = .friends, titleId: String? = nil, commentsOff: Bool = false) {
        self.caption = caption
        self.visibility = visibility
        self.titleId = titleId
        self.commentsOff = commentsOff
    }

    /// The caption as it goes: trimmed, at most 500, nothing when empty.
    public var sentCaption: String? {
        let trimmed = String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TogetherPostLimits.caption))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// PPSA01234: four capitals and five digits.
    public static func isTitleId(_ text: String) -> Bool {
        text.range(of: "^[A-Z]{4}[0-9]{5}$", options: .regularExpression) != nil
    }

    /// POST /posts. The visibility is always sent, so the choice made here is the one kept.
    public func body(media: [String]) -> [String: Any] {
        var body: [String: Any] = ["media": media, "visibility": visibility.rawValue, "source": Self.source]
        if let sentCaption { body["caption"] = sentCaption }
        if let titleId, Self.isTitleId(titleId) { body["titleId"] = titleId }
        if commentsOff { body["commentsOff"] = true }
        return body
    }
}

/// Why AnyTogether refused something about a post or a comment, for the launcher to say in words.
public enum TogetherPostRefusal: Equatable, Sendable {
    case commentsOff
    case linkBlocked
    case accountMuted
    /// A parent's settings: sharing is off (`mediaSharing`), or posts stay with friends (`profileVisibility`).
    case family(FamilyFeature)
    case rateLimited
    case storageDisabled
    case clipTooLong
    case badMedia
    case quotaFull
    case tooBig
    /// The post or comment is gone, or the reader may no longer see it.
    case gone

    public init?(_ error: Error) {
        guard let problem = error as? TogetherProblem else { return nil }
        switch problem.code {
        case "comments_off": self = .commentsOff
        case "link_blocked": self = .linkBlocked
        case "account_muted": self = .accountMuted
        case "restricted_by_family": self = .family(problem.familyFeature ?? .family)
        case "rate_limited": self = .rateLimited
        case "storage_disabled": self = .storageDisabled
        case "bad_media", "bad_image": self = problem.maxMs != nil ? .clipTooLong : .badMedia
        case "quota_exceeded": self = .quotaFull
        case "payload_too_large": self = .tooBig
        case "not_found": self = .gone
        default:
            guard problem.status == 404 else { return nil }
            self = .gone
        }
    }
}

/// The Captures feed as the launcher holds it: newest first (IDs are time-ordered UUIDv7s), one
/// post per ID.
public struct TogetherCaptures: Equatable, Sendable {
    public private(set) var items: [TogetherPost] = []
    public private(set) var next: String?
    public private(set) var loaded = false

    public init() {}

    /// The first page, in place of whatever was read before.
    public mutating func load(_ page: TogetherPostPage) {
        items = []
        loaded = true
        next = page.next
        page.items.forEach { upsert($0) }
    }

    /// An older page, after what is there.
    public mutating func loadOlder(_ page: TogetherPostPage) {
        next = page.next
        page.items.forEach { upsert($0) }
    }

    /// A new or changed post: it replaces the one with its ID, or goes in at its place.
    public mutating func upsert(_ post: TogetherPost) {
        if let index = index(of: post.id) {
            items[index] = post
        } else {
            items.insert(post, at: items.firstIndex { $0.id < post.id } ?? items.endIndex)
        }
    }

    public mutating func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    /// Likes or takes the like back at once; the likes as they were, to put back on a failure.
    public mutating func toggleLike(_ id: String) -> TogetherLikes? {
        guard let index = index(of: id) else { return nil }
        let before = TogetherLikes(likes: items[index].likes, liked: items[index].liked)
        items[index].liked.toggle()
        items[index].likes = max(0, before.likes + (before.liked ? -1 : 1))
        return before
    }

    public mutating func setLikes(_ likes: TogetherLikes, for id: String) {
        guard let index = index(of: id) else { return }
        items[index].likes = likes.likes
        items[index].liked = likes.liked
    }

    /// Comments added (or, negative, deleted) under a post.
    public mutating func addComments(_ delta: Int, to id: String) {
        guard let index = index(of: id) else { return }
        items[index].comments = max(0, items[index].comments + delta)
    }

    public func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }
}

/// A post's comments as the comments sheet holds them: top-level newest first, each with its
/// replies oldest first, read a page at a time.
public struct TogetherCommentThread: Equatable, Sendable {
    /// One line of the sheet: a top-level comment or a reply under one.
    public struct Line: Equatable, Sendable, Identifiable {
        public let comment: TogetherComment
        /// The top-level comment a reply is under; nil for a top-level one.
        public let parent: String?
        public var id: String { comment.id }
        public var isReply: Bool { parent != nil }
    }

    public let postId: String
    public private(set) var items: [TogetherComment] = []
    public private(set) var next: String?
    public private(set) var loaded = false

    public init(postId: String) {
        self.postId = postId
    }

    public mutating func load(_ page: TogetherCommentPage) {
        items = page.items
        next = page.next
        loaded = true
    }

    public mutating func loadOlder(_ page: TogetherCommentPage) {
        let have = Set(items.map(\.id))
        items += page.items.filter { !have.contains($0.id) }
        next = page.next
    }

    /// A comment just made: a top-level one first, a reply last under the one it answers.
    public mutating func add(_ comment: TogetherComment) {
        if let parent = comment.replyTo {
            guard let index = items.firstIndex(where: { $0.id == parent }), !items[index].replies.contains(where: { $0.id == comment.id }) else { return }
            items[index].replies.append(comment)
        } else if !items.contains(where: { $0.id == comment.id }) {
            items.insert(comment, at: 0)
        }
    }

    /// Takes a comment out (a top-level one with its replies); how many went.
    @discardableResult
    public mutating func remove(_ id: String) -> Int {
        if let index = items.firstIndex(where: { $0.id == id }) {
            return 1 + items.remove(at: index).replies.count
        }
        for index in items.indices {
            if let reply = items[index].replies.firstIndex(where: { $0.id == id }) {
                items[index].replies.remove(at: reply)
                return 1
            }
        }
        return 0
    }

    /// The sheet's lines in order: each top-level comment, then its replies.
    public var lines: [Line] {
        items.flatMap { comment in [Line(comment: comment, parent: nil)] + comment.replies.map { Line(comment: $0, parent: comment.id) } }
    }

    public func comment(_ id: String) -> TogetherComment? { lines.first { $0.id == id }?.comment }
}

extension TogetherClient {
    /// Makes a post of media already uploaded; the post as the server keeps it.
    public func createPost(media: [String], draft: TogetherPostDraft) async throws -> TogetherPost {
        try JSONDecoder.together.decode(TogetherPost.self, from: try await authorized("POST", "posts", draft.body(media: media)))
    }

    /// The Captures feed: one's own posts, friends' and public ones of people one played with.
    public func captures(before: String? = nil, limit: Int? = nil) async throws -> TogetherPostPage {
        try JSONDecoder.together.decode(TogetherPostPage.self, from: try await authorized("GET", "me/captures" + Self.paging(before, limit), nil))
    }

    /// Likes a post, or takes the like back; its likes as they are now.
    public func setLiked(_ liked: Bool, post id: String) async throws -> TogetherLikes {
        try JSONDecoder.together.decode(TogetherLikes.self, from: try await authorized(liked ? "PUT" : "DELETE", "posts/\(Self.path(id))/like", nil))
    }

    public func comments(on post: String, before: String? = nil, limit: Int? = nil) async throws -> TogetherCommentPage {
        try JSONDecoder.together.decode(TogetherCommentPage.self, from: try await authorized("GET", "posts/\(Self.path(post))/comments" + Self.paging(before, limit), nil))
    }

    /// A comment, or a reply to a top-level one.
    public func comment(on post: String, text: String, replyTo: String? = nil) async throws -> TogetherComment {
        var body: [String: Any] = ["text": String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TogetherPostLimits.comment))]
        if let replyTo { body["replyTo"] = replyTo }
        return try JSONDecoder.together.decode(TogetherComment.self, from: try await authorized("POST", "posts/\(Self.path(post))/comments", body))
    }

    public func deleteComment(_ id: String, on post: String) async throws {
        _ = try await authorized("DELETE", "posts/\(Self.path(post))/comments/\(Self.path(id))", nil)
    }

    public func deletePost(_ id: String) async throws {
        _ = try await authorized("DELETE", "posts/\(Self.path(id))", nil)
    }
}
