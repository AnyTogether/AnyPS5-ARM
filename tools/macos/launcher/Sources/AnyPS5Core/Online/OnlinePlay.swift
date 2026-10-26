import Foundation

/// Online play for one game start: the bridge the game connects to, the web router onto
/// AnyTogether, and the transport that carries game packets to the other players. The account
/// the game sees is the signed-in AnyTogether user; the virtual address is the user's in the
/// current AnyTogether game session.
public final class OnlinePlay: @unchecked Sendable {
    public typealias TransportFactory = @Sendable (OnlinePeerContext) -> OnlinePeerTransport

    public let bridge: OnlineBridgeServer
    public let router: OnlineWebRouter
    public let transport: OnlinePeerTransport
    /// The game's streams between the bridge and the transport.
    public let streams: OnlineStreamRelay
    /// Where the engine writes its observation log (ANYPS5_ONLINE_LOG), when one was asked for.
    public let observationLog: URL?
    private let service: OnlineSessionService
    private let lock = NSLock()
    private let baseAccount: OnlineWire.Account
    private let userId: String?
    private var session: OnlineSessionView?
    private var following: String?
    private var observations: [String] = []

    /// `transport` makes the peer transport; without one, packets go over plain UDP
    /// (`OnlinePeerLink`) under `sessionKey`, which only tests and one network use.
    public init(service: OnlineSessionService, user: TogetherUser?, game: OnlineWebRouter.Game, sessionKey: Data = OnlineWire.randomBytes(32),
                locale: Locale = .current, platformGroups: Bool = true, observationLog: URL? = nil,
                signal: @escaping @Sendable (String, String, String, String, Data) -> Void = { _, _, _, _, _ in }, transport: TransportFactory? = nil) {
        let account = user.map { OnlinePlay.account(for: $0, locale: locale) } ?? .signedOut
        baseAccount = account
        userId = user?.id
        self.service = service
        self.observationLog = observationLog
        let refs = References()
        let context = OnlinePeerContext(deliver: { refs.bridge?.deliver($0) }, service: service, signal: signal,
                                        deliverStream: { refs.streams?.fromPeer($0, $1) }, peerGone: { refs.streams?.peerGone($0) })
        let streams = OnlineStreamRelay(toEngine: { refs.bridge?.deliver($0) }, toPeer: { refs.transport?.sendStream($1, to: $0) ?? false })
        let made = transport?(context) ?? OnlinePeerLink(sessionKey: sessionKey, ownAddress: 0) { refs.bridge?.deliver($0) }
        let profile = user.map { OnlineUserProfile(service: service, me: $0, language: account.language) }
        let playerSessions = user.map { _ in
            OnlinePlayerSessions(account: account.accountId, onlineId: account.onlineId) { event in refs.bridge?.push(event) }
        }
        let router = OnlineWebRouter(service: service, game: game, profile: profile, playerSessions: playerSessions, platformGroups: platformGroups) { view in
            guard let play = refs.play else { return }
            play.sessionChanged(view)
            Task { await play.follow(sessionId: view?.id) }
        }
        let bridge = OnlineBridgeServer(account: account, handlers: .init(
            web: { request in await refs.router?.handle(request) ?? .notOffered },
            datagram: { _ = refs.transport?.send($0) },
            stream: { refs.streams?.fromEngine($0) },
            observation: { line in refs.play?.keep(line) },
            engine: { hello in
                // A game that connects (again) or goes starts with no streams.
                refs.streams?.engineGone()
                if let hello { refs.router?.setEngineBuild(hello.build) }
            }))
        self.bridge = bridge
        self.router = router
        self.transport = made
        self.streams = streams
        refs.streams = streams
        refs.bridge = bridge
        refs.transport = made
        refs.router = router
        refs.play = self
    }

    /// The plain-UDP transport, when that is the one in use.
    public var link: OnlinePeerLink? { transport as? OnlinePeerLink }

    /// Starts listening for the game (and, with the plain-UDP transport, for peers); the result
    /// is what the game is started with.
    public func start(peerHost: String = "127.0.0.1", peerPort: UInt16 = 0) throws -> [String: String] {
        try bridge.start()
        try link?.start(host: peerHost, port: peerPort)
        var environment = bridge.environment
        if let observationLog { environment["ANYPS5_ONLINE_LOG"] = observationLog.path }
        return environment
    }

    public func stop() {
        bridge.stop()
        transport.stop()
    }

    public var currentSession: OnlineSessionView? { lock.withLock { session } }

    /// How each other player is reached now.
    public func links(_ done: @escaping @Sendable ([OnlinePeerLinkInfo]) -> Void) { transport.links(done) }

    /// The observation lines the game sent, newest last (at most 2000).
    public var observed: [String] { lock.withLock { observations } }

    /// Where a session member's launcher receives packets, for the plain-UDP transport.
    public func setEndpoint(of userId: String, _ endpoint: OnlinePeerLink.Endpoint?) {
        guard let address = lock.withLock({ session?.addresses[userId] }) else { return }
        link?.setPeer(address, at: endpoint)
    }

    /// Plays in AnyTogether game session `sessionId` (nil: in none): publishes this launcher as a
    /// member, so the others' signals reach it, and takes the session with every player's device.
    public func follow(sessionId: String?) async {
        lock.withLock { following = sessionId }
        guard let sessionId, userId != nil else { return sessionChanged(nil) }
        let body = Data(#"{"properties":{"online":1}}"#.utf8)
        let published = try? await service.call("PUT", "game-sessions/\(sessionId)/members/me", body)
        let data: Data?
        if let published { data = published } else { data = try? await service.call("GET", "game-sessions/\(sessionId)", nil) }
        guard lock.withLock({ following == sessionId }), let data, let view = try? JSONDecoder.together.decode(OnlineSessionView.self, from: data) else { return }
        sessionChanged(view.endedAt == nil ? view : nil)
    }

    /// The session changed on AnyTogether (someone joined, left or published): takes it again.
    public func refresh() async {
        guard let sessionId = lock.withLock({ following }) else { return }
        guard let data = try? await service.call("GET", "game-sessions/\(sessionId)", nil),
              let view = try? JSONDecoder.together.decode(OnlineSessionView.self, from: data),
              lock.withLock({ following == sessionId }) else { return }
        sessionChanged(view.endedAt == nil ? view : nil)
    }

    /// A signal from another player's launcher in the session followed now.
    public func receive(_ signal: OnlinePeerSignal, sessionId: String) {
        guard lock.withLock({ following == sessionId }) else { return }
        transport.receive(signal)
    }

    func sessionChanged(_ view: OnlineSessionView?) {
        lock.withLock { session = view }
        var account = baseAccount
        let addresses = view?.addresses ?? [:]
        let own = userId.flatMap { addresses[$0] } ?? 0
        account.address = account.signedIn ? own : 0
        bridge.setAccount(account)
        guard let view, let userId, own != 0 else { return transport.update(nil) }
        let devices = Dictionary((view.members ?? []).compactMap { member in member.device.map { (member.userId, $0) } }, uniquingKeysWith: { first, _ in first })
        transport.update(OnlinePeerSession(id: view.id, me: userId, addresses: addresses, devices: devices))
    }

    private func keep(_ line: String) {
        lock.withLock {
            observations.append(line)
            if observations.count > 2000 { observations.removeFirst(observations.count - 2000) }
        }
    }

    /// The account the game sees for an AnyTogether user (`OnlineIdentity`), with the Mac's
    /// country and language.
    public static func account(for user: TogetherUser, locale: Locale) -> OnlineWire.Account {
        let region = locale.region?.identifier.lowercased() ?? ""
        let language = locale.language.languageCode?.identifier ?? ""
        return OnlineWire.Account(signedIn: true, accountId: OnlineIdentity.accountId(forUser: user.id), onlineId: OnlineIdentity.onlineId(handle: user.handle),
                                  country: region.count == 2 ? region : "", language: language)
    }
}

private final class References: @unchecked Sendable {
    weak var bridge: OnlineBridgeServer?
    weak var transport: OnlinePeerTransport?
    weak var streams: OnlineStreamRelay?
    weak var router: OnlineWebRouter?
    weak var play: OnlinePlay?
}

/// The one online session of the running game, switched on with Settings → Online play
/// (experimental), stored as the `OnlinePlay` default. Off, nothing changes for the game.
public enum OnlinePlayHost {
    nonisolated(unsafe) private static var current: OnlinePlay?
    nonisolated(unsafe) private static var session: String?
    nonisolated(unsafe) private static var factory: OnlinePlay.TransportFactory?
    nonisolated(unsafe) private static var signaller: (@Sendable (String, String, String, String, Data) -> Void)?
    private static let lock = NSLock()

    public static let enabledKey = "OnlinePlay"
    /// Off answers every platform web API group "not offered" (a clean observation run).
    public static let platformGroupsKey = "OnlinePlayPlatformGroups"

    public static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    nonisolated(unsafe) private static var together: String?

    /// The Play Together session the next game starts in: online play is on for it whatever the
    /// setting, until that game ends (`stop`); the setting itself is left as the user chose.
    public static func playTogether(sessionId: String?) {
        lock.withLock { together = sessionId }
        follow(sessionId: sessionId)
    }

    public static var togetherSession: String? { lock.withLock { together } }

    /// Online play for the next game: the setting, or a Play Together session.
    public static var isOn: Bool { enabled || togetherSession != nil }

    static var platformGroups: Bool { UserDefaults.standard.object(forKey: platformGroupsKey) as? Bool ?? true }

    /// Where a title's observation log goes: one file per title, the last one kept as `.1`
    /// once it passes 20 MB.
    public static func observationLog(titleId: String, folder: URL = OnlinePlayHost.logFolder) -> URL {
        let safe = String(titleId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
        let file = folder.appendingPathComponent("\(safe.isEmpty ? "game" : safe).jsonl")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 20 * 1024 * 1024 {
            let old = file.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: file, to: old)
        }
        return file
    }

    public static var logFolder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/AnyPS5/Online")
    }

    /// How packets reach other players (the app sets the WebRTC one) and how signals leave.
    public static func configure(transport: @escaping OnlinePlay.TransportFactory, signal: @escaping @Sendable (String, String, String, String, Data) -> Void) {
        lock.withLock {
            factory = transport
            signaller = signal
        }
    }

    /// What a game is started with for online play, or nothing when it is off or fails to start.
    public static func environment(for game: Game, client: TogetherClient, engineBuild: String = "unknown") -> [String: String] {
        guard isOn else { return [:] }
        let (play, sessionId) = lock.withLock { () -> (OnlinePlay, String?) in
            current?.stop()
            let made = factory ?? { _ in OnlineNoTransport() }
            let signal = signaller ?? { _, _, _, _, _ in }
            let play = OnlinePlay(service: client, user: client.user,
                                  game: .init(titleId: game.titleID, gameVersion: game.version.isEmpty ? "0" : game.version, engineBuild: engineBuild),
                                  platformGroups: platformGroups, observationLog: observationLog(titleId: game.titleID), signal: signal, transport: made)
            current = play
            return (play, session)
        }
        guard let environment = try? play.start() else {
            lock.withLock { if current === play { current = nil } }
            return [:]
        }
        if let sessionId { Task { await play.follow(sessionId: sessionId) } }
        return environment
    }

    /// The AnyTogether game session the launcher keeps for the running game (nil: none).
    public static func follow(sessionId: String?) {
        let play = lock.withLock { () -> OnlinePlay? in
            guard session != sessionId else { return nil }
            session = sessionId
            return current
        }
        if let play { Task { await play.follow(sessionId: sessionId) } }
    }

    /// A socket event about game sessions: news of the followed one, or a signal in it.
    public static func handle(_ event: TogetherSocket.Event) {
        guard let play = lock.withLock({ current }) else { return }
        switch event.type {
        case "game_session.updated":
            Task { await play.refresh() }
        case "game_session.signal":
            guard let sessionId = event.data["sessionId"], let signal = OnlinePeerSignal(event: event.json) else { return }
            play.receive(signal, sessionId: sessionId)
        default:
            break
        }
    }

    /// The game ended; a Play Together session ends with it.
    public static func stop() {
        lock.withLock {
            current?.stop()
            current = nil
            together = nil
        }
    }

    public static var running: OnlinePlay? { lock.withLock { current } }
}
