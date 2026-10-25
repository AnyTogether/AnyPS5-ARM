import Foundation

/// The platform's `userProfile` web API group, answered from AnyTogether: the friends list, a
/// profile and basic presence. The shapes follow public community documentation of the console
/// network's web API; no game has yet been seen accepting them (AnyPlay saw Minecraft Dungeons II
/// ask for `GET /v1/users/local_268435456/friends?` and nobody has seen an answer), so they are
/// unverified and can be switched off with the router's other platform groups.
///
/// Account IDs are `OnlineIdentity.accountId(forUser:)`, as decimal strings, as the platform
/// writes them in JSON. Friends are asked of AnyTogether at most every 30 s: games poll.
///
/// Games check that they may play with others before they go online: Human Fall Flat (PPSA02429)
/// asks for the block list (`GET /v1/users/me/blocks?offset=0&limit=0`) and, in the
/// `communicationRestrictionStatus` group, `GET /v3/users/<account>/communication/restriction/status`.
/// Nobody is blocked and nobody is restricted here.
public final class OnlineUserProfile: @unchecked Sendable {
    public static let group = "userProfile"
    public static let restrictionGroup = "communicationRestrictionStatus"
    static let keepFriends: TimeInterval = 30
    static let pageLimit = 2000

    struct Friend: Decodable {
        struct Presence: Decodable {
            let state: String
            let titleId: String?
        }

        let userId: String
        let handle: String
        let displayName: String
        let avatar: String?
        let presence: Presence?
    }

    private let service: OnlineSessionService
    private let me: TogetherUser
    private let language: String
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var friends: (at: Date, list: [Friend])?

    public init(service: OnlineSessionService, me: TogetherUser, language: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.service = service
        self.me = me
        self.language = language
        self.now = now
    }

    var myAccount: String { String(OnlineIdentity.accountId(forUser: me.id)) }

    public func handle(_ request: OnlineWire.WebRequest) async -> OnlineWire.WebReply {
        guard request.method.uppercased() == "GET" else { return problem(405, "Only GET is offered") }
        let split = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let parts = split.first.map { $0.split(separator: "/").map(String.init) } ?? []
        let query = OnlineUserProfile.query(split.count > 1 ? String(split[1]) : "")
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "users" else { return problem(404, "No such userProfile call") }
        do {
            switch (parts.count, parts[2], parts.count > 3 ? parts[3] : "") {
            case (3, "basicPresences", _):
                let wanted = (query["accountIds"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
                let people = try await everyone()
                let presences = wanted.compactMap { id in people[id].map { presence(id, $0) } }
                return json(["basicPresences": presences])
            case (4, let who, "friends"):
                guard isMe(who) else { return problem(403, "Only your own friends are offered") }
                let list = try await friendList().map { String(OnlineIdentity.accountId(forUser: $0.userId)) }
                let offset = max(0, Int(query["offset"] ?? "") ?? 0)
                let limit = min(OnlineUserProfile.pageLimit, max(1, Int(query["limit"] ?? "") ?? OnlineUserProfile.pageLimit))
                let page = Array(list.dropFirst(offset).prefix(limit))
                var body: [String: Any] = ["friends": page, "totalItemCount": list.count]
                if offset + page.count < list.count { body["nextOffset"] = offset + page.count }
                if offset > 0 { body["previousOffset"] = max(0, offset - limit) }
                return json(body)
            case (4, let who, "profiles"):
                guard let person = try await person(who) else { return problem(404, "No such user") }
                return json(profile(person, isMe: isMe(who)))
            case (4, let who, "basicPresences"):
                guard let person = try await person(who) else { return problem(404, "No such user") }
                return json(["basicPresence": presence(isMe(who) ? myAccount : who, person)])
            case (4, let who, "blocks"):
                guard isMe(who) else { return problem(403, "Only your own block list is offered") }
                return json(["blocks": [String](), "totalItemCount": 0])
            default:
                return problem(404, "No such userProfile call")
            }
        } catch let problem as TogetherProblem {
            return self.problem(problem.status, problem.title)
        } catch {
            return problem(502, "AnyTogether could not be reached")
        }
    }

    /// The `communicationRestrictionStatus` group: our own account is never restricted.
    public func handleRestriction(_ request: OnlineWire.WebRequest) -> OnlineWire.WebReply {
        guard request.method.uppercased() == "GET" else { return problem(405, "Only GET is offered") }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 6, parts[0] == "v3", parts[1] == "users", parts[3] == "communication", parts[4] == "restriction",
              parts[5] == "status" else { return problem(404, "No such communicationRestrictionStatus call") }
        guard isMe(parts[2]) else { return problem(403, "Only your own restriction status is offered") }
        return json(["restricted": false])
    }

    /// "me", "local_<user ID>" (the game's own user, as games write it) or our account number.
    private func isMe(_ who: String) -> Bool {
        who == "me" || who.hasPrefix("local_") || who == myAccount
    }

    private struct Person {
        let onlineId: String
        let presence: Friend.Presence?
        let online: Bool
    }

    private func person(_ who: String) async throws -> Person? {
        if isMe(who) { return Person(onlineId: OnlineIdentity.onlineId(handle: me.handle), presence: nil, online: true) }
        return try await everyone()[who]
    }

    /// Me and my friends by account number.
    private func everyone() async throws -> [String: Person] {
        var people: [String: Person] = [:]
        for friend in try await friendList() {
            people[String(OnlineIdentity.accountId(forUser: friend.userId))] =
                Person(onlineId: OnlineIdentity.onlineId(handle: friend.handle), presence: friend.presence, online: (friend.presence?.state ?? "offline") != "offline")
        }
        people[myAccount] = Person(onlineId: OnlineIdentity.onlineId(handle: me.handle), presence: nil, online: true)
        return people
    }

    private func friendList() async throws -> [Friend] {
        let time = now()
        if let kept = lock.withLock({ friends }), time.timeIntervalSince(kept.at) < OnlineUserProfile.keepFriends { return kept.list }
        struct List: Decodable { let friends: [Friend] }
        let list = try JSONDecoder().decode(List.self, from: try await service.call("GET", "me/friends", nil)).friends
        lock.withLock { friends = (time, list) }
        return list
    }

    private func profile(_ person: Person, isMe: Bool) -> [String: Any] {
        ["onlineId": person.onlineId, "aboutMe": "", "avatars": [Any](), "languages": isMe && !language.isEmpty ? [language] : [String](),
         "isPlus": false, "isOfficiallyVerified": false, "isMe": isMe]
    }

    private func presence(_ account: String, _ person: Person) -> [String: Any] {
        var platform: [String: Any] = ["onlineStatus": person.online ? "online" : "offline"]
        if person.online { platform["platform"] = "PS5" }
        return ["accountId": account, "availability": person.online ? "availableToPlay" : "unavailable", "primaryPlatformInfo": platform]
    }

    static func query(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if let name = parts.first, !name.isEmpty { fields[name] = parts.count > 1 ? parts[1] : "" }
        }
        return fields
    }

    private func json(_ object: [String: Any]) -> OnlineWire.WebReply {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return OnlineWire.WebReply(status: 200, headers: [.init("Content-Type", "application/json")], body: body)
    }

    private func problem(_ status: Int, _ message: String) -> OnlineWire.WebReply {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": ["code": status, "message": message]], options: [.sortedKeys])) ?? Data()
        return OnlineWire.WebReply(status: UInt16(clamping: status), headers: [.init("Content-Type", "application/json")], body: body)
    }
}
