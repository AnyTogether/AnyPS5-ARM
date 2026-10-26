import Foundation
import Security

/// Who may use the browser pad: the QR code's one-time token, the session cookie a redeemed
/// token turns into, the origin and host a request must name, and which peers count as the
/// local network. No sockets here, so all of it is tested with a clock of its own.
public final class BrowserPadAccess: @unchecked Sendable {
    /// The QR code's link stays good this long, and for one phone only.
    public static let tokenLifetime: TimeInterval = 120
    /// A browser session ends this long after it was last connected.
    public static let sessionIdle: TimeInterval = 30 * 60
    /// At most this many browsers hold a session at a time; the oldest idle one gives way.
    public static let maxSessions = 8
    public static let cookieName = "anyps5_pad"
    /// Device IDs of browser pads in the paired devices start with this.
    public static let devicePrefix = "browser-"

    public struct Token: Equatable, Sendable {
        public let value: String
        public let expires: Date
    }

    /// A browser that redeemed a token: its cookie, the device ID and name it pairs with, and the
    /// key the launcher gave it once allowed.
    public struct Session: Equatable, Sendable {
        public let id: String
        public let deviceID: String
        public let name: String
        public var key: String?
        public var lastSeen: Date
        /// Connected now (its socket is open), so it does not expire.
        public var connected: Bool
    }

    private let lock = NSLock()
    private let clock: @Sendable () -> Date
    private var token: Token?
    private var sessions: [String: Session] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    // MARK: Token

    /// The QR code's token: the current one while it is good, else a new one.
    public func currentToken() -> Token {
        lock.withLock {
            if let token, token.expires > clock() { return token }
            let fresh = Token(value: Self.random(bytes: 18), expires: clock().addingTimeInterval(Self.tokenLifetime))
            token = fresh
            return fresh
        }
    }

    /// A new token now, the old one no longer good.
    @discardableResult
    public func renewToken() -> Token {
        lock.withLock { token = nil }
        return currentToken()
    }

    /// Trades a good token for a new session, once: the token is spent whatever happens next.
    public func redeem(_ value: String, deviceName: String) -> Session? {
        lock.withLock {
            guard let token, token.expires > clock(), Self.same(token.value, value) else { return nil }
            self.token = nil
            expire()
            if sessions.count >= Self.maxSessions,
               let oldest = sessions.values.filter({ !$0.connected }).min(by: { $0.lastSeen < $1.lastSeen }) {
                sessions[oldest.id] = nil
            }
            guard sessions.count < Self.maxSessions else { return nil }
            let session = Session(id: Self.random(bytes: 24), deviceID: Self.devicePrefix + Self.random(bytes: 8, hex: true),
                                  name: deviceName, key: nil, lastSeen: clock(), connected: false)
            sessions[session.id] = session
            return session
        }
    }

    // MARK: Sessions

    /// The session a request's Cookie header carries, nil when it has none or it ended.
    public func session(cookieHeader: String?) -> Session? {
        guard let id = Self.cookie(Self.cookieName, in: cookieHeader) else { return nil }
        return lock.withLock {
            expire()
            return sessions.first { Self.same($0.key, id) }?.value
        }
    }

    public func session(id: String) -> Session? { lock.withLock { sessions[id] } }

    public var all: [Session] { lock.withLock { Array(sessions.values) } }

    public func setKey(_ key: String, for id: String) { lock.withLock { sessions[id]?.key = key } }

    public func setConnected(_ connected: Bool, for id: String) {
        lock.withLock {
            sessions[id]?.connected = connected
            sessions[id]?.lastSeen = clock()
        }
    }

    /// Ends a session (the launcher said no, or the user removed it); returns it.
    @discardableResult
    public func end(_ id: String) -> Session? { lock.withLock { sessions.removeValue(forKey: id) } }

    /// Ends every session and the token; returns the sessions that were.
    @discardableResult
    public func endAll() -> [Session] {
        lock.withLock {
            let ended = Array(sessions.values)
            sessions = [:]
            token = nil
            return ended
        }
    }

    /// Sessions idle for longer than `sessionIdle` that just ended.
    @discardableResult
    public func expireIdle() -> [Session] { lock.withLock { expire() } }

    @discardableResult
    private func expire() -> [Session] {
        let now = clock()
        let ended = sessions.values.filter { !$0.connected && now.timeIntervalSince($0.lastSeen) > Self.sessionIdle }
        for session in ended { sessions[session.id] = nil }
        return ended
    }

    /// The Set-Cookie header value for a session: HttpOnly, SameSite=Strict, this site only.
    public static func setCookie(_ session: Session) -> String {
        "\(cookieName)=\(session.id); Path=/; HttpOnly; SameSite=Strict; Max-Age=\(Int(sessionIdle) * 24)"
    }

    // MARK: Requests

    /// Whether a request names this server: Host must be the address and port it listens on
    /// (no other name, so a rebound DNS name gets nowhere), and Origin, when there is one (a
    /// WebSocket always has one: `requireOrigin`), must be this same site over http.
    public static func allowed(origin: String?, host: String?, serverHost: String, port: UInt16, requireOrigin: Bool) -> Bool {
        let site = "\(serverHost):\(port)".lowercased()
        guard let host, host.trimmingCharacters(in: .whitespaces).lowercased() == site else { return false }
        guard let origin else { return !requireOrigin }
        return origin.trimmingCharacters(in: .whitespaces).lowercased() == "http://" + site
    }

    /// Whether a peer's address is on the local network: private IPv4 (10/8, 172.16/12,
    /// 192.168/16), link-local (169.254/16), loopback, or the IPv6 equivalents.
    public static func isLocal(_ address: String) -> Bool {
        var text = address
        if text.hasPrefix("::ffff:") { text.removeFirst(7) }
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            let bytes = withUnsafeBytes(of: v4.s_addr) { Array($0) }
            switch (bytes[0], bytes[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        var v6 = in6_addr()
        guard inet_pton(AF_INET6, text.split(separator: "%").first.map(String.init) ?? text, &v6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: v6) { Array($0) }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
        // fe80::/10 link-local, fc00::/7 unique local.
        return (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) || bytes[0] & 0xFE == 0xFC
    }

    /// A short name for the browser's device from its User-Agent, as the pairing card shows it.
    public static func deviceName(userAgent: String?) -> String {
        let agent = userAgent ?? ""
        let device: String
        if agent.contains("iPad") {
            device = "iPad"
        } else if agent.contains("iPhone") || agent.contains("iPod") {
            device = "iPhone"
        } else if agent.contains("Android") {
            device = "Android"
        } else if agent.contains("Macintosh") && agent.contains("Mobile") {
            device = "iPad"
        } else {
            device = "Phone"
        }
        return "\(device) · Web"
    }

    /// A cookie's value in a Cookie header.
    public static func cookie(_ name: String, in header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == name {
                let value = pair[1].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// A query parameter of a request target such as `/?t=abc`.
    public static func query(_ name: String, in target: String) -> String? {
        URLComponents(string: target)?.queryItems?.first { $0.name == name }?.value
    }

    /// Compares secrets in time that does not depend on where they differ.
    static func same(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    static func random(bytes count: Int, hex: Bool = false) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        }
        if hex { return bytes.map { String(format: "%02x", $0) }.joined() }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// A token bucket per key (a peer's address): `capacity` at once, refilled at `perSecond`.
public final class RateLimiter: @unchecked Sendable {
    private let capacity: Double
    private let perSecond: Double
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var buckets: [String: (tokens: Double, at: Date)] = [:]

    public init(capacity: Double, perSecond: Double, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = capacity
        self.perSecond = perSecond
        self.clock = clock
    }

    /// Takes `cost` from the key's bucket; false (and nothing taken) when it has too little.
    public func allow(_ key: String, cost: Double = 1) -> Bool {
        lock.withLock {
            let now = clock()
            var bucket = buckets[key] ?? (capacity, now)
            bucket.tokens = min(capacity, bucket.tokens + now.timeIntervalSince(bucket.at) * perSecond)
            bucket.at = now
            let allowed = bucket.tokens >= cost
            if allowed { bucket.tokens -= cost }
            buckets[key] = bucket
            if buckets.count > 256 { buckets = buckets.filter { now.timeIntervalSince($0.value.at) < 60 } }
            return allowed
        }
    }
}
