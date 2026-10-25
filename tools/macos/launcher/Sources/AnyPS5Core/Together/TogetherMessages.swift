import Foundation

/// The reactions a message can get, one of each per person, in the order they are drawn.
public enum TogetherMessageReaction: String, CaseIterable, Codable, Sendable {
    case like, love, laugh, wow, sad, fire, gg

    public var glyph: String {
        switch self {
        case .like: return "👍"
        case .love: return "❤️"
        case .laugh: return "😂"
        case .wow: return "😮"
        case .sad: return "😢"
        case .fire: return "🔥"
        case .gg: return "GG"
        }
    }
}

/// Who reacted to a message with one reaction.
public struct TogetherReactionCount: Decodable, Equatable, Sendable {
    public let reaction: TogetherMessageReaction
    public let count: Int
    public let userIds: [String]

    public init(reaction: TogetherMessageReaction, count: Int, userIds: [String]) {
        self.reaction = reaction
        self.count = count
        self.userIds = userIds
    }
}

/// A list of reactions as this launcher knows them: one it does not know (from a newer server) is left out.
struct KnownReactions: Decodable {
    let reactions: [TogetherReactionCount]

    init(from decoder: Decoder) throws {
        struct One: Decodable {
            let value: TogetherReactionCount?
            init(from decoder: Decoder) throws { value = try? TogetherReactionCount(from: decoder) }
        }
        reactions = try [One](from: decoder).compactMap(\.value)
    }
}

/// A message as every member sees it; an unsent or removed one keeps its place with no text,
/// media or reactions.
public struct TogetherMessage: Decodable, Equatable, Sendable, Identifiable {
    /// How long after sending a message may be edited, and how many times.
    public static let editWindow: TimeInterval = 15 * 60
    public static let maxEdits = 20

    public let id: String
    public let conversationId: String
    public let seq: Int
    public let authorId: String?
    public let text: String?
    /// The seq of the message it answers, in the same conversation.
    public let replyTo: Int?
    public let editedAt: Date?
    public let deletedAt: Date?
    public let createdAt: Date
    /// "text", "image", "clip" or "voice"; nil from a server that knows no media.
    public let kind: String?
    /// A media message's caption alone (its `text` is the caption or a stand-in like "[photo]").
    public let caption: String?
    /// The one piece of media a media message has, as this member may see it.
    public let attachments: [TogetherAttachment]?
    /// How many times it was edited; 0 from an older server.
    public let editCount: Int
    /// Who reacted with what, in TogetherMessageReaction's order; empty once unsent (and from an older server).
    public var reactions: [TogetherReactionCount]

    public init(id: String, conversationId: String, seq: Int, authorId: String?, text: String?, replyTo: Int? = nil, editedAt: Date? = nil, deletedAt: Date? = nil, createdAt: Date,
                kind: String? = nil, caption: String? = nil, attachments: [TogetherAttachment]? = nil, editCount: Int = 0, reactions: [TogetherReactionCount] = []) {
        self.id = id
        self.conversationId = conversationId
        self.seq = seq
        self.authorId = authorId
        self.text = text
        self.replyTo = replyTo
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.kind = kind
        self.caption = caption
        self.attachments = attachments
        self.editCount = editCount
        self.reactions = reactions
    }

    enum CodingKeys: String, CodingKey { case id, conversationId, seq, authorId, text, replyTo, editedAt, deletedAt, createdAt, kind, caption, attachments, editCount, reactions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        seq = try container.decode(Int.self, forKey: .seq)
        authorId = try container.decodeIfPresent(String.self, forKey: .authorId)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        replyTo = container.lenient(Int.self, .replyTo)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        attachments = try container.decodeIfPresent([TogetherAttachment].self, forKey: .attachments)
        editCount = container.lenient(Int.self, .editCount) ?? 0
        reactions = container.lenient(KnownReactions.self, .reactions)?.reactions ?? []
    }

    /// The media it carries, when it is a media message (and not deleted).
    public var attachment: TogetherAttachment? {
        guard deletedAt == nil else { return nil }
        return attachments?.first
    }

    /// What it says in words: the caption of a media message (nil without one), else the text.
    public var words: String? {
        guard deletedAt == nil else { return nil }
        guard attachment != nil else { return text }
        return caption.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func hasReacted(_ reaction: TogetherMessageReaction, by userId: String) -> Bool {
        reactions.contains { $0.reaction == reaction && $0.userIds.contains(userId) }
    }

    /// Whether its author may still edit it: their own text (or a media message's caption), within
    /// the edit window and under the edit limit.
    public func canEdit(by me: String, at now: Date = Date()) -> Bool {
        guard authorId == me, deletedAt == nil, editCount < TogetherMessage.maxEdits, now.timeIntervalSince(createdAt) < TogetherMessage.editWindow else { return false }
        return kind == nil || kind == "text" || !(caption ?? "").isEmpty
    }

    /// The same message unsent: only its place is left.
    public func removed(at date: Date = Date()) -> TogetherMessage {
        TogetherMessage(id: id, conversationId: conversationId, seq: seq, authorId: authorId, text: nil, replyTo: replyTo, editedAt: editedAt, deletedAt: date, createdAt: createdAt,
                        kind: kind, caption: nil, attachments: nil, editCount: editCount)
    }
}

/// What a reply quotes, as far as the thread loaded knows it.
public enum TogetherQuote: Equatable, Sendable {
    case message(TogetherMessage)
    /// Unsent or removed.
    case removed
    /// Not in the pages loaded.
    case earlier

    public init?(seq: Int?, in thread: [TogetherMessage]) {
        guard let seq else { return nil }
        guard let found = thread.first(where: { $0.seq == seq }) else { self = .earlier; return }
        self = found.deletedAt == nil ? .message(found) : .removed
    }
}

/// How far another member of a conversation has got. `readSeq` is nil unless both share read
/// receipts; `deliveredSeq` is nil in a group.
public struct TogetherReceipt: Decodable, Equatable, Sendable {
    public let userId: String
    public var readSeq: Int?
    public var deliveredSeq: Int?

    public init(userId: String, readSeq: Int?, deliveredSeq: Int?) {
        self.userId = userId
        self.readSeq = readSeq
        self.deliveredSeq = deliveredSeq
    }

    /// Where the user's own message has got: sent, delivered or read in a direct conversation,
    /// seen by some or everyone in a group.
    public enum State: Equatable, Sendable {
        case sent, delivered, read
        case seen(Int, everyone: Bool)
    }
}

/// A direct conversation with a friend, or a group.
public struct TogetherConversation: Decodable, Equatable, Sendable, Identifiable {
    /// The most conversations kept pinned at the top of the list.
    public static let maxPinned = 5

    public let id: String
    /// "direct" or "group".
    public let kind: String
    public let title: String?
    public let members: [TogetherPerson]
    public var lastSeq: Int
    public var readSeq: Int
    /// The others' messages after `readSeq` that are not unsent, as the server counts them.
    public var unread: Int
    public var lastMessage: TogetherMessage?
    public var updatedAt: Date
    /// Kept at the top of the list; false from an older server.
    public var pinned: Bool
    /// No notifications for it; false from an older server.
    public var muted: Bool
    /// One for each other member; nil from an older server (and then none are shown).
    public var receipts: [TogetherReceipt]?

    public init(id: String, kind: String, title: String?, members: [TogetherPerson], lastSeq: Int, readSeq: Int, unread: Int, lastMessage: TogetherMessage?, updatedAt: Date,
                pinned: Bool = false, muted: Bool = false, receipts: [TogetherReceipt]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.members = members
        self.lastSeq = lastSeq
        self.readSeq = readSeq
        self.unread = unread
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.muted = muted
        self.receipts = receipts
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, members, lastSeq, readSeq, unread, lastMessage, updatedAt, pinned, muted, receipts }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        members = try container.decode([TogetherPerson].self, forKey: .members)
        lastSeq = try container.decode(Int.self, forKey: .lastSeq)
        readSeq = try container.decode(Int.self, forKey: .readSeq)
        unread = try container.decode(Int.self, forKey: .unread)
        lastMessage = try container.decodeIfPresent(TogetherMessage.self, forKey: .lastMessage)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pinned = container.lenient(Bool.self, .pinned) ?? false
        muted = container.lenient(Bool.self, .muted) ?? false
        receipts = container.lenient([TogetherReceipt].self, .receipts)
    }

    public func others(than me: String) -> [TogetherPerson] { members.filter { $0.userId != me } }

    /// The group's title, or who is in it besides the user.
    public func name(for me: String) -> String {
        if let title, !title.isEmpty { return title }
        return others(than: me).map(\.displayName).joined(separator: ", ")
    }

    /// Where the user's own message has got; nil for someone else's, an unsent one, or without receipts.
    public func receipt(for message: TogetherMessage, me: String) -> TogetherReceipt.State? {
        guard message.authorId == me, message.deletedAt == nil, let receipts else { return nil }
        if kind == "group" {
            let seen = receipts.filter { ($0.readSeq ?? -1) >= message.seq }.count
            return .seen(seen, everyone: seen > 0 && seen == receipts.count)
        }
        guard let other = receipts.first else { return nil }
        if (other.readSeq ?? -1) >= message.seq { return .read }
        if (other.deliveredSeq ?? -1) >= message.seq { return .delivered }
        return .sent
    }
}

extension TogetherClient {
    public func conversations() async throws -> [TogetherConversation] {
        struct List: Decodable { let conversations: [TogetherConversation] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "me/conversations", nil)).conversations
    }

    /// Unread messages over every conversation, for the top bar.
    public func unreadMessages() async throws -> Int {
        struct Count: Decodable { let messages: Int }
        return try JSONDecoder.together.decode(Count.self, from: try await authorized("GET", "me/conversations/unread", nil)).messages
    }

    /// The direct conversation with a friend: made the first time, the same one after.
    public func conversation(with userId: String) async throws -> TogetherConversation {
        try JSONDecoder.together.decode(TogetherConversation.self, from: try await authorized("POST", "conversations", ["members": [userId]]))
    }

    /// A group with friends (one or more); without a name its members stand for it.
    public func startGroup(with userIds: [String], title: String? = nil) async throws -> TogetherConversation {
        var body: [String: Any] = ["members": userIds, "group": true]
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { body["title"] = String(title.prefix(80)) }
        return try JSONDecoder.together.decode(TogetherConversation.self, from: try await authorized("POST", "conversations", body))
    }

    /// The newest page, or the one before `before` (a message seq); oldest first.
    public func messages(in conversationId: String, before: Int? = nil, limit: Int = 50) async throws -> (messages: [TogetherMessage], more: Bool) {
        struct Page: Decodable { let messages: [TogetherMessage]; let more: Bool }
        let query = "limit=\(limit)" + (before.map { "&before=\($0)" } ?? "")
        let page = try JSONDecoder.together.decode(Page.self, from: try await authorized("GET", "conversations/\(conversationId)/messages?\(query)", nil))
        return (page.messages, page.more)
    }

    /// `id` is the message's own ID, so sending again after a timeout stores it once; `replyTo`
    /// is the seq of the message it answers.
    public func send(_ text: String, in conversationId: String, replyTo: Int? = nil, id: UUID = UUID()) async throws -> TogetherMessage {
        var body: [String: Any] = ["clientId": id.uuidString.lowercased(), "text": text]
        if let replyTo { body["replyTo"] = replyTo }
        return try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("POST", "conversations/\(conversationId)/messages", body))
    }

    /// A piece of the user's media (uploaded first) as a message, with an optional caption.
    public func send(media mediaId: String, caption: String? = nil, in conversationId: String, id: UUID = UUID()) async throws -> TogetherMessage {
        var body: [String: Any] = ["clientId": id.uuidString.lowercased(), "attachments": [["mediaId": mediaId]]]
        if let caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty { body["text"] = caption }
        return try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("POST", "conversations/\(conversationId)/messages", body))
    }

    public func markRead(_ conversationId: String, upTo seq: Int) async throws {
        _ = try await authorized("POST", "conversations/\(conversationId)/read", ["upToSeq": seq])
    }

    /// Messages from someone else reached this device (in a thread not on screen): its sender sees
    /// them delivered.
    public func markDelivered(_ conversationId: String, upTo seq: Int) async throws {
        _ = try await authorized("POST", "conversations/\(conversationId)/delivered", ["upToSeq": seq])
    }

    /// The user's own message (or a media message's caption) said again: refused with a 403 once
    /// the edit window has passed, and "edit_limit" after the most edits.
    public func edit(_ seq: Int, in conversationId: String, to text: String) async throws -> TogetherMessage {
        try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("PATCH", "conversations/\(conversationId)/messages/\(seq)", ["text": text]))
    }

    /// The user's own message unsent for everyone; only its place is left.
    public func unsend(_ seq: Int, in conversationId: String) async throws {
        _ = try await authorized("DELETE", "conversations/\(conversationId)/messages/\(seq)", nil)
    }

    /// A reaction added (`on`) or taken back; the message's reactions as they are now.
    public func react(_ reaction: TogetherMessageReaction, to seq: Int, in conversationId: String, on: Bool) async throws -> [TogetherReactionCount] {
        struct Answer: Decodable { let reactions: KnownReactions }
        let data = try await authorized(on ? "PUT" : "DELETE", "conversations/\(conversationId)/messages/\(seq)/reactions/\(reaction.rawValue)", nil)
        return try JSONDecoder.together.decode(Answer.self, from: data).reactions.reactions
    }

    /// Pinned to the top of the list or not: "full" (409) with TogetherConversation.maxPinned pinned.
    public func pin(_ conversationId: String, _ pinned: Bool) async throws -> TogetherConversation {
        try JSONDecoder.together.decode(TogetherConversation.self, from: try await authorized("PUT", "conversations/\(conversationId)/pin", ["pinned": pinned]))
    }

    /// Its notifications off or on again.
    public func mute(_ conversationId: String, _ muted: Bool) async throws -> TogetherConversation {
        try JSONDecoder.together.decode(TogetherConversation.self, from: try await authorized("PUT", "conversations/\(conversationId)/mute", ["muted": muted]))
    }

    /// Whether others see when the user has read their messages (and the user sees theirs).
    public func setReadReceipts(_ on: Bool) async throws -> Bool {
        struct Setting: Decodable { let readReceipts: Bool }
        return try JSONDecoder.together.decode(Setting.self, from: try await authorized("PATCH", "me/read-receipts", ["readReceipts": on])).readReceipts
    }
}

/// Who is typing where: someone shows as typing for a few seconds after they last said so, or
/// until their message arrives.
public struct TogetherTyping: Equatable, Sendable {
    /// How often a client says it is typing, and how long it shows after.
    public static let every: TimeInterval = 2
    public static let shows: TimeInterval = 5

    private var said: [String: [String: Date]] = [:]

    public init() {}

    public mutating func typing(_ userId: String, in conversation: String, at now: Date = Date()) {
        said[conversation, default: [:]][userId] = now
    }

    /// Their message came: they stopped typing it.
    public mutating func wrote(_ userId: String, in conversation: String) {
        said[conversation]?[userId] = nil
    }

    /// Who types in the conversation now, in user ID order.
    public func who(in conversation: String, at now: Date = Date()) -> [String] {
        (said[conversation] ?? [:]).filter { now.timeIntervalSince($0.value) < TogetherTyping.shows }.keys.sorted()
    }

    /// Forgets what has stopped showing; true when anything went.
    @discardableResult
    public mutating func expire(at now: Date = Date()) -> Bool {
        let before = said
        said = said.compactMapValues { users in
            let kept = users.filter { now.timeIntervalSince($0.value) < TogetherTyping.shows }
            return kept.isEmpty ? nil : kept
        }
        return said != before
    }
}

/// The conversations and the threads read so far, kept current by the socket's events.
public struct TogetherInbox: Equatable, Sendable {
    public let me: String
    public var conversations: [TogetherConversation]
    /// Messages by conversation, oldest first, for the threads opened.
    public var threads: [String: [TogetherMessage]] = [:]

    public init(me: String, conversations: [TogetherConversation] = []) {
        self.me = me
        self.conversations = conversations
    }

    public var unread: Int { conversations.reduce(0) { $0 + $1.unread } }

    /// A message made, edited or unsent. A new one moves its conversation up (under the pinned
    /// ones) and counts as unread unless it is the user's own or its thread is `open`. False when
    /// the list should be read again: a conversation not in it (a new one), or someone else's
    /// unread message unsent where the thread loaded cannot tell whether it was counted.
    @discardableResult
    public mutating func apply(_ message: TogetherMessage, open: String?) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else { return false }
        var conversation = conversations[index]
        var thread = threads[message.conversationId]
        let before = thread?.first { $0.seq == message.seq }
        if let existing = thread?.firstIndex(where: { $0.seq == message.seq }) {
            thread?[existing] = message
        } else if thread != nil {
            thread?.append(message)
            thread?.sort { $0.seq < $1.seq }
        }
        if let thread { threads[message.conversationId] = thread }
        if conversation.lastMessage?.seq == message.seq { conversation.lastMessage = message }
        guard message.seq > conversation.lastSeq else {
            var known = true
            if message.deletedAt != nil, message.authorId != me, message.seq > conversation.readSeq {
                if let before {
                    if before.deletedAt == nil { conversation.unread = max(0, conversation.unread - 1) }
                } else {
                    known = false
                }
            }
            conversations[index] = conversation
            return known
        }
        conversation.lastSeq = message.seq
        conversation.lastMessage = message
        conversation.updatedAt = message.createdAt
        if message.authorId == me || open == message.conversationId {
            conversation.readSeq = message.seq
            conversation.unread = 0
        } else if message.deletedAt == nil {
            conversation.unread += 1
        }
        conversations[index] = conversation
        order()
        return true
    }

    /// Someone read up to a message. The user's own reading (here or on another device) moves the
    /// read mark, with what the server says is left unread when it says so; another member's
    /// raises their receipt (never lowers it), which counts as delivered too.
    public mutating func read(_ conversationId: String, by userId: String, upTo seq: Int, unread: Int? = nil) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if userId == me {
            conversations[index].readSeq = max(conversations[index].readSeq, seq)
            conversations[index].unread = unread ?? max(0, conversations[index].lastSeq - conversations[index].readSeq)
            return
        }
        receipt(index, userId) { receipt in
            receipt.readSeq = max(receipt.readSeq ?? 0, seq)
            receipt.deliveredSeq = receipt.deliveredSeq.map { max($0, seq) }
        }
    }

    /// Another member's device got messages up to `seq`.
    public mutating func delivered(_ conversationId: String, by userId: String, upTo seq: Int) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        receipt(index, userId) { receipt in
            receipt.deliveredSeq = receipt.deliveredSeq.map { max($0, seq) }
        }
    }

    private mutating func receipt(_ index: Int, _ userId: String, change: (inout TogetherReceipt) -> Void) {
        guard let at = conversations[index].receipts?.firstIndex(where: { $0.userId == userId }) else { return }
        change(&conversations[index].receipts![at])
    }

    /// A message's reactions as they are now, in its thread and as its conversation's last message.
    public mutating func react(_ conversationId: String, seq: Int, reactions: [TogetherReactionCount]) {
        if let at = threads[conversationId]?.firstIndex(where: { $0.seq == seq }) { threads[conversationId]?[at].reactions = reactions }
        if let index = conversations.firstIndex(where: { $0.id == conversationId }), conversations[index].lastMessage?.seq == seq {
            conversations[index].lastMessage?.reactions = reactions
        }
    }

    /// A conversation as the server has it now (pinned, muted or renamed), in its place in the list.
    public mutating func update(_ conversation: TogetherConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        order()
    }

    /// Pinned ones first, then the newest, as the server lists them.
    private mutating func order() {
        let ranked = conversations.enumerated().sorted { a, b in
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            if a.element.updatedAt != b.element.updatedAt { return a.element.updatedAt > b.element.updatedAt }
            return a.offset < b.offset
        }
        conversations = ranked.map(\.element)
    }

    /// Whether a new message should tell its sender it was delivered: someone else's, in a direct
    /// conversation whose thread is not on screen (reading it says more).
    public func acknowledges(_ message: TogetherMessage, open: String?) -> Bool {
        guard message.authorId != me, message.deletedAt == nil, open != message.conversationId,
              let conversation = conversations.first(where: { $0.id == message.conversationId }) else { return false }
        return conversation.kind == "direct"
    }

    /// The receipt under the user's newest message in a loaded thread (not an unsent one).
    public func receipt(in conversationId: String) -> (seq: Int, state: TogetherReceipt.State)? {
        guard let conversation = conversations.first(where: { $0.id == conversationId }),
              let mine = threads[conversationId]?.last(where: { $0.authorId == me && $0.deletedAt == nil }),
              let state = conversation.receipt(for: mine, me: me) else { return nil }
        return (mine.seq, state)
    }
}
