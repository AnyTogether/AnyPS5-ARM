import Darwin
import Foundation

/// The launcher's end of the engine's online bridge: a loopback TCP listener the running game
/// connects to with the per-start secret from `environment`. Both sides prove the secret with
/// HMAC; the secret itself never crosses the socket. One proven engine at a time: a game that
/// reconnects replaces its old connection.
public final class OnlineBridgeServer: @unchecked Sendable {
    public struct Handlers: Sendable {
        public var web: @Sendable (OnlineWire.WebRequest) async -> OnlineWire.WebReply
        public var datagram: @Sendable (OnlineWire.Datagram) -> Void
        public var observation: @Sendable (String) -> Void
        public var engine: @Sendable (OnlineWire.Hello?) -> Void

        public init(web: @escaping @Sendable (OnlineWire.WebRequest) async -> OnlineWire.WebReply = { _ in .notOffered },
                    datagram: @escaping @Sendable (OnlineWire.Datagram) -> Void = { _ in },
                    observation: @escaping @Sendable (String) -> Void = { _ in },
                    engine: @escaping @Sendable (OnlineWire.Hello?) -> Void = { _ in }) {
            self.web = web
            self.datagram = datagram
            self.observation = observation
            self.engine = engine
        }
    }

    public let secret: Data
    private let handlers: Handlers
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var listener: Int32 = -1
    private var listenPort: UInt16 = 0
    private var engineSocket: Int32 = -1
    private var currentAccount: OnlineWire.Account
    private var hello: OnlineWire.Hello?
    private var stopped = false
    private var acceptor: Thread?

    public init(secret: Data = OnlineWire.randomBytes(32), account: OnlineWire.Account = .signedOut, handlers: Handlers = Handlers()) {
        self.secret = secret
        self.currentAccount = account
        self.handlers = handlers
    }

    deinit { stop() }

    /// The loopback port, once started.
    public var port: UInt16 { lock.withLock { listenPort } }

    /// What the game is started with.
    public var environment: [String: String] {
        ["ANYPS5_ONLINE": "127.0.0.1:\(port)", "ANYPS5_ONLINE_SECRET": OnlineWire.hex(secret)]
    }

    /// The engine that proved the secret last, while it is connected.
    public var engine: OnlineWire.Hello? { lock.withLock { engineSocket >= 0 ? hello : nil } }

    public var account: OnlineWire.Account { lock.withLock { currentAccount } }

    public func start() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var one: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, length) } }
        guard bound == 0, listen(socket, 4) == 0,
              withUnsafeMutablePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) } }) == 0 else {
            close(socket)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }
        lock.withLock {
            listener = socket
            listenPort = UInt16(bigEndian: address.sin_port)
        }
        let thread = Thread { [weak self] in self?.acceptLoop(socket) }
        thread.name = "online bridge"
        acceptor = thread
        thread.start()
    }

    public func stop() {
        let (socket, engine) = lock.withLock { () -> (Int32, Int32) in
            stopped = true
            defer {
                listener = -1
                engineSocket = -1
            }
            return (listener, engineSocket)
        }
        if engine >= 0 { shutdown(engine, SHUT_RDWR) }
        if socket >= 0 { close(socket) }
    }

    /// Tells the game who is signed in, now and on every later connection.
    public func setAccount(_ account: OnlineWire.Account) {
        let socket = lock.withLock { () -> Int32 in
            currentAccount = account
            return engineSocket
        }
        if socket >= 0 { write(socket, OnlineWire.frame(.account, account.payload)) }
    }

    /// Hands a packet from a peer to the game; false while no game is connected.
    @discardableResult
    public func deliver(_ datagram: OnlineWire.Datagram) -> Bool {
        let socket = lock.withLock { engineSocket }
        guard socket >= 0, datagram.data.count <= OnlineWire.maxDatagram else { return false }
        return write(socket, OnlineWire.frame(.datagram, datagram.payload))
    }

    /// Hands a push event (session news) to the game; false while no game is connected or when
    /// the event is not one the engine accepts.
    @discardableResult
    public func push(_ event: OnlineWire.PushEvent) -> Bool {
        let socket = lock.withLock { engineSocket }
        guard socket >= 0, event.isValid else { return false }
        return write(socket, OnlineWire.frame(.pushEvent, event.payload))
    }

    private func acceptLoop(_ listener: Int32) {
        while !lock.withLock({ stopped }) {
            var waiting = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, 100) > 0 else { continue }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { continue }
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in
                self?.serve(client)
                close(client)
            }
            thread.name = "online bridge engine"
            thread.start()
        }
    }

    private func serve(_ socket: Int32) {
        setTimeout(socket, seconds: 5)
        guard let first = readFrame(socket), first.header.kind == OnlineWire.Kind.hello.rawValue, let hello = OnlineWire.Hello(first.payload) else { return }
        guard hello.protocolVersion == OnlineWire.protocolVersion else {
            write(socket, OnlineWire.frame(.refuse, OnlineWire.refuse(.protocolVersion, "this launcher speaks protocol \(OnlineWire.protocolVersion)")))
            return
        }
        let nonce = OnlineWire.randomBytes(16)
        let launcherProof = OnlineWire.proof(secret: secret, side: .launcher, engineNonce: hello.nonce, launcherNonce: nonce)
        guard write(socket, OnlineWire.frame(.welcome, OnlineWire.welcome(nonce: nonce, proof: launcherProof))),
              let answer = readFrame(socket), answer.header.kind == OnlineWire.Kind.proof.rawValue else { return }
        let expected = OnlineWire.proof(secret: secret, side: .engine, engineNonce: hello.nonce, launcherNonce: nonce)
        guard OnlineWire.sameProof(answer.payload.prefix(32), expected) else {
            write(socket, OnlineWire.frame(.refuse, OnlineWire.refuse(.badProof, "this game was not started by this launcher")))
            return
        }
        setTimeout(socket, seconds: 0)
        let (previous, account) = lock.withLock { () -> (Int32, OnlineWire.Account) in
            let previous = engineSocket
            engineSocket = socket
            self.hello = hello
            return (previous, currentAccount)
        }
        if previous >= 0 { shutdown(previous, SHUT_RDWR) }
        write(socket, OnlineWire.frame(.account, account.payload))
        handlers.engine(hello)
        while let frame = readFrame(socket) { dispatch(frame, socket) }
        let wasCurrent = lock.withLock { () -> Bool in
            guard engineSocket == socket else { return false }
            engineSocket = -1
            return true
        }
        if wasCurrent { handlers.engine(nil) }
    }

    private func dispatch(_ frame: (header: OnlineWire.Header, payload: Data), _ socket: Int32) {
        let header = frame.header
        if header.flags & OnlineWire.flagReply != 0 { return }
        switch OnlineWire.Kind(rawValue: header.kind) {
        case .webRequest where header.call != 0:
            guard let request = OnlineWire.WebRequest(frame.payload) else {
                write(socket, OnlineWire.frame(.webRequest, flags: OnlineWire.flagReply | OnlineWire.flagUnsupported, call: header.call, Data()))
                return
            }
            let web = handlers.web
            Task {
                let reply = await web(request)
                guard self.lock.withLock({ self.engineSocket == socket }) else { return }
                self.write(socket, OnlineWire.frame(.webRequest, flags: OnlineWire.flagReply, call: header.call, reply.payload))
            }
        case .datagram:
            if let datagram = OnlineWire.Datagram(frame.payload) { handlers.datagram(datagram) }
        case .observation:
            var reader = OnlineWire.Reader(frame.payload)
            let line = reader.str()
            if reader.ok { handlers.observation(line) }
        default:
            if header.call != 0 {
                write(socket, OnlineWire.Header(length: 0, kind: header.kind, flags: OnlineWire.flagReply | OnlineWire.flagUnsupported, call: header.call).bytes)
            }
        }
    }

    @discardableResult
    private func write(_ socket: Int32, _ data: Data) -> Bool {
        writeLock.withLock {
            data.withUnsafeBytes { buffer -> Bool in
                var offset = 0
                while offset < buffer.count {
                    let sent = Darwin.send(socket, buffer.baseAddress! + offset, buffer.count - offset, 0)
                    if sent > 0 {
                        offset += sent
                    } else if sent < 0 && errno == EINTR {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
        }
    }

    private func readFrame(_ socket: Int32) -> (header: OnlineWire.Header, payload: Data)? {
        guard let head = readExact(socket, OnlineWire.headerSize), let header = OnlineWire.Header(head) else { return nil }
        guard header.length > 0 else { return (header, Data()) }
        guard let payload = readExact(socket, Int(header.length)) else { return nil }
        return (header, payload)
    }

    private func readExact(_ socket: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var done = 0
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            while done < count {
                let got = recv(socket, buffer.baseAddress! + done, count - done, 0)
                if got > 0 {
                    done += got
                } else if got < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        return ok ? data : nil
    }

    private func setTimeout(_ socket: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}
