import Foundation

/// A message as every member sees it; a deleted one keeps its place with no text.
public struct TogetherMessage: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let conversationId: String
    public let seq: Int
    public let authorId: String?
    public let text: String?
    public let replyTo: Int?
    public let editedAt: Date?
    public let deletedAt: Date?
    public let createdAt: Date

    public init(id: String, conversationId: String, seq: Int, authorId: String?, text: String?, replyTo: Int? = nil, editedAt: Date? = nil, deletedAt: Date? = nil, createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.seq = seq
        self.authorId = authorId
        self.text = text
        self.replyTo = replyTo
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt
    }
}

/// A direct conversation with a friend, or a group.
public struct TogetherConversation: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    /// "direct" or "group".
    public let kind: String
    public let title: String?
    public let members: [TogetherPerson]
    public var lastSeq: Int
    public var readSeq: Int
    public var unread: Int
    public var lastMessage: TogetherMessage?
    public var updatedAt: Date

    public init(id: String, kind: String, title: String?, members: [TogetherPerson], lastSeq: Int, readSeq: Int, unread: Int, lastMessage: TogetherMessage?, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.members = members
        self.lastSeq = lastSeq
        self.readSeq = readSeq
        self.unread = unread
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
    }

    public func others(than me: String) -> [TogetherPerson] { members.filter { $0.userId != me } }

    /// The group's title, or who is in it besides the user.
    public func name(for me: String) -> String {
        if let title, !title.isEmpty { return title }
        return others(than: me).map(\.displayName).joined(separator: ", ")
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

    /// The newest page, or the one before `before` (a message seq); oldest first.
    public func messages(in conversationId: String, before: Int? = nil, limit: Int = 50) async throws -> (messages: [TogetherMessage], more: Bool) {
        struct Page: Decodable { let messages: [TogetherMessage]; let more: Bool }
        let query = "limit=\(limit)" + (before.map { "&before=\($0)" } ?? "")
        let page = try JSONDecoder.together.decode(Page.self, from: try await authorized("GET", "conversations/\(conversationId)/messages?\(query)", nil))
        return (page.messages, page.more)
    }

    /// `id` is the message's own ID, so sending again after a timeout stores it once.
    public func send(_ text: String, in conversationId: String, id: UUID = UUID()) async throws -> TogetherMessage {
        let body: [String: Any] = ["clientId": id.uuidString.lowercased(), "text": text]
        return try JSONDecoder.together.decode(TogetherMessage.self, from: try await authorized("POST", "conversations/\(conversationId)/messages", body))
    }

    public func markRead(_ conversationId: String, upTo seq: Int) async throws {
        _ = try await authorized("POST", "conversations/\(conversationId)/read", ["upToSeq": seq])
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

    /// A message made, edited or deleted. A new one moves its conversation to the top and counts
    /// as unread unless it is the user's own or its thread is `open`. False for a conversation not
    /// in the list (a new one): the list should be read again.
    @discardableResult
    public mutating func apply(_ message: TogetherMessage, open: String?) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else { return false }
        var conversation = conversations[index]
        var thread = threads[message.conversationId]
        if let existing = thread?.firstIndex(where: { $0.seq == message.seq }) {
            thread?[existing] = message
        } else if thread != nil {
            thread?.append(message)
            thread?.sort { $0.seq < $1.seq }
        }
        if let thread { threads[message.conversationId] = thread }
        if conversation.lastMessage?.seq == message.seq { conversation.lastMessage = message }
        if message.seq > conversation.lastSeq {
            conversation.lastSeq = message.seq
            conversation.lastMessage = message
            conversation.updatedAt = message.createdAt
            if message.authorId == me || open == message.conversationId {
                conversation.readSeq = message.seq
            }
            conversation.unread = max(0, conversation.lastSeq - conversation.readSeq)
            conversations.remove(at: index)
            conversations.insert(conversation, at: 0)
        } else {
            conversations[index] = conversation
        }
        return true
    }

    /// Someone read up to a message; the user's own reading (here or elsewhere) clears the count.
    public mutating func read(_ conversationId: String, by userId: String, upTo seq: Int) {
        guard userId == me, let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].readSeq = max(conversations[index].readSeq, seq)
        conversations[index].unread = max(0, conversations[index].lastSeq - conversations[index].readSeq)
    }
}
