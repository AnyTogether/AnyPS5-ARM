import Foundation

/// The launcher's socket to AnyTogether's realtime gateway (/rt): it says hello with the access
/// token, sends a heartbeat with the presence every 25 s, hands on the events, picks up what it
/// missed after a reconnect, and ends for good when the session is signed out elsewhere.
public final class TogetherSocket: @unchecked Sendable {
    public struct Event: Sendable {
        public let id: String
        public let type: String
        /// The event's data as the gateway sent it, JSON.
        public let json: Data

        public init(id: String, type: String, json: Data) {
            self.id = id
            self.type = type
            self.json = json
        }

        /// The data's top-level strings and numbers, as text.
        public var data: [String: String] {
            ((try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]).compactMapValues { $0 as? String ?? ($0 as? NSNumber)?.stringValue }
        }

        public func decode<T: Decodable>(_ type: T.Type = T.self) -> T? { try? JSONDecoder.together.decode(T.self, from: json) }
    }

    public enum Presence: Sendable, Equatable {
        case online
        case away
        case inGame(titleID: String, since: Date)
    }

    private let client: TogetherClient
    private let session: URLSession
    private let queue = DispatchQueue(label: "org.anyps5.together.socket")
    private var task: URLSessionWebSocketTask?
    private var lastEventID: String?
    private var presence: Presence = .online
    private var heartbeat: Timer?
    private var running = false
    private var attempt = 0
    private var typingSent: [String: Date] = [:]
    /// The public topics listened to, sent again after each reconnect.
    private var topics: [String] = []
    private let onEvent: @Sendable (Event) -> Void
    private let onSignedOut: @Sendable () -> Void

    public init(client: TogetherClient, session: URLSession = .shared, onEvent: @escaping @Sendable (Event) -> Void = { _ in },
                onSignedOut: @escaping @Sendable () -> Void) {
        self.client = client
        self.session = session
        self.onEvent = onEvent
        self.onSignedOut = onSignedOut
    }

    public func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            attempt = 0
            Task { await self.connect() }
        }
    }

    public func stop() {
        queue.sync {
            running = false
            task?.cancel(with: .normalClosure, reason: nil)
            task = nil
        }
        DispatchQueue.main.async { [weak self] in self?.heartbeat?.invalidate() }
    }

    /// What the friends see: sent at once and with every heartbeat.
    public func setPresence(_ presence: Presence) {
        queue.async { [self] in
            self.presence = presence
            sendHeartbeat()
        }
    }

    /// WebRTC signalling to one device of a peer in the same call; dropped while disconnected
    /// (the peer connection's own retries cover it).
    public func signal(to userId: String, device: String, call: String, kind: TogetherSignalKind, data: Any?) {
        let frame = TogetherSocket.signalFrame(to: userId, device: device, call: call, kind: kind, data: data)
        queue.async { [self] in task?.send(.string(String(decoding: frame, as: UTF8.self))) { _ in } }
    }

    /// The same between a share play's host and a viewer.
    public func signal(to userId: String, device: String, share: String, kind: TogetherShareSignal.Kind, data: Any?) {
        let frame = TogetherSocket.shareSignalFrame(to: userId, device: device, share: share, kind: kind, data: data)
        queue.async { [self] in task?.send(.string(String(decoding: frame, as: UTF8.self))) { _ in } }
    }

    /// The public topics to hear "changed" events of (the board, the public lists), replacing the
    /// ones before; [] for none. Sent now and again after a reconnect.
    public func watch(_ topics: [String]) {
        let clean = TogetherTopics.clean(topics)
        queue.async { [self] in
            guard clean != self.topics else { return }
            self.topics = clean
            sendTopics()
        }
    }

    private func sendTopics() {
        guard let task else { return }
        task.send(.string(String(decoding: TogetherTopics.frame(topics), as: UTF8.self))) { _ in }
    }

    private func connect() async {
        guard queue.sync(execute: { running }) else { return }
        do {
            let token = try await client.accessToken()
            var components = URLComponents(url: client.base, resolvingAgainstBaseURL: false)!
            components.scheme = components.scheme == "http" ? "ws" : "wss"
            components.path = "/rt"
            let task = session.webSocketTask(with: components.url!)
            queue.sync { self.task = task }
            task.resume()
            var hello: [String: String] = ["op": "hello", "token": token, "client": client.clientName]
            if let resume = queue.sync(execute: { lastEventID }) { hello["resume"] = resume }
            try await task.send(.string(String(decoding: try JSONSerialization.data(withJSONObject: hello), as: UTF8.self)))
            await receive(task)
        } catch let problem as TogetherProblem where problem.status == 401 {
            signedOut()
        } catch {
            retryLater()
        }
    }

    private func receive(_ task: URLSessionWebSocketTask) async {
        while true {
            do {
                let message = try await task.receive()
                guard case .string(let text) = message, let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
                handle(frame)
            } catch {
                break
            }
        }
        // 4001: the token was refused (refresh and try again); 4003: signed out elsewhere.
        switch task.closeCode.rawValue {
        case 4003: signedOut()
        default: retryLater()
        }
    }

    private func handle(_ frame: [String: Any]) {
        switch frame["op"] as? String {
        case "ready":
            queue.async { self.attempt = 0 }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.heartbeat?.invalidate()
                self.heartbeat = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in self?.queue.async { self?.sendHeartbeat() } }
            }
            queue.async {
                self.sendHeartbeat()
                if !self.topics.isEmpty { self.sendTopics() }
            }
        case "event":
            guard let event = TogetherSocket.event(frame) else { return }
            queue.async { self.lastEventID = event.id }
            onEvent(event)
        default:
            break
        }
    }

    /// An event frame as the gateway sends it: its data kept whole, nested objects and all (a
    /// party, a call's peers, a signal's description), for `decode`.
    static func event(_ frame: [String: Any]) -> Event? {
        guard frame["op"] as? String == "event", let id = frame["id"] as? String, let type = frame["type"] as? String else { return nil }
        let json = frame["data"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed) } ?? Data("{}".utf8)
        return Event(id: id, type: type, json: json)
    }

    /// "I am typing" in a conversation, to its other members; at most every two seconds (the
    /// gateway drops more).
    public func typing(in conversation: String, at now: Date = Date()) {
        queue.async { [self] in
            if let last = typingSent[conversation], now.timeIntervalSince(last) < TogetherTyping.every { return }
            typingSent[conversation] = now
            let frame: [String: Any] = ["op": "typing", "conversation": conversation]
            guard let data = try? JSONSerialization.data(withJSONObject: frame) else { return }
            task?.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        }
    }

    private func sendHeartbeat() {
        guard let task else { return }
        var state: [String: String]
        switch presence {
        case .online: state = ["state": "online"]
        case .away: state = ["state": "away"]
        case .inGame(let titleID, let since): state = ["state": "in_game", "titleId": titleID, "since": ISO8601DateFormatter().string(from: since)]
        }
        let frame: [String: Any] = ["op": "heartbeat", "presence": state]
        guard let data = try? JSONSerialization.data(withJSONObject: frame) else { return }
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    private func retryLater() {
        let delay: Double = queue.sync {
            guard running else { return -1 }
            attempt += 1
            // 1, 2, 4 … 30 s, with some spread so a server restart is not met by everyone at once.
            return min(30, pow(2, Double(attempt - 1))) * Double.random(in: 0.8 ... 1.2)
        }
        guard delay >= 0 else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            await self.connect()
        }
    }

    private func signedOut() {
        queue.sync { running = false }
        DispatchQueue.main.async { [weak self] in self?.heartbeat?.invalidate() }
        client.forget()
        onSignedOut()
    }
}
