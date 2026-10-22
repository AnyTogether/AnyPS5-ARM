import Darwin
import Foundation
import Network

/// A phone that is not paired yet, waiting for the user to allow it on the Mac.
public struct PairingRequest: Identifiable, Sendable {
    public let id: UUID
    public let deviceName: String
    public let code: String

    public init(id: UUID, deviceName: String, code: String) {
        self.id = id
        self.deviceName = deviceName
        self.code = code
    }
}

/// The launcher's side of the phone controller: it advertises itself on the local network,
/// pairs phones over a WebSocket control channel and tells the phone where to send its pad.
/// One phone is connected at a time. Everything runs on one private queue.
public final class RemoteServer: @unchecked Sendable {
    public static let serviceType = "_anyps5-remote._tcp"
    /// The control port the launcher tries first; the phone's manual address field assumes it.
    public static let preferredPort: UInt16 = 47700
    /// The game bridge port the launcher tries first, so a game started before the launcher
    /// restarted still reaches it.
    public static let preferredBridgePort: UInt16 = 47701

    public struct Events: Sendable {
        public var pairing: @Sendable (PairingRequest) -> Void
        public var connected: @Sendable (String) -> Void
        public var disconnected: @Sendable () -> Void
        public var latency: @Sendable (Double) -> Void
        /// What the welcomed phone asks the launcher to do (launcher mode).
        public var request: @Sendable (RemoteMessage) -> Void

        public init(pairing: @escaping @Sendable (PairingRequest) -> Void = { _ in }, connected: @escaping @Sendable (String) -> Void = { _ in },
                    disconnected: @escaping @Sendable () -> Void = {}, latency: @escaping @Sendable (Double) -> Void = { _ in },
                    request: @escaping @Sendable (RemoteMessage) -> Void = { _ in }) {
            self.pairing = pairing
            self.connected = connected
            self.disconnected = disconnected
            self.latency = latency
            self.request = request
        }
    }

    /// The phone on the control channel, from its hello to the end of its socket.
    final class Client {
        let connection: NWConnection
        var deviceID: String?
        var name: String?
        var pending: PairingRequest?
        var session: UInt64?

        init(connection: NWConnection) { self.connection = connection }
    }

    private let name: String
    private let devices: PairedDevices
    private let events: Events
    private let advertise: Bool
    private let requestedPort: UInt16
    private let requestedBridgePort: UInt16
    let queue = DispatchQueue(label: "org.anyps5.remote")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    /// The welcomed phone, or the one being asked about.
    var current: Client?

    public init(name: String, devices: PairedDevices, events: Events, advertise: Bool = true, controlPort: UInt16 = 0, bridgePort: UInt16 = 0) {
        self.requestedBridgePort = bridgePort
        self.name = name
        self.devices = devices
        self.events = events
        self.advertise = advertise
        self.requestedPort = controlPort
    }

    /// Starts listening and returns once the control port is open.
    public func start() throws {
        // Keepalive notices a phone that vanished without closing; reuse lets a launcher that
        // just quit with a phone connected listen on the same port again.
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        let listener = try NWListener(using: parameters, on: port)
        if advertise { listener.service = NWListener.Service(name: name, type: RemoteServer.serviceType) }
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
            throw InstallError("the phone server did not start")
        }
        if let error = failure.value {
            listener.cancel()
            throw error
        }
        self.listener = listener
        try startRelay()
    }

    /// Stops and returns once the control port is free again.
    public func stop() {
        let cancelled = DispatchSemaphore(value: 0)
        let stopping: NWListener? = queue.sync { listener }
        stopping?.stateUpdateHandler = { state in if case .cancelled = state { cancelled.signal() } }
        queue.sync {
            listener?.cancel()
            listener = nil
            for client in clients.values { client.connection.cancel() }
            clients = [:]
            current = nil
            stopRelay()
        }
        if stopping != nil { _ = cancelled.wait(timeout: .now() + 2) }
    }

    public var controlPort: UInt16? { queue.sync { listener?.port?.rawValue } }

    public var connectedDevice: String? { queue.sync { current?.session != nil ? current?.name : nil } }

    /// The user's answer to a pairing request.
    public func respond(to id: UUID, allow: Bool) {
        queue.async { [self] in
            guard let client = current, let request = client.pending, request.id == id, let deviceID = client.deviceID else { return }
            client.pending = nil
            if allow {
                let device = devices.add(id: deviceID, name: request.deviceName)
                welcome(client, key: device.key)
            } else {
                reject(client, "denied")
            }
        }
    }

    // MARK: Control channel

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection)
        clients[ObjectIdentifier(client)] = client
        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled: self.ended(client)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(client)
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            guard let self, let client else { return }
            if error != nil {
                client.connection.cancel()
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .close {
                client.connection.cancel()
                return
            }
            if let data, metadata?.opcode == .text || metadata?.opcode == .binary, let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) {
                self.handle(message, from: client)
            }
            self.receive(client)
        }
    }

    private func handle(_ message: RemoteMessage, from client: Client) {
        switch message {
        case .hello(let version, let deviceID, let deviceName, let key):
            guard version == RemoteMessage.protocolVersion else { return reject(client, "protocol") }
            if let current, current !== client {
                // The same phone back on a new connection: the old one is dead, it takes over.
                guard current.deviceID == deviceID else { return reject(client, "busy") }
                self.current = nil
                current.connection.cancel()
            }
            client.deviceID = deviceID
            client.name = deviceName
            current = client
            if let key, let device = devices.device(id: deviceID, key: key) {
                welcome(client, key: device.key)
            } else {
                let request = PairingRequest(id: UUID(), deviceName: deviceName, code: String(format: "%04d", Int.random(in: 0...9999)))
                client.pending = request
                send(.pairing(code: request.code), to: client)
                events.pairing(request)
            }
        case .latency(let milliseconds):
            if client === current, client.session != nil { events.latency(milliseconds) }
        case .wantArt, .command, .select, .launch, .close, .home:
            if client === current, client.session != nil { events.request(message) }
        case .pairing, .welcome, .rejected, .library, .art:
            break
        }
    }

    /// Sends to the welcomed phone, if one is connected.
    public func publish(_ message: RemoteMessage) {
        queue.async { [self] in
            guard let client = current, client.session != nil else { return }
            send(message, to: client)
        }
    }

    private func welcome(_ client: Client, key: String) {
        var session: UInt64 = 0
        while session == 0 { session = UInt64.random(in: UInt64.min...UInt64.max) }
        client.session = session
        send(.welcome(session: session, udpPort: relayPort ?? 0, macName: name, key: key), to: client)
        if let name = client.name { events.connected(name) }
    }

    private func reject(_ client: Client, _ reason: String) {
        if current === client { current = nil }
        send(.rejected(reason: reason), to: client) { client.connection.cancel() }
    }

    private func ended(_ client: Client) {
        clients[ObjectIdentifier(client)] = nil
        guard current === client else { return }
        let welcomed = client.session != nil
        current = nil
        phoneEnded()
        if welcomed { events.disconnected() }
    }

    private func send(_ message: RemoteMessage, to client: Client, then: (() -> Void)? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        client.connection.send(content: Data(message.text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in then?() })
    }

    // MARK: Pad relay

    private var phoneSocket: Int32 = -1
    private var bridgeSocket: Int32 = -1
    private var sources: [DispatchSourceRead] = []
    private var phoneAddress: sockaddr_storage?
    private var gameAddress: sockaddr_storage?

    /// The UDP port the phone sends its pad to, on every interface.
    public var udpPort: UInt16? { queue.sync { relayPort } }

    /// The loopback UDP port the running game talks to.
    public var bridgePort: UInt16? { queue.sync { bridgeSocket >= 0 ? RemoteServer.port(of: bridgeSocket) : nil } }

    /// What a game is started with so that it reads the phone (ANYPS5_REMOTE_PAD).
    public var bridgeEnvironment: [String: String] {
        guard let bridgePort else { return [:] }
        return ["ANYPS5_REMOTE_PAD": "127.0.0.1:\(bridgePort)"]
    }

    var relayPort: UInt16? { phoneSocket >= 0 ? RemoteServer.port(of: phoneSocket) : nil }

    func startRelay() throws {
        let phone = Darwin.socket(AF_INET6, SOCK_DGRAM, 0)
        var dual: Int32 = 0
        setsockopt(phone, IPPROTO_IPV6, IPV6_V6ONLY, &dual, socklen_t(MemoryLayout<Int32>.size))
        var any = sockaddr_in6()
        any.sin6_family = sa_family_t(AF_INET6)
        any.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        any.sin6_addr = in6addr_any
        let bridge = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        var loopback = sockaddr_in()
        loopback.sin_family = sa_family_t(AF_INET)
        loopback.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        loopback.sin_addr.s_addr = inet_addr("127.0.0.1")
        loopback.sin_port = requestedBridgePort.bigEndian
        guard phone >= 0, bridge >= 0, RemoteServer.bind(phone, &any), RemoteServer.bind(bridge, &loopback) else {
            if phone >= 0 { close(phone) }
            if bridge >= 0 { close(bridge) }
            throw InstallError("the phone pad sockets could not be opened")
        }
        for socket in [phone, bridge] { _ = fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK) }
        queue.sync {
            phoneSocket = phone
            bridgeSocket = bridge
            sources = [watch(phone) { [weak self] in self?.fromPhone() }, watch(bridge) { [weak self] in self?.fromGame() }]
        }
    }

    func stopRelay() {
        for source in sources { source.cancel() }
        sources = []
        phoneSocket = -1
        bridgeSocket = -1
        phoneAddress = nil
        gameAddress = nil
    }

    func phoneEnded() {
        phoneAddress = nil
    }

    private func watch(_ socket: Int32, _ handler: @escaping () -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(socket) }
        source.resume()
        return source
    }

    /// Pad packets from the welcomed phone go to the game; anything else is dropped.
    private func fromPhone() {
        while let (data, source) = RemoteServer.receive(phoneSocket) {
            guard let session = current?.session, RemotePacket.inputSession(data) == session else { continue }
            phoneAddress = source
            if var game = gameAddress { RemoteServer.send(data, from: bridgeSocket, to: &game) }
        }
    }

    /// A hello names the game to send to; its answers go back to the phone.
    private func fromGame() {
        while let (data, source) = RemoteServer.receive(bridgeSocket) {
            if RemotePacket.isHello(data) {
                gameAddress = source
            } else if RemotePacket.isOutput(data), let game = gameAddress, RemoteServer.same(source, game), var phone = phoneAddress {
                RemoteServer.send(data, from: phoneSocket, to: &phone)
            }
        }
    }

    private static func bind<Address>(_ socket: Int32, _ address: inout Address) -> Bool {
        withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socket, $0, socklen_t(MemoryLayout<Address>.size)) == 0 } }
    }

    private static func port(of socket: Int32) -> UInt16? {
        var address = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        guard withUnsafeMutablePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) } }) == 0 else { return nil }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt16(bigEndian: $0.pointee.sin_port) }
        }
    }

    private static func receive(_ socket: Int32) -> (Data, sockaddr_storage)? {
        var buffer = [UInt8](repeating: 0, count: 512)
        var address = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let got = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(socket, &buffer, buffer.count, 0, $0, &length) } }
        return got < 0 ? nil : (Data(buffer.prefix(got)), address)
    }

    private static func send(_ data: Data, from socket: Int32, to address: inout sockaddr_storage) {
        let length = socklen_t(address.ss_len)
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(socket, bytes.baseAddress, data.count, 0, $0, length) } }
        }
    }

    private static func same(_ left: sockaddr_storage, _ right: sockaddr_storage) -> Bool {
        var left = left
        var right = right
        return left.ss_len == right.ss_len && memcmp(&left, &right, Int(left.ss_len)) == 0
    }
}

/// A value shared with a callback on another thread.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    public init(_ value: Value) { stored = value }

    public var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
