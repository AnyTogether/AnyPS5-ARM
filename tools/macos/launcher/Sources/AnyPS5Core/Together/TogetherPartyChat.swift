import Foundation

/// A party's text chat, beside its voice: an ordinary group conversation tied to the party, so
/// the messages routes and the socket's message events work for it as for any other. It is not in
/// the inbox's list or its unread count (the party screen shows it, read to its end while it is
/// shown), it is text only, and its members are the party's: joining reads its history, leaving
/// or the party ending takes it away.
public struct TogetherPartyChat: Equatable, Sendable {
    /// How many messages the party screen reads at first, and catches up by at a time.
    public static let page = 40

    /// The conversation's ID, and the party it belongs to.
    public let id: String
    public let partyId: String
    /// Oldest first; nil until the history is read.
    public private(set) var messages: [TogetherMessage]?
    /// Whether there are older messages than the first one here.
    public private(set) var more = false
    /// The newest seq told to the server as read.
    public private(set) var readSeq = 0
    /// Others' messages that came while the chat was not on screen.
    public private(set) var unread = 0
    /// Everyone seen in the party this session, by user ID: someone who left keeps their name.
    public private(set) var seen: [String: TogetherPerson] = [:]
    /// The order they were first seen in.
    private var seenOrder: [String] = []
    /// What the socket brought before the history was read.
    private var early: [TogetherMessage] = []

    public init(id: String, partyId: String) {
        self.id = id
        self.partyId = partyId
    }

    public var newestSeq: Int? { messages?.last?.seq }

    /// The party's members as it is now.
    public mutating func saw(_ people: [TogetherPerson]) {
        for person in people {
            if seen[person.userId] == nil { seenOrder.append(person.userId) }
            seen[person.userId] = person
        }
    }

    /// The newest page read (on joining nothing of it is unread); what the socket brought
    /// meanwhile stays.
    public mutating func loaded(_ page: [TogetherMessage], more: Bool) {
        let page = page.filter { $0.conversationId == id }
        guard let kept = messages else {
            messages = merged(page, early)
            early = []
            self.more = more
            return
        }
        messages = merged(kept, page)
    }

    /// A message made, edited or unsent (the socket's, or the answer to sending or editing). True
    /// when it is a new one here. `open`: the chat is on screen, so it is not unread.
    @discardableResult
    public mutating func apply(_ message: TogetherMessage, me: String, open: Bool) -> Bool {
        guard message.conversationId == id else { return false }
        guard var list = messages else {
            let new = !early.contains { $0.seq == message.seq }
            early = merged(early, [message])
            return new
        }
        if let at = list.firstIndex(where: { $0.seq == message.seq }) {
            let before = list[at]
            list[at] = message
            messages = list
            // Unsent before it was read.
            if before.deletedAt == nil, message.deletedAt != nil, before.authorId != me, message.seq > readSeq, unread > 0 { unread -= 1 }
            return false
        }
        // Older than the history read, while older ones are left to read: it is not shown alone at the top.
        if more, let first = list.first, message.seq < first.seq { return false }
        messages = merged(list, [message])
        if message.authorId != me, message.deletedAt == nil, !open, message.seq > readSeq { unread += 1 }
        return true
    }

    /// A message's reactions as they are now.
    public mutating func react(_ seq: Int, reactions: [TogetherReactionCount]) {
        guard let at = messages?.firstIndex(where: { $0.seq == seq }) else { return }
        messages?[at].reactions = reactions
    }

    /// Read to its newest message here: the seq to tell the server, nil when it knows already.
    public mutating func readToEnd() -> Int? {
        unread = 0
        guard let newest = newestSeq, newest > readSeq else { return nil }
        readSeq = newest
        return newest
    }

    /// The name a message's author goes by: a member's, or the one they had in the party this
    /// session; nil for someone the launcher never saw in it (a former member).
    public func name(of userId: String?, members: [TogetherPerson]) -> String? {
        guard let userId else { return nil }
        return (members.first { $0.userId == userId } ?? seen[userId])?.displayName
    }

    /// The chat as a conversation, for the thread's views: the party's members, then those seen in
    /// it who left (so their names stay); no receipts, nothing pinned, muted as the server starts it.
    public func conversation(for party: TogetherParty) -> TogetherConversation {
        let inside = Set(party.members.map(\.userId))
        let left = seenOrder.filter { !inside.contains($0) }.compactMap { seen[$0] }
        let last = messages?.last
        return TogetherConversation(id: id, kind: "group", title: nil, members: party.members + left, lastSeq: last?.seq ?? 0, readSeq: readSeq, unread: unread,
                                    lastMessage: last, updatedAt: last?.createdAt ?? .distantPast, muted: true, partyId: partyId)
    }

    private func merged(_ kept: [TogetherMessage], _ new: [TogetherMessage]) -> [TogetherMessage] {
        var bySeq: [Int: TogetherMessage] = [:]
        for message in kept { bySeq[message.seq] = message }
        for message in new { bySeq[message.seq] = message }
        return bySeq.values.sorted { $0.seq < $1.seq }
    }
}
