import CryptoKit
import Foundation

/// Online play for one game start: the bridge the game connects to, the web router onto
/// AnyTogether's game sessions, and the peer link that carries game packets to the other
/// players. The account the game sees is the signed-in AnyTogether user; the virtual address is
/// the user's place in the current session.
public final class OnlinePlay: @unchecked Sendable {
    public let bridge: OnlineBridgeServer
    public let router: OnlineWebRouter
    public let link: OnlinePeerLink
    private let lock = NSLock()
    private let baseAccount: OnlineWire.Account
    private let userId: String?
    private var session: OnlineSessionView?
    private var observations: [String] = []

    public init(service: OnlineSessionService, user: TogetherUser?, game: OnlineWebRouter.Game, sessionKey: Data = OnlineWire.randomBytes(32), locale: Locale = .current) {
        let account = user.map { OnlinePlay.account(for: $0, locale: locale) } ?? .signedOut
        baseAccount = account
        userId = user?.id
        let refs = References()
        let link = OnlinePeerLink(sessionKey: sessionKey, ownAddress: 0) { refs.bridge?.deliver($0) }
        let router = OnlineWebRouter(service: service, game: game) { view in refs.play?.sessionChanged(view) }
        let bridge = OnlineBridgeServer(account: account, handlers: .init(
            web: { request in await refs.router?.handle(request) ?? .notOffered },
            datagram: { refs.link?.send($0) },
            observation: { line in refs.play?.keep(line) },
            engine: { hello in if let hello { refs.router?.setEngineBuild(hello.build) } }))
        self.bridge = bridge
        self.router = router
        self.link = link
        refs.bridge = bridge
        refs.link = link
        refs.router = router
        refs.play = self
    }

    /// Starts listening for the game and for peers; the result is what the game is started with.
    public func start(peerHost: String = "0.0.0.0", peerPort: UInt16 = 0) throws -> [String: String] {
        try bridge.start()
        try link.start(host: peerHost, port: peerPort)
        return bridge.environment
    }

    public func stop() {
        bridge.stop()
        link.stop()
    }

    public var currentSession: OnlineSessionView? { lock.withLock { session } }

    /// The observation lines the game sent, newest last (at most 2000).
    public var observed: [String] { lock.withLock { observations } }

    /// Where a session member's launcher receives packets. Until AnyTogether carries endpoints,
    /// the caller tells it.
    public func setEndpoint(of userId: String, _ endpoint: OnlinePeerLink.Endpoint?) {
        guard let address = lock.withLock({ session?.addresses[userId] }) else { return }
        link.setPeer(address, at: endpoint)
    }

    func sessionChanged(_ view: OnlineSessionView?) {
        lock.withLock { session = view }
        var account = baseAccount
        let own = view.flatMap { view in userId.flatMap { view.addresses[$0] } } ?? 0
        account.address = account.signedIn ? own : 0
        link.setOwnAddress(account.address)
        bridge.setAccount(account)
    }

    private func keep(_ line: String) {
        lock.withLock {
            observations.append(line)
            if observations.count > 2000 { observations.removeFirst(observations.count - 2000) }
        }
    }

    /// The account the game sees for an AnyTogether user: a stable 64-bit number from the user's
    /// ID, the handle cut to the platform's 16 letters, and the Mac's country and language.
    public static func account(for user: TogetherUser, locale: Locale) -> OnlineWire.Account {
        let digest = SHA256.hash(data: Data(user.id.utf8))
        var number = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        if number == 0 { number = 1 }
        let onlineId = String(user.handle.prefix(16))
        let region = locale.region?.identifier.lowercased() ?? ""
        let language = locale.language.languageCode?.identifier ?? ""
        return OnlineWire.Account(signedIn: true, accountId: number, onlineId: onlineId.isEmpty ? "player" : onlineId,
                                  country: region.count == 2 ? region : "", language: language)
    }
}

private final class References: @unchecked Sendable {
    weak var bridge: OnlineBridgeServer?
    weak var link: OnlinePeerLink?
    weak var router: OnlineWebRouter?
    weak var play: OnlinePlay?
}

/// The one online session of the running game, switched on with the `OnlinePlay` default
/// (`defaults write <launcher> OnlinePlay -bool YES`). Off, nothing changes for the game.
public enum OnlinePlayHost {
    nonisolated(unsafe) private static var current: OnlinePlay?
    private static let lock = NSLock()

    public static var enabled: Bool { UserDefaults.standard.bool(forKey: "OnlinePlay") }

    /// What a game is started with for online play, or nothing when it is off or fails to start.
    public static func environment(for game: Game, client: TogetherClient) -> [String: String] {
        guard enabled else { return [:] }
        return lock.withLock {
            current?.stop()
            let play = OnlinePlay(service: client, user: client.user, game: .init(titleId: game.titleID, gameVersion: game.version.isEmpty ? "0" : game.version, engineBuild: "unknown"))
            guard let environment = try? play.start() else {
                current = nil
                return [:]
            }
            current = play
            return environment
        }
    }

    public static var session: OnlinePlay? { lock.withLock { current } }
}
