import Darwin
import Foundation
import Network

/// Play from a browser: a phone with no app scans the launcher's QR code and its browser
/// becomes a pad. The server listens on the Mac's local network address only, hands out the
/// page (BrowserPad/index.html), turns the QR code's one-time token into a session cookie and
/// takes the page's WebSocket. Each browser then goes through the phone server exactly as the
/// phone app does, on a loopback control channel of its own: the same hello and pairing card,
/// the same seats (players 2 to 4 after the first), the same pad packets to the game and the
/// game's vibration and light bar back. Everything runs on one private queue.
public final class BrowserPadServer: @unchecked Sendable {
    /// The port tried first, so a phone that saved the page finds it again.
    public static let preferredPort: UInt16 = 47710

    public let host: String
    private let requestedPort: UInt16
    private let page: Data
    private let controlPort: UInt16
    public let access: BrowserPadAccess
    private let devices: PairedDevices?
    private let players: @Sendable () -> [String: Int]
    private let changed: @Sendable () -> Void
    let queue = DispatchQueue(label: "org.anyps5.browserpad")
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var timer: DispatchSourceTimer?
    /// Page loads and WebSocket opens per peer address, and bad tokens per peer address.
    private let requests = RateLimiter(capacity: 30, perSecond: 2)
    private let tokenTries = RateLimiter(capacity: 5, perSecond: 0.1)

    /// `players` says which player each phone server device is in the game (RemoteServer's
    /// phonePlayers); `changed` is called whenever a browser connects, pairs or leaves.
    public init(host: String, port: UInt16 = 0, page: Data, controlPort: UInt16, access: BrowserPadAccess = BrowserPadAccess(),
                devices: PairedDevices? = nil, players: @escaping @Sendable () -> [String: Int] = { [:] }, changed: @escaping @Sendable () -> Void = {}) {
        self.host = host
        self.requestedPort = port
        self.page = page
        self.controlPort = controlPort
        self.access = access
        self.devices = devices
        self.players = players
        self.changed = changed
    }

    /// Starts listening on `host` and returns once the port is open.
    public func start() throws {
        // Browser pads a launcher that quit left among the allowed phones are of no use now.
        for device in devices?.all ?? [] where device.id.hasPrefix(BrowserPadAccess.devicePrefix) { devices?.remove(id: device.id) }
        guard let address = IPv4Address(host) else { throw InstallError("not an IPv4 address: \(host)") }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(address), port: NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        let failure = Locked<Error?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error):
                failure.value = error
                ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw InstallError("the browser pad server did not start")
        }
        if let error = failure.value {
            listener.cancel()
            throw error
        }
        queue.sync {
            self.listener = listener
            boundPort = listener.port?.rawValue
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(150), repeating: .milliseconds(150))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    /// Stops: every browser is let go, every session ends and the port is free again.
    public func stop() {
        let cancelled = DispatchSemaphore(value: 0)
        let stopping: NWListener? = queue.sync { listener }
        stopping?.stateUpdateHandler = { state in if case .cancelled = state { cancelled.signal() } }
        queue.sync {
            timer?.cancel()
            timer = nil
            listener?.cancel()
            listener = nil
            boundPort = nil
            for peer in peers.values { peer.close() }
            peers = [:]
        }
        for session in access.endAll() { devices?.remove(id: session.deviceID) }
        if stopping != nil { _ = cancelled.wait(timeout: .now() + 2) }
    }

    public var port: UInt16? { queue.sync { boundPort } }
    /// The port, read on the queue.
    private var boundPort: UInt16?

    /// The QR code's link: this server and the current one-time token.
    public var pairingURL: URL? {
        guard let port else { return nil }
        return URL(string: "http://\(host):\(port)/?t=\(access.currentToken().value)")
    }

    /// The browsers with an open page now, by name, and whether the launcher allowed each.
    public var connected: [(name: String, deviceID: String, allowed: Bool)] {
        queue.sync {
            peers.values.compactMap { peer in
                guard let link = peer.link, let session = access.session(id: link.sessionID) else { return nil }
                return (session.name, session.deviceID, link.padSession != nil)
            }
            .sorted { $0.deviceID < $1.deviceID }
        }
    }

    /// The Mac's address on the local network: Wi-Fi or Ethernet, a private IPv4 address.
    public static func lanAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard !["utun", "awdl", "llw", "bridge", "anpi", "ap"].contains(where: { name.hasPrefix($0) }) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { var inside = $0.pointee.sin_addr; _ = inet_ntop(AF_INET, &inside, &buffer, socklen_t(buffer.count)) }
            let address = String(cString: buffer)
            guard BrowserPadAccess.isLocal(address), !address.hasPrefix("127."), !address.hasPrefix("169.254.") else { continue }
            found.append((name, address))
        }
        return (found.first { $0.name == "en0" } ?? found.first { $0.name.hasPrefix("en") } ?? found.first)?.address
    }

    // MARK: Connections

    /// One TCP connection: an HTTP request, and after an upgrade the page's WebSocket.
    final class Peer {
        let connection: NWConnection
        let address: String
        var buffer = Data()
        var link: Link?
        /// Text frames from the page; the rest is dropped while it sends too fast.
        let messages = RateLimiter(capacity: 120, perSecond: 120)
        var fragments: Data?

        init(connection: NWConnection, address: String) {
            self.connection = connection
            self.address = address
        }

        func send(_ frame: WebSocketFrame, then: (() -> Void)? = nil) {
            connection.send(content: frame.encoded(), completion: .contentProcessed { _ in then?() })
        }

        func send(_ reply: BrowserPadReply) { send(.text(reply.text)) }

        func close() {
            link?.end()
            connection.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        var address = ""
        if case .hostPort(let host, _) = connection.endpoint {
            switch host {
            case .ipv4(let v4): address = "\(v4)"
            case .ipv6(let v6): address = "\(v6)"
            default: address = "\(host)"
            }
        }
        // Local network only, whatever reaches the address.
        guard BrowserPadAccess.isLocal(address.split(separator: "%").first.map(String.init) ?? address) else {
            connection.cancel()
            return
        }
        let peer = Peer(connection: connection, address: address)
        peers[ObjectIdentifier(peer)] = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else { return }
            switch state {
            case .failed, .cancelled: self.ended(peer)
            default: break
            }
        }
        connection.start(queue: queue)
        // A request that does not finish soon is let go.
        queue.asyncAfter(deadline: .now() + 10) { [weak peer] in
            if let peer, peer.link == nil { peer.connection.cancel() }
        }
        receive(peer)
    }

    private func receive(_ peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self, weak peer] data, _, complete, error in
            guard let self, let peer else { return }
            if let data { peer.buffer.append(data) }
            if peer.link == nil { self.readRequest(peer) } else { self.readFrames(peer) }
            if complete || error != nil {
                peer.connection.cancel()
                return
            }
            if self.peers[ObjectIdentifier(peer)] != nil { self.receive(peer) }
        }
    }

    private func ended(_ peer: Peer) {
        guard peers.removeValue(forKey: ObjectIdentifier(peer)) != nil else { return }
        if let link = peer.link {
            link.end()
            // A reload's new page may hold the session already.
            if !peers.values.contains(where: { $0.link?.sessionID == link.sessionID }) { access.setConnected(false, for: link.sessionID) }
            changed()
        }
    }

    // MARK: HTTP

    private func readRequest(_ peer: Peer) {
        let parsed: (HTTPRequest, Int)?
        do {
            parsed = try HTTPRequest.parse(peer.buffer)
        } catch {
            return respond(peer, 400, "Bad Request")
        }
        guard let (request, used) = parsed else { return }
        peer.buffer.removeFirst(used)
        guard requests.allow(peer.address) else { return respond(peer, 429, "Too Many Requests", headers: [("Retry-After", "5")]) }
        guard request.method == "GET" else { return respond(peer, 405, "Method Not Allowed") }
        guard let port = boundPort else { return peer.connection.cancel() }
        let websocket = request.path == "/ws"
        guard BrowserPadAccess.allowed(origin: request.header("origin"), host: request.header("host"), serverHost: host, port: port, requireOrigin: websocket) else {
            return respond(peer, 403, "Forbidden")
        }
        switch request.path {
        case "/":
            if let token = BrowserPadAccess.query("t", in: request.target) {
                // A few scans at once, then one every ten seconds: no guessing tokens.
                guard tokenTries.allow(peer.address) else { return respond(peer, 429, "Too Many Requests", headers: [("Retry-After", "10")]) }
                if let session = access.redeem(token, deviceName: BrowserPadAccess.deviceName(userAgent: request.header("user-agent"))) {
                    changed()
                    // The token leaves the address bar (and the history) at once.
                    return respond(peer, 303, "See Other", headers: [("Location", "/"), ("Set-Cookie", BrowserPadAccess.setCookie(session)), ("Cache-Control", "no-store")])
                }
            }
            respond(peer, 200, "OK", headers: pageHeaders(port: port), body: page)
        case "/ws":
            guard request.isUpgrade, let key = request.header("sec-websocket-key") else { return respond(peer, 426, "Upgrade Required") }
            guard let session = access.session(cookieHeader: request.header("cookie")) else { return respond(peer, 403, "Forbidden") }
            upgrade(peer, key: key, session: session)
        default:
            respond(peer, 404, "Not Found")
        }
    }

    private func pageHeaders(port: UInt16) -> [(String, String)] {
        [("Content-Type", "text/html; charset=utf-8"), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"),
         ("X-Frame-Options", "DENY"), ("Referrer-Policy", "no-referrer"),
         ("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src ws://\(host):\(port); base-uri 'none'; form-action 'none'; frame-ancestors 'none'")]
    }

    private func respond(_ peer: Peer, _ status: Int, _ reason: String, headers: [(String, String)] = [], body: Data? = nil) {
        let text = body ?? Data("\(status) \(reason)\n".utf8)
        let contentType = body == nil ? [("Content-Type", "text/plain; charset=utf-8")] : []
        let response = HTTPRequest.response(status: status, reason: reason, headers: contentType + headers, body: text)
        peer.connection.send(content: response, completion: .contentProcessed { _ in peer.connection.cancel() })
    }

    private func upgrade(_ peer: Peer, key: String, session: BrowserPadAccess.Session) {
        // One page per session: a reload takes over from the page it replaces.
        for other in peers.values where other !== peer && other.link?.sessionID == session.id { other.close() }
        let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(HTTPRequest.acceptKey(key))\r\n\r\n"
        peer.connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        access.setConnected(true, for: session.id)
        let link = Link(server: self, peer: peer, session: session)
        peer.link = link
        link.connect()
        changed()
        readFrames(peer)
    }

    // MARK: WebSocket

    private func readFrames(_ peer: Peer) {
        while true {
            let decoded: (WebSocketFrame, Int)?
            do {
                decoded = try WebSocketFrame.decode(peer.buffer)
            } catch {
                peer.send(.close(1002)) { peer.connection.cancel() }
                peer.buffer = Data()
                return
            }
            guard let (frame, used) = decoded else { return }
            peer.buffer.removeFirst(used)
            switch frame.opcode {
            case .ping:
                peer.send(WebSocketFrame(opcode: .pong, payload: frame.payload))
            case .pong:
                break
            case .close:
                peer.send(.close(1000)) { peer.connection.cancel() }
                return
            case .text, .binary, .continuation:
                var payload = frame.payload
                if frame.opcode == .continuation {
                    guard var fragments = peer.fragments else { continue }
                    fragments.append(payload)
                    guard fragments.count <= BrowserPadMessage.maxLength else {
                        peer.fragments = nil
                        continue
                    }
                    peer.fragments = frame.fin ? nil : fragments
                    payload = fragments
                } else if !frame.fin {
                    peer.fragments = payload
                }
                guard frame.fin, frame.opcode != .binary else { continue }
                guard peer.messages.allow("page"), let message = BrowserPadMessage.parse(String(decoding: payload, as: UTF8.self)) else { continue }
                peer.link?.heard(message)
            }
        }
    }

    // MARK: The phone server

    /// A browser's place on the phone server: a loopback control channel that says hello as the
    /// phone app does, and the pad it relays.
    final class Link {
        weak var server: BrowserPadServer?
        weak var peer: Peer?
        let sessionID: String
        let deviceID: String
        let name: String
        private var remote: NWConnection?
        /// The pad packets' session, once the phone server welcomed this browser.
        private(set) var padSession: UInt64?
        private var sequence: UInt32 = 0
        private var state: SharePadState?
        private var heardAt = Date.distantPast
        private var sentAt = Date.distantPast
        private var neutralSent = true
        private var lastOutput: BrowserPadReply?
        private var player: Int?
        private var playerCheckedAt = Date.distantPast
        private var ended = false
        private var retry: DispatchWorkItem?

        init(server: BrowserPadServer, peer: Peer, session: BrowserPadAccess.Session) {
            self.server = server
            self.peer = peer
            sessionID = session.id
            deviceID = session.deviceID
            name = session.name
        }

        func connect() {
            guard let server, !ended else { return }
            peer?.send(.wait)
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
            let connection = NWConnection(to: .url(URL(string: "ws://127.0.0.1:\(server.controlPort)/")!), using: parameters)
            remote = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, connection === self.remote else { return }
                switch state {
                case .ready:
                    let key = self.server?.access.session(id: self.sessionID)?.key
                    self.tell(.hello(protocol: RemoteMessage.protocolVersion, deviceID: self.deviceID, deviceName: self.name, key: key))
                case .failed, .cancelled:
                    self.remoteEnded()
                case .waiting:
                    connection.cancel()
                default: break
                }
            }
            connection.start(queue: server.queue)
            receive(connection)
        }

        private func receive(_ connection: NWConnection) {
            connection.receiveMessage { [weak self, weak connection] data, context, _, error in
                guard let self, let connection, connection === self.remote else { return }
                if error != nil { return connection.cancel() }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if let data {
                    if metadata?.opcode == .binary {
                        self.output(data)
                    } else if let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) {
                        self.fromPhoneServer(message)
                    }
                }
                self.receive(connection)
            }
        }

        private func fromPhoneServer(_ message: RemoteMessage) {
            switch message {
            case .pairing(let code):
                peer?.send(.pairing(code: code))
                server?.changed()
            case .welcome(let session, _, let host, let key, _):
                padSession = session
                server?.access.setKey(key, for: sessionID)
                peer?.send(.welcome(host: host))
                player = nil
                playerCheckedAt = .distantPast
                server?.changed()
            case .rejected(let reason):
                padSession = nil
                // The phone server closes the channel after this; that end is no failure.
                remote = nil
                if reason == "busy" {
                    // Every seat taken, or another phone being asked about: try again shortly.
                    peer?.send(.busy)
                    let retry = DispatchWorkItem { [weak self] in self?.reconnect() }
                    self.retry = retry
                    server?.queue.asyncAfter(deadline: .now() + 3, execute: retry)
                } else {
                    peer?.send(.rejected(reason: reason))
                    ended = true
                    if reason == "denied", let server {
                        // Not allowed: this session is over, the QR code has to be scanned again.
                        server.access.end(sessionID)
                        server.devices?.remove(id: deviceID)
                    }
                    let peer = self.peer
                    server?.queue.asyncAfter(deadline: .now() + 0.3) { peer?.send(.close(4001)) { peer?.connection.cancel() } }
                }
            case .look(let deep, let middle, let accent):
                peer?.send(.look(deep: deep, middle: middle, accent: accent))
            default:
                break
            }
        }

        private func reconnect() {
            guard !ended else { return }
            let old = remote
            remote = nil
            old?.cancel()
            connect()
        }

        private func remoteEnded() {
            guard !ended else { return }
            remote = nil
            let wasWelcomed = padSession != nil
            padSession = nil
            // The phone server went away (the launcher restarting it): try again.
            if wasWelcomed { peer?.send(.wait) }
            let retry = DispatchWorkItem { [weak self] in self?.connect() }
            self.retry = retry
            server?.queue.asyncAfter(deadline: .now() + 2, execute: retry)
        }

        private func output(_ packet: Data) {
            guard let reply = BrowserPadReply.output(packet), reply != lastOutput else { return }
            lastOutput = reply
            peer?.send(reply)
        }

        private func tell(_ message: RemoteMessage) {
            let context = NWConnection.ContentContext(identifier: "message", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
            remote?.send(content: Data(message.text.utf8), contentContext: context, isComplete: true, completion: .idempotent)
        }

        private func sendPad(_ pad: SharePadState) {
            guard let padSession else { return }
            sequence &+= 1
            let now = Date()
            let packet = pad.packet(sequence: sequence, sentMicros: UInt64(now.timeIntervalSince1970 * 1_000_000), session: padSession)
            let context = NWConnection.ContentContext(identifier: "pad", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
            remote?.send(content: packet, contentContext: context, isComplete: true, completion: .idempotent)
            sentAt = now
            neutralSent = pad == SharePadState()
        }

        /// What the page said.
        func heard(_ message: BrowserPadMessage) {
            heardAt = Date()
            switch message {
            case .pad(let pad):
                state = pad
                sendPad(pad)
            case .button(let name):
                guard padSession != nil else { return }
                tell(name == "ps" ? .home : .command(name: "capture"))
            case .ping(let at):
                peer?.send(.pong(at))
            case .latency(let milliseconds):
                if padSession != nil { tell(.latency(milliseconds: milliseconds)) }
            }
        }

        /// Every 150 ms: the pad again while the page is there (the engine lets a pad go after
        /// 500 ms of silence), released once the page has gone quiet; the player now and then.
        func tick(now: Date) {
            guard padSession != nil else { return }
            if let state, now.timeIntervalSince(heardAt) < 0.6 {
                if now.timeIntervalSince(sentAt) >= 0.14 { sendPad(state) }
            } else if !neutralSent {
                state = nil
                sendPad(SharePadState())
            }
            if now.timeIntervalSince(playerCheckedAt) >= 0.5, let server {
                playerCheckedAt = now
                let number = server.players()[deviceID] ?? 0
                if number != player {
                    player = number
                    peer?.send(.player(number))
                }
            }
        }

        func end() {
            guard !ended else { return }
            ended = true
            retry?.cancel()
            if padSession != nil { sendPad(SharePadState()) }
            let remote = self.remote
            self.remote = nil
            // The neutral pad goes out before the channel closes.
            server?.queue.asyncAfter(deadline: .now() + 0.05) { remote?.cancel() }
        }
    }

    private var ticks = 0

    private func tick() {
        let now = Date()
        for peer in peers.values { peer.link?.tick(now: now) }
        ticks += 1
        if ticks % 200 == 0 {
            for session in access.expireIdle() { devices?.remove(id: session.deviceID) }
        }
    }
}
