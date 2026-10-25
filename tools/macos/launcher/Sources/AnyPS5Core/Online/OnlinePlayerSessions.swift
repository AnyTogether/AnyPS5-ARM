import Foundation

/// The platform's Player Sessions (`sessionManager` web API group, `/v1/playerSessions…`),
/// answered here for one game run and kept in memory. Nothing goes to Sony.
///
/// Games make a Player Session when they host, even when their own game traffic goes elsewhere:
/// Human Fall Flat (PPSA02429) hosts through Photon, but makes a `sessionManager` push context
/// and a Player Session first, and shows "Failed to Start a Server" when either fails. Paths
/// are the ones the game's `libSceNpCppWebApi` names; the bodies follow public documentation of
/// the console network's Session Manager API and are unverified, so every request body is in the
/// title's observation log (the engine writes it with the request).
///
/// Changes the game makes itself bring it no push events (the platform does not tell a member
/// about its own change). Changes from elsewhere (`playerJoined`, `playerLeft`) are pushed to
/// every push context the session's players registered, with the data types the game listens
/// for (`psn:sessionManager:ps:m:players:created`, …).
public final class OnlinePlayerSessions: @unchecked Sendable {
    public static let group = "sessionManager"
    static let platform = "PS5"
    static let maxSessions = 64

    struct Player {
        var accountId: String
        var platform: String
        var onlineId: String
        var joined: Int64
        var pushContexts: [String]
        var customData1: Any?
    }

    struct Session {
        let id: String
        let created: Int64
        var settings: [String: Any]
        var players: [Player]
        var spectators: [Player]
        var leader: String
        var joinableSpecifiedUsers: [String]
        var invitations: [[String: Any]]
    }

    /// What the game may set at creation and with PATCH.
    static let settable: Set<String> = ["maxPlayers", "maxSpectators", "joinDisabled", "supportedPlatforms", "sessionName", "localizedSessionName",
                                        "joinableUserType", "invitableUserType", "leaderPrivileges", "exclusiveLeaderPrivileges",
                                        "disableSystemUiMenu", "swapSupported", "customData1", "customData2", "conditionalSession"]

    private let me: String
    private let onlineId: String
    private let now: @Sendable () -> Date
    private let push: @Sendable (OnlineWire.PushEvent) -> Void
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    private var order: [String] = []

    /// `account` and `onlineId` are the signed-in player's (`OnlineIdentity`); `push` hands an
    /// event to the game (the bridge).
    public init(account: UInt64, onlineId: String, now: @escaping @Sendable () -> Date = Date.init,
                push: @escaping @Sendable (OnlineWire.PushEvent) -> Void = { _ in }) {
        me = String(account)
        self.onlineId = onlineId
        self.now = now
        self.push = push
    }

    /// The sessions open now, as GET answers them.
    public var openSessions: [[String: Any]] { lock.withLock { order.compactMap { sessions[$0].map(view) } } }

    public var sessionIds: [String] { lock.withLock { order } }

    public func handle(_ request: OnlineWire.WebRequest) -> OnlineWire.WebReply {
        let split = request.path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let parts = split.first.map { $0.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) } } ?? []
        let query = OnlineUserProfile.query(split.count > 1 ? String(split[1]) : "")
        let method = request.method.uppercased()
        guard parts.count >= 2, parts[0] == "v1" else { return problem(404, "No such sessionManager call") }
        let body: [String: Any]
        do { body = try object(request.body) } catch { return problem(400, "The body must be a JSON object") }

        if parts[1] == "users", parts.count == 4 {
            guard isMe(parts[2]) else { return problem(403, "Only your own sessions are offered") }
            switch (method, parts[3]) {
            case ("GET", "playerSessions"):
                let mine = lock.withLock { order.compactMap { sessions[$0] }.filter { $0.players.contains { $0.accountId == me } || $0.spectators.contains { $0.accountId == me } } }
                return json(200, ["playerSessions": mine.map { ["sessionId": $0.id, "platform": OnlinePlayerSessions.platform] }])
            case ("GET", "playerSessionsInvitations"):
                return json(200, ["invitations": [Any]()])
            default:
                return problem(404, "No such sessionManager call")
            }
        }
        guard parts[1] == "playerSessions" else { return problem(404, "No such sessionManager call") }
        switch (method, parts.count) {
        case ("POST", 2):
            return create(body)
        case ("GET", 3):
            let wanted = parts[2].split(separator: ",").map(String.init)
            let found = lock.withLock { wanted.compactMap { sessions[$0].map(view) } }
            return found.isEmpty ? problem(404, "No such player session") : json(200, ["playerSessions": found])
        case ("PATCH", 3):
            return change(parts[2]) { session in
                for (key, value) in body where OnlinePlayerSessions.settable.contains(key) { session.settings[key] = value }
                return nil
            }
        case ("DELETE", 3):
            let removed = lock.withLock { () -> Bool in
                guard sessions.removeValue(forKey: parts[2]) != nil else { return false }
                order.removeAll { $0 == parts[2] }
                return true
            }
            return removed ? OnlineWire.WebReply(status: 204) : problem(404, "No such player session")
        default:
            break
        }
        guard parts.count >= 4 else { return problem(404, "No such sessionManager call") }
        let id = parts[2]
        switch (method, parts.count, parts[3]) {
        case ("POST", 5, "member") where parts[4] == "players" || parts[4] == "spectators":
            let spectators = parts[4] == "spectators"
            let joining = players(body[parts[4]])
            return change(id) { session in
                for player in joining {
                    session.players.removeAll { $0.accountId == player.accountId }
                    session.spectators.removeAll { $0.accountId == player.accountId }
                    if spectators { session.spectators.append(player) } else { session.players.append(player) }
                }
                return json(200, [parts[4]: joining.map { ["accountId": $0.accountId, "platform": $0.platform] }])
            }
        case ("DELETE", 5, "members"):
            let who = isMe(parts[4]) ? me : parts[4]
            // Leaving a session one is not in (or one that is gone) is done already: games leave
            // the last session they knew before they host again.
            lock.withLock {
                guard var session = sessions[id] else { return }
                session.players.removeAll { $0.accountId == who }
                session.spectators.removeAll { $0.accountId == who }
                if session.players.isEmpty && session.spectators.isEmpty {
                    sessions[id] = nil
                    order.removeAll { $0 == id }
                    return
                }
                if session.leader == who { session.leader = session.players.first?.accountId ?? session.spectators.first?.accountId ?? "" }
                sessions[id] = session
            }
            return OnlineWire.WebReply(status: 204)
        case ("PUT", 4, "leader"):
            guard let account = accountId(body["accountId"]) else { return problem(400, "accountId is required") }
            return change(id) { session in
                guard session.players.contains(where: { $0.accountId == account }) else { return self.problem(400, "The leader must be a player") }
                session.leader = account
                return nil
            }
        case ("POST", 4, "invitations"):
            var made: [[String: Any]] = []
            let reply = change(id) { session in
                for invitation in body["invitations"] as? [[String: Any]] ?? [] {
                    let to = (invitation["to"] as? [String: Any]).flatMap { self.accountId($0["accountId"]) } ?? ""
                    let entry: [String: Any] = ["invitationId": UUID().uuidString.lowercased(), "to": ["accountId": to]]
                    session.invitations.append(entry)
                    made.append(["invitationId": entry["invitationId"] as Any])
                }
                return nil
            }
            return reply.status == 204 ? json(200, ["invitations": made]) : reply
        case ("POST", 4, "joinableSpecifiedUsers"):
            let users = (body["joinableSpecifiedUsers"] as? [[String: Any]] ?? []).compactMap { accountId($0["accountId"]) }
            let reply = change(id) { session in
                for user in users where !session.joinableSpecifiedUsers.contains(user) { session.joinableSpecifiedUsers.append(user) }
                return nil
            }
            return reply.status == 204 ? json(200, ["joinableSpecifiedUsers": users.map { ["accountId": $0] }]) : reply
        case ("DELETE", 4, "joinableSpecifiedUsers"):
            let users = Set((query["accountIds"] ?? "").split(separator: ",").map(String.init))
            return change(id) { session in
                session.joinableSpecifiedUsers.removeAll { users.contains($0) }
                return nil
            }
        case ("POST", 4, "sessionMessage"):
            return change(id) { _ in nil }
        default:
            return problem(404, "No such sessionManager call")
        }
    }

    /// Another player joined session `sessionId` (from outside this game): kept, and pushed to
    /// the game as `psn:sessionManager:ps:m:players:created`. False when there is no such session.
    @discardableResult
    public func playerJoined(sessionId: String, account: UInt64, onlineId: String) -> Bool {
        let player = Player(accountId: String(account), platform: OnlinePlayerSessions.platform, onlineId: onlineId, joined: millis(), pushContexts: [], customData1: nil)
        guard let contexts = lock.withLock({ () -> [String]? in
            guard var session = sessions[sessionId] else { return nil }
            let contexts = pushContexts(session)
            session.players.removeAll { $0.accountId == player.accountId }
            session.players.append(player)
            sessions[sessionId] = session
            return contexts
        }) else { return false }
        let data: [String: Any] = ["playerSessionId": sessionId,
                                   "member": ["players": [["accountId": player.accountId, "platform": player.platform, "onlineId": onlineId]]]]
        send("psn:sessionManager:ps:m:players:created", data, to: contexts, from: account, fromOnlineId: onlineId)
        return true
    }

    /// Another player left session `sessionId`: pushed as `psn:sessionManager:ps:m:players:deleted`
    /// (and `…:ps:leader:updated` when they led it).
    public func playerLeft(sessionId: String, account: UInt64) {
        let who = String(account)
        guard let (contexts, newLeader, onlineId) = lock.withLock({ () -> ([String], String?, String)? in
            guard var session = sessions[sessionId], let leaving = session.players.first(where: { $0.accountId == who }) else { return nil }
            session.players.removeAll { $0.accountId == who }
            var leader: String?
            if session.leader == who, let next = session.players.first?.accountId {
                session.leader = next
                leader = next
            }
            sessions[sessionId] = session
            return (pushContexts(session), leader, leaving.onlineId)
        }) else { return }
        send("psn:sessionManager:ps:m:players:deleted", ["playerSessionId": sessionId, "member": ["players": [["accountId": who, "platform": OnlinePlayerSessions.platform]]]],
             to: contexts, from: account, fromOnlineId: onlineId)
        if let newLeader {
            send("psn:sessionManager:ps:leader:updated", ["playerSessionId": sessionId, "leader": ["accountId": newLeader, "platform": OnlinePlayerSessions.platform]],
                 to: contexts, from: account, fromOnlineId: onlineId)
        }
    }

    // MARK: - Requests

    private func create(_ body: [String: Any]) -> OnlineWire.WebReply {
        let asked = body["playerSessions"] as? [[String: Any]] ?? []
        guard !asked.isEmpty else { return problem(400, "playerSessions is required") }
        var made: [[String: Any]] = []
        let full = lock.withLock { () -> Bool in
            guard sessions.count + asked.count <= OnlinePlayerSessions.maxSessions else { return true }
            for fields in asked {
                let member = fields["member"] as? [String: Any] ?? [:]
                var playing = players(member["players"])
                let watching = players(member["spectators"])
                if playing.isEmpty && watching.isEmpty { playing = [Player(accountId: me, platform: OnlinePlayerSessions.platform, onlineId: onlineId, joined: millis(), pushContexts: [], customData1: nil)] }
                var settings = fields.filter { OnlinePlayerSessions.settable.contains($0.key) }
                if settings["maxPlayers"] == nil { settings["maxPlayers"] = max(playing.count, 1) }
                if settings["maxSpectators"] == nil { settings["maxSpectators"] = 0 }
                let session = Session(id: UUID().uuidString.lowercased(), created: millis(), settings: settings, players: playing, spectators: watching,
                                      leader: playing.first?.accountId ?? watching.first?.accountId ?? me,
                                      joinableSpecifiedUsers: (fields["joinableSpecifiedUsers"] as? [[String: Any]] ?? []).compactMap { accountId($0["accountId"]) },
                                      invitations: [])
                sessions[session.id] = session
                order.append(session.id)
                made.append(["sessionId": session.id,
                             "member": ["players": playing.map { ["accountId": $0.accountId, "platform": $0.platform] },
                                        "spectators": watching.map { ["accountId": $0.accountId, "platform": $0.platform] }]])
            }
            return false
        }
        if full { return problem(429, "Too many player sessions") }
        return json(200, ["playerSessions": made])
    }

    /// Runs `apply` on session `id`; its reply, or 204 when it returns nil.
    private func change(_ id: String, _ apply: (inout Session) -> OnlineWire.WebReply?) -> OnlineWire.WebReply {
        lock.withLock {
            guard var session = sessions[id] else { return problem(404, "No such player session") }
            let reply = apply(&session)
            sessions[id] = session
            return reply ?? OnlineWire.WebReply(status: 204)
        }
    }

    private func players(_ value: Any?) -> [Player] {
        (value as? [[String: Any]] ?? []).compactMap { entry in
            guard let account = accountId(entry["accountId"]) else { return nil }
            let platform = (entry["platform"] as? String).flatMap { $0 == "me" || $0.isEmpty ? nil : $0 } ?? OnlinePlayerSessions.platform
            let contexts = (entry["pushContexts"] as? [[String: Any]] ?? []).compactMap { $0["pushContextId"] as? String }
            return Player(accountId: account, platform: platform, onlineId: account == me ? onlineId : "", joined: millis(), pushContexts: contexts,
                          customData1: entry["customData1"])
        }
    }

    /// An account in a body: "me", our number, or another player's number (string or number).
    private func accountId(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return isMe(text) ? me : text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func isMe(_ who: String) -> Bool { who == "me" || who.hasPrefix("local_") || who == me }

    private func pushContexts(_ session: Session) -> [String] {
        (session.players + session.spectators).filter { $0.accountId == me }.flatMap(\.pushContexts)
    }

    private func send(_ dataType: String, _ data: [String: Any], to contexts: [String], from: UInt64, fromOnlineId: String) {
        let body = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])) ?? Data("{}".utf8)
        let targets = contexts.isEmpty ? [""] : contexts
        for context in targets {
            push(OnlineWire.PushEvent(service: OnlinePlayerSessions.group, pushContextId: context, dataType: dataType, data: body,
                                      to: UInt64(me) ?? 0, from: from, fromOnlineId: String(fromOnlineId.prefix(16))))
        }
    }

    private func view(_ session: Session) -> [String: Any] {
        func member(_ player: Player) -> [String: Any] {
            var entry: [String: Any] = ["accountId": player.accountId, "platform": player.platform, "joinTimestamp": String(player.joined)]
            if !player.onlineId.isEmpty { entry["onlineId"] = player.onlineId }
            if let custom = player.customData1 { entry["customData1"] = custom }
            return entry
        }
        var fields = session.settings
        fields["sessionId"] = session.id
        fields["createdTimestamp"] = String(session.created)
        fields["member"] = ["players": session.players.map(member), "spectators": session.spectators.map(member)]
        fields["leader"] = ["accountId": session.leader, "platform": OnlinePlayerSessions.platform]
        fields["joinableSpecifiedUsers"] = session.joinableSpecifiedUsers.map { ["accountId": $0] }
        if fields["joinDisabled"] == nil { fields["joinDisabled"] = false }
        if fields["supportedPlatforms"] == nil { fields["supportedPlatforms"] = [OnlinePlayerSessions.platform] }
        return fields
    }

    private func millis() -> Int64 { Int64(now().timeIntervalSince1970 * 1000) }

    private func object(_ body: Data) throws -> [String: Any] {
        guard !body.isEmpty else { return [:] }
        guard let fields = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        return fields
    }

    private func json(_ status: UInt16, _ object: [String: Any]) -> OnlineWire.WebReply {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return OnlineWire.WebReply(status: status, headers: [.init("Content-Type", "application/json")], body: body)
    }

    private func problem(_ status: Int, _ message: String) -> OnlineWire.WebReply {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": ["code": status, "message": message]], options: [.sortedKeys])) ?? Data()
        return OnlineWire.WebReply(status: UInt16(clamping: status), headers: [.init("Content-Type", "application/json")], body: body)
    }
}
