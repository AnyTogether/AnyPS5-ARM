import XCTest
@testable import AnyPS5Core

/// The launcher's AnyTogether client in the cross-client scenarios that the server's repository
/// runs (AnyTogether's e2e/): with ANYTOGETHER_E2E_BUS and ANYTOGETHER_E2E_URL set, this test
/// takes commands from the scenario script and runs each with the real client (TogetherClient,
/// TogetherSocket, TogetherInbox, TogetherTyping, TogetherSync) against the local stack, while the
/// phone, the Windows/Linux launcher and the website do the same. Without them it is skipped.
final class TogetherCrossClientTests: XCTestCase {
    func testDriveTheLauncherFromTheCrossClientScenarios() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let bus = environment["ANYTOGETHER_E2E_BUS"].flatMap(URL.init(string:)),
              let base = environment["ANYTOGETHER_E2E_URL"].flatMap(URL.init(string:)) else { throw XCTSkip("no cross-client run") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("together-e2e-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try await LauncherDriver(base: base, folder: folder).run(bus: bus, role: environment["ANYTOGETHER_E2E_ROLE"] ?? "swift")
    }
}

/// One signed-in launcher (or one waiting to be): its client, its socket and what the socket said.
private final class DrivenAccount: @unchecked Sendable {
    let client: TogetherClient
    let sync: TogetherSync
    var socket: TogetherSocket?
    var events: [(type: String, json: Data)] = []
    var signedOut = false
    var inbox: TogetherInbox?
    var typing = TogetherTyping()
    let lock = NSLock()

    init(client: TogetherClient, sync: TogetherSync) {
        self.client = client
        self.sync = sync
    }
}

private struct DriverError: Error { let message: String }

private final class LauncherDriver: @unchecked Sendable {
    let base: URL
    let folder: URL
    private var accounts: [String: DrivenAccount] = [:]
    private let lock = NSLock()
    private let http: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    init(base: URL, folder: URL) {
        self.base = base
        self.folder = folder
    }

    func account(_ name: String) -> DrivenAccount {
        lock.withLock {
            if let known = accounts[name] { return known }
            let client = TogetherClient(base: base, store: TokenStore(file: folder.appendingPathComponent("\(name)/session.json")), clientName: "launcher-macos/e2e")
            let made = DrivenAccount(client: client, sync: TogetherSync(client: client, folder: folder.appendingPathComponent("\(name)/sync"), deviceName: "E2E Mac \(name)", model: "Mac15,9"))
            accounts[name] = made
            return made
        }
    }

    // MARK: The bus

    func run(bus: URL, role: String) async throws {
        try await post(bus.appendingPathComponent("hello"), ["role": role])
        var done = false
        while !done {
            var request = URLRequest(url: URL(string: bus.appendingPathComponent("next").absoluteString + "?role=\(role)")!)
            request.timeoutInterval = 60
            let (data, response) = try await http.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let command = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = command["id"] as? String, let name = command["cmd"] as? String else { continue }
            let args = command["args"] as? [String: Any] ?? [:]
            if name == "done" {
                done = true
                try await post(bus.appendingPathComponent("result"), ["id": id, "ok": true, "value": NSNull()])
                continue
            }
            Task {
                var answer: [String: Any] = ["id": id]
                do {
                    answer["value"] = Self.plain(try await self.handle(name, args))
                    answer["ok"] = true
                } catch let problem as TogetherProblem {
                    answer["ok"] = false
                    answer["error"] = ["status": problem.status, "code": problem.code, "message": problem.title]
                } catch let error as DriverError {
                    answer["ok"] = false
                    answer["error"] = ["message": error.message]
                } catch {
                    answer["ok"] = false
                    answer["error"] = ["message": "\(error)"]
                }
                try? await self.post(bus.appendingPathComponent("result"), answer)
            }
        }
        for account in lock.withLock({ Array(accounts.values) }) { account.socket?.stop() }
    }

    private func post(_ url: URL, _ body: [String: Any]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await http.data(for: request)
    }

    // MARK: Commands

    func handle(_ name: String, _ args: [String: Any]) async throws -> Any? {
        let who = account(args["as"] as? String ?? "main")
        let client = who.client
        func string(_ key: String) throws -> String {
            guard let value = args[key] as? String else { throw DriverError(message: "\(name): \(key) missing") }
            return value
        }
        func int(_ key: String) throws -> Int {
            guard let value = args[key] as? NSNumber else { throw DriverError(message: "\(name): \(key) missing") }
            return value.intValue
        }
        func bool(_ key: String) -> Bool { (args[key] as? NSNumber)?.boolValue ?? false }
        func strings(_ key: String) -> [String] { args[key] as? [String] ?? [] }

        switch name {
        // Signing in
        case "emailStart": try await client.startEmail(try string("email")); return nil
        case "emailVerify": return try await client.verifyEmail(try string("email"), code: try string("code"))
        case "handoffStart": return try await client.startHandoff(deviceName: try string("deviceName"))
        case "handoffWait":
            return try await client.waitForApproval(.handoff(id: try string("handoffId"), secret: try string("secret")), every: .milliseconds(500), until: Date().addingTimeInterval(60))
        case "handoffApprove": try await client.approveHandoff(try string("id")); return nil
        case "deviceStart": return try await client.startDeviceCode(deviceName: try string("deviceName"))
        case "deviceWait":
            return try await client.waitForApproval(.device(code: try string("deviceCode")), every: .seconds(Double((args["interval"] as? NSNumber)?.intValue ?? 1)), until: Date().addingTimeInterval(90))
        case "user": return client.user
        case "me": return try await client.me()
        case "signOut": who.socket?.stop(); await client.signOut(); return nil

        // The socket
        case "socketStart":
            guard who.socket == nil else { return nil }
            let socket = TogetherSocket(client: client, onEvent: { [weak self, weak who] event in
                guard let who else { return }
                who.lock.withLock { who.events.append((event.type, event.json)) }
                self?.apply(event, to: who)
            }, onSignedOut: { [weak who] in who?.lock.withLock { who?.signedOut = true } })
            who.socket = socket
            socket.start()
            return nil
        case "socketStop": who.socket?.stop(); who.socket = nil; return nil
        case "signedOut": return who.lock.withLock { who.signedOut }
        case "events":
            let since = (args["since"] as? NSNumber)?.intValue ?? 0
            return who.lock.withLock { () -> [String: Any] in
                let slice = who.events.count > since ? Array(who.events[since...]) : []
                return ["next": who.events.count, "events": slice.map { ["type": $0.type, "data": (try? JSONSerialization.jsonObject(with: $0.json, options: .fragmentsAllowed)) ?? NSNull()] }]
            }
        case "presence":
            let state = try string("state")
            who.socket?.setPresence(state == "in_game" ? .inGame(titleID: try string("titleId"), since: Date()) : state == "away" ? .away : .online)
            return nil
        case "typing": who.socket?.typing(in: try string("conversation")); return nil
        case "signal":
            who.socket?.signal(to: try string("to"), device: try string("device"), call: try string("call"), kind: TogetherSignalKind(rawValue: try string("kind"))!, data: args["data"])
            return nil

        // Friends
        case "friends": return try await client.friends()
        case "requests": return try await client.friendRequests()
        case "askFriend": return try await client.askFriend(try string("handle"))
        case "answerFriend": try await client.answerFriend(try string("userId"), accept: bool("accept")); return nil
        case "removeFriend": try await client.removeFriend(try string("userId")); return nil
        case "search": return try await client.searchPeople(try string("q"))

        // Messages, through the launcher's own inbox and typing state
        case "conversations": return try await client.conversations()
        case "unread": return try await client.unreadMessages()
        case "conversationWith": return try await client.conversation(with: try string("userId"))
        case "group": return try await client.startGroup(with: strings("userIds"), title: args["title"] as? String)
        case "messages": return try await client.messages(in: try string("conversationId")).messages
        case "send": return try await client.send(try string("text"), in: try string("conversationId"))
        case "markRead": try await client.markRead(try string("conversationId"), upTo: try int("seq")); return nil
        case "inboxLoad":
            let list = try await client.conversations()
            who.lock.withLock { who.inbox = TogetherInbox(me: client.user?.id ?? "", conversations: list) }
            return nil
        case "inbox":
            return who.lock.withLock { () -> [String: Any] in
                guard let inbox = who.inbox else { return [:] }
                return ["unread": inbox.unread, "conversations": inbox.conversations.map { (c: TogetherConversation) -> [String: Any] in ["id": c.id, "kind": c.kind, "unread": c.unread, "lastSeq": c.lastSeq, "last": c.lastMessage?.text ?? NSNull()] }]
            }
        case "typingWho": return who.lock.withLock { who.typing.who(in: (args["conversation"] as? String) ?? "") }

        // Parties
        case "myParty":
            let mine = try await client.myParty()
            return ["party": Self.plain(mine.party) ?? NSNull(), "invites": Self.plain(mine.invites) ?? []]
        case "startParty": return try await client.startParty(open: bool("open"))
        case "invite": return try await client.invite(strings("userIds"), to: try string("partyId"))
        case "joinParty": return try await client.joinParty(try string("partyId"))
        case "declineParty": try await client.declineParty(try string("partyId")); return nil
        case "leaveParty": try await client.leaveParty(try string("partyId")); return nil
        case "kick": try await client.kick(try string("userId"), from: try string("partyId")); return nil
        case "makeLeader": return try await client.makeLeader(try string("userId"), of: try string("partyId"))

        // Calls
        case "joinCall":
            let join = try await client.joinCall(party: try string("partyId"))
            return ["join": Self.plain(join) ?? NSNull(), "peersToCall": Self.plain(join.peersToCall(me: client.user?.id ?? "")) ?? []]
        case "callFriend": return try await client.call(friend: try string("userId"))
        case "answerCall":
            let join = try await client.answerCall(try string("callId"))
            return ["join": Self.plain(join) ?? NSNull(), "peersToCall": Self.plain(join.peersToCall(me: client.user?.id ?? "")) ?? []]
        case "declineCall": try await client.declineCall(try string("callId")); return nil
        case "setMuted": try await client.setMuted(bool("muted"), in: try string("callId")); return nil
        case "leaveCall": try await client.leaveCall(try string("callId")); return nil
        case "iceServers": return try await client.iceServers()
        case "decodeSignals":
            // The signals received so far, as the launcher's voice reads them.
            return who.lock.withLock {
                who.events.filter { $0.type == "signal" }.compactMap { try? JSONDecoder.together.decode(TogetherSignal.self, from: $0.json) }
                    .map { ["call": $0.call, "from": $0.from, "device": $0.device, "kind": $0.kind.rawValue, "sdp": $0.description?.sdp ?? NSNull(), "type": $0.description?.type ?? NSNull(), "candidate": $0.candidate?.candidate ?? NSNull(), "sdpMid": $0.candidate?.sdpMid ?? NSNull(), "sdpMLineIndex": $0.candidate.flatMap { $0.sdpMLineIndex.map { Int($0) } } ?? NSNull()] as [String: Any] }
            }
        case "decodeMutes":
            return who.lock.withLock {
                who.events.filter { $0.type == "call.updated" || $0.type == "call.muted" }.compactMap { try? JSONDecoder.together.decode(TogetherMuteChange.self, from: $0.json) }
            }

        // Profiles and sync
        case "myProfile": return try await client.myProfile()
        case "privacy":
            return try await client.updatePrivacy(TogetherPrivacy.Section(rawValue: try string("section"))!, to: TogetherVisibility(rawValue: try string("visibility"))!)
        case "profilePage": return try await client.profilePage(try string("handle"))
        case "syncPlay":
            let titleId = try string("titleId")
            let seconds = Double(try int("seconds"))
            who.sync.recordSession(titleId: titleId, gameName: try string("gameName"), startedAt: Date().addingTimeInterval(-seconds), endedAt: Date(), exit: "normal")
            if let trophies = args["trophies"] as? [[String: Any]] {
                who.sync.recordTrophies(.init(titleId: titleId, gameName: try string("gameName"), language: "en", trophies: trophies.map {
                    .init(id: ($0["id"] as? NSNumber)?.intValue ?? 0, grade: $0["grade"] as? String ?? "bronze", hidden: ($0["hidden"] as? NSNumber)?.boolValue ?? false,
                          name: $0["name"] as? String ?? "", detail: $0["detail"] as? String ?? "", earnedAt: ($0["earned"] as? NSNumber)?.boolValue == true ? Date().addingTimeInterval(-60) : nil)
                }))
            }
            try await who.sync.flush()
            return ["empty": who.sync.isEmpty]

        // Game sessions
        case "openGame":
            return try await client.openGameSession(titleId: try string("titleId"), gameVersion: try string("gameVersion"), engineBuild: try string("engineBuild"), capacity: try int("capacity"), joinable: args["joinable"] as? Bool ?? true)
        case "myGame":
            let mine = try await client.myGameSession()
            return ["session": Self.plain(mine.session) ?? NSNull(), "invites": Self.plain(mine.invites) ?? []]
        case "game": return try await client.gameSession(try string("id"))
        case "updateGame": return try await client.updateGameSession(try string("id"), joinable: bool("joinable"))
        case "joinGame": return try await client.joinGameSession(try string("id"), gameVersion: try string("gameVersion"), engineBuild: try string("engineBuild"))
        case "inviteGame": try await client.inviteToGame(strings("userIds"), session: try string("id")); return nil
        case "leaveGame": try await client.leaveGameSession(try string("id")); return nil
        case "endGame": try await client.endGameSession(try string("id")); return nil

        // Anything else the API has, with the client's session
        case "api":
            let data = try await client.authorized(try string("method"), try string("path"), args["body"])
            return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        case "token": return try await client.accessToken()
        default: throw DriverError(message: "unknown command \(name)")
        }
    }

    /// What the launcher's views do with an event: messages into the inbox, typing shown.
    private func apply(_ event: TogetherSocket.Event, to who: DrivenAccount) {
        who.lock.withLock {
            switch event.type {
            case "message.created", "message.updated", "message.deleted":
                guard let message = event.decode(TogetherMessage.self) else { return }
                if event.type == "message.created", let author = message.authorId { who.typing.wrote(author, in: message.conversationId) }
                // A conversation the inbox does not know yet: read the list again, as the launcher does.
                if who.inbox?.apply(message, open: nil) == false { reload(who) }
            case "conversation.read":
                let data = event.data
                guard let id = data["conversationId"], let user = data["userId"], let seq = data["upToSeq"].flatMap(Int.init) else { return }
                who.inbox?.read(id, by: user, upTo: seq)
            case "typing":
                let data = event.data
                guard let id = data["conversationId"], let user = data["userId"], user != who.client.user?.id else { return }
                who.typing.typing(user, in: id)
            case "conversation.updated": reload(who)
            default: break
            }
        }
    }

    private func reload(_ who: DrivenAccount) {
        Task {
            guard let list = try? await who.client.conversations() else { return }
            who.lock.withLock { who.inbox = TogetherInbox(me: who.client.user?.id ?? "", conversations: list) }
        }
    }

    // MARK: Answers as JSON

    /// Any value the client returns as plain JSON: Encodable ones as they encode, the rest
    /// (Decodable-only models) by their stored properties.
    static func plain(_ value: Any?) -> Any? {
        guard let value else { return NSNull() }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let inner = mirror.children.first?.value else { return NSNull() }
            return plain(inner)
        }
        switch value {
        case is NSNull: return value
        case let text as String: return text
        case let number as Bool: return number
        case let number as Int: return number
        case let number as Int32: return number
        case let number as Double: return number
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let json as TogetherJSON:
            return (try? JSONEncoder().encode(json)).flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        case let list as [Any]: return list.map { plain($0) ?? NSNull() }
        case let map as [String: Any]: return map.mapValues { plain($0) ?? NSNull() }
        default: break
        }
        switch mirror.displayStyle {
        case .enum:
            guard let payload = mirror.children.first else { return "\(value)" }
            return [payload.label ?? "value": plain(payload.value) ?? NSNull()]
        case .dictionary:
            var object: [String: Any] = [:]
            for child in mirror.children {
                let pair = Array(Mirror(reflecting: child.value).children)
                if pair.count == 2 { object["\(pair[0].value)"] = plain(pair[1].value) ?? NSNull() }
            }
            return object
        case .struct, .class, .tuple:
            var object: [String: Any] = [:]
            for child in mirror.children { if let label = child.label { object[label] = plain(child.value) ?? NSNull() } }
            return object
        default:
            return "\(value)"
        }
    }
}
