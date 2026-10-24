import Darwin
import Foundation
import Network
import os

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
/// Up to four phones are connected at a time, one per player, each with its own bridge to the
/// game; one new phone is asked about at a time. Everything runs on one private queue.
public final class RemoteServer: @unchecked Sendable {
    /// `log stream --predicate 'subsystem == "org.anyps5.launcher"'` shows what the phone and the
    /// launcher tell each other.
    static let log = Logger(subsystem: "org.anyps5.launcher", category: "phone")
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
        /// A phone that said hello and is not welcomed yet, by name; nil when it gave up or was
        /// refused before that.
        public var connecting: @Sendable (String?) -> Void
        /// The game said a phone became another player, or none (`phonePlayers`).
        public var players: @Sendable () -> Void

        public init(pairing: @escaping @Sendable (PairingRequest) -> Void = { _ in }, connected: @escaping @Sendable (String) -> Void = { _ in },
                    disconnected: @escaping @Sendable () -> Void = {}, latency: @escaping @Sendable (Double) -> Void = { _ in },
                    request: @escaping @Sendable (RemoteMessage) -> Void = { _ in }, connecting: @escaping @Sendable (String?) -> Void = { _ in },
                    players: @escaping @Sendable () -> Void = {}) {
            self.pairing = pairing
            self.connected = connected
            self.disconnected = disconnected
            self.latency = latency
            self.request = request
            self.connecting = connecting
            self.players = players
        }
    }

    /// The phone on the control channel, from its hello to the end of its socket.
    final class Client {
        let connection: NWConnection
        var deviceID: String?
        var name: String?
        var pending: PairingRequest?
        var session: UInt64?
        /// Which bridge, and so which of the game's phone channels, carries this phone's pad.
        var slot: Int?
        /// Where the phone sends its pad from.
        var address: sockaddr_storage?
        /// The phone sends its pad on this channel (on a cable, with no UDP path), and is
        /// answered on it.
        var padOnChannel = false

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
    /// The welcomed phones, by slot.
    var phones: [Client] = []
    /// The phone being asked about.
    var asking: Client?
    public static let maxPhones = 4

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
            phones = []
            asking = nil
            stopRelay()
        }
        if stopping != nil { _ = cancelled.wait(timeout: .now() + 2) }
    }

    public var controlPort: UInt16? { queue.sync { listener?.port?.rawValue } }

    /// The first welcomed phone's name.
    public var connectedDevice: String? { queue.sync { phones.first?.name } }

    /// Every welcomed phone's name, by slot.
    public var connectedDevices: [String] { queue.sync { phones.compactMap(\.name) } }

    /// Every welcomed phone's device ID, by slot.
    public var connectedDeviceIDs: [String] { queue.sync { phones.compactMap(\.deviceID) } }

    /// Which player each welcomed phone is in the game, from 1, by device ID; a phone that is
    /// no player yet is left out.
    public var phonePlayers: [String: Int] {
        queue.sync {
            var players: [String: Int] = [:]
            for client in phones {
                guard let id = client.deviceID, let slot = client.slot, let player = gamePlayers[slot] else { continue }
                players[id] = player
            }
            return players
        }
    }

    /// The user's answer to a pairing request.
    public func respond(to id: UUID, allow: Bool) {
        queue.async { [self] in
            guard let client = asking, let request = client.pending, request.id == id, let deviceID = client.deviceID else { return }
            client.pending = nil
            if allow {
                asking = nil
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
            if let data, metadata?.opcode == .binary, let session = RemotePacket.inputSession(data) {
                self.padFromChannel(data, session: session, client: client)
            } else if let data, metadata?.opcode == .text || metadata?.opcode == .binary {
                if let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) {
                    self.handle(message, from: client)
                } else {
                    RemoteServer.log.error("unreadable from phone: \(String(decoding: data.prefix(200), as: UTF8.self), privacy: .public)")
                }
            }
            self.receive(client)
        }
    }

    private func handle(_ message: RemoteMessage, from client: Client) {
        RemoteServer.log.info("from phone: \(message.kind, privacy: .public) welcomed=\(client.session != nil, privacy: .public)")
        switch message {
        case .hello(let version, let deviceID, let deviceName, let key):
            guard version == RemoteMessage.protocolVersion else { return reject(client, "protocol") }
            // The same phone back on a new connection: the old one is dead, it takes over.
            if let old = (phones + [asking].compactMap { $0 }).first(where: { $0 !== client && $0.deviceID == deviceID }) {
                phones.removeAll { $0 === old }
                if asking === old { asking = nil }
                old.connection.cancel()
            }
            client.deviceID = deviceID
            client.name = deviceName
            if let key, let device = devices.device(id: deviceID, key: key) {
                guard phones.count < RemoteServer.maxPhones else { return reject(client, "busy") }
                events.connecting(deviceName)
                welcome(client, key: device.key)
            } else {
                guard asking == nil, phones.count < RemoteServer.maxPhones else { return reject(client, "busy") }
                asking = client
                events.connecting(deviceName)
                let request = PairingRequest(id: UUID(), deviceName: deviceName, code: String(format: "%04d", Int.random(in: 0...9999)))
                client.pending = request
                send(.pairing(code: request.code), to: client)
                events.pairing(request)
            }
        case .latency(let milliseconds):
            if client === phones.first { events.latency(milliseconds) }
        case .wantArt, .command, .select, .launch, .close, .home, .saveLayout:
            if phones.contains(where: { $0 === client }) { events.request(message) }
        case .pairing, .welcome, .rejected, .library, .art, .trophy, .activity:
            break
        }
    }

    /// Sends to every welcomed phone.
    public func publish(_ message: RemoteMessage) {
        queue.async { [self] in
            for client in phones { send(message, to: client) }
        }
    }

    private func welcome(_ client: Client, key: String) {
        guard let slot = (0..<RemoteServer.maxPhones).first(where: { slot in !phones.contains { $0.slot == slot } }) else { return reject(client, "busy") }
        var session: UInt64 = 0
        while session == 0 { session = UInt64.random(in: UInt64.min...UInt64.max) }
        client.session = session
        client.slot = slot
        phones.append(client)
        phones.sort { ($0.slot ?? 0) < ($1.slot ?? 0) }
        send(.welcome(session: session, udpPort: relayPort ?? 0, macName: name, key: key), to: client)
        if let name = client.name { events.connected(name) }
    }

    private func reject(_ client: Client, _ reason: String) {
        if asking === client {
            asking = nil
            events.connecting(nil)
        }
        send(.rejected(reason: reason), to: client) { client.connection.cancel() }
    }

    private func ended(_ client: Client) {
        clients[ObjectIdentifier(client)] = nil
        if asking === client {
            asking = nil
            events.connecting(nil)
        } else if phones.contains(where: { $0 === client }) {
            phones.removeAll { $0 === client }
            if let slot = client.slot, gamePlayers.indices.contains(slot) { gamePlayers[slot] = nil }
            events.disconnected()
        }
    }

    private func send(_ message: RemoteMessage, to client: Client, then: (() -> Void)? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
        let data = Data(message.text.utf8)
        let kind = message.kind
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if let error {
                RemoteServer.log.error("to phone: \(kind, privacy: .public) \(data.count) bytes failed: \(error.localizedDescription, privacy: .public)")
            } else {
                RemoteServer.log.info("to phone: \(kind, privacy: .public) \(data.count) bytes")
            }
            then?()
        })
    }

    // MARK: Pad relay

    private var phoneSocket: Int32 = -1
    /// One loopback socket per slot; the game's nth phone channel talks to the nth.
    private var bridgeSockets: [Int32] = []
    private var sources: [DispatchSourceRead] = []
    private var gameAddresses: [sockaddr_storage?] = []
    /// The player the game last said each slot's phone is.
    private var gamePlayers: [Int?] = []

    /// The UDP port the phone sends its pad to, on every interface.
    public var udpPort: UInt16? { queue.sync { relayPort } }

    /// The loopback UDP port the running game talks to for the first phone.
    public var bridgePort: UInt16? { bridgePorts.first }

    /// The loopback UDP ports of the game's phone channels, by slot.
    public var bridgePorts: [UInt16] { queue.sync { bridgeSockets.compactMap { RemoteServer.port(of: $0) } } }

    /// What a game is started with so that it reads the phones (ANYPS5_REMOTE_PAD, then
    /// ANYPS5_REMOTE_PAD_2 to _4).
    public var bridgeEnvironment: [String: String] {
        var environment: [String: String] = [:]
        for (slot, port) in bridgePorts.enumerated() {
            environment[slot == 0 ? "ANYPS5_REMOTE_PAD" : "ANYPS5_REMOTE_PAD_\(slot + 1)"] = "127.0.0.1:\(port)"
        }
        return environment
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
        var bridges: [Int32] = []
        var opened = phone >= 0 && RemoteServer.bind(phone, &any)
        for slot in 0..<RemoteServer.maxPhones where opened {
            let bridge = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
            var loopback = sockaddr_in()
            loopback.sin_family = sa_family_t(AF_INET)
            loopback.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            loopback.sin_addr.s_addr = inet_addr("127.0.0.1")
            loopback.sin_port = (slot == 0 ? requestedBridgePort : 0).bigEndian
            if bridge >= 0 { bridges.append(bridge) }
            opened = bridge >= 0 && RemoteServer.bind(bridge, &loopback)
        }
        guard opened else {
            if phone >= 0 { close(phone) }
            for bridge in bridges { close(bridge) }
            throw InstallError("the phone pad sockets could not be opened")
        }
        for socket in [phone] + bridges { _ = fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK) }
        queue.sync {
            phoneSocket = phone
            bridgeSockets = bridges
            gameAddresses = Array(repeating: nil, count: bridges.count)
            gamePlayers = Array(repeating: nil, count: bridges.count)
            sources = [watch(phone) { [weak self] in self?.fromPhone() }]
                + bridges.indices.map { slot in watch(bridges[slot]) { [weak self] in self?.fromGame(slot) } }
        }
    }

    func stopRelay() {
        for source in sources { source.cancel() }
        sources = []
        phoneSocket = -1
        bridgeSockets = []
        gameAddresses = []
        gamePlayers = []
    }

    private func watch(_ socket: Int32, _ handler: @escaping () -> Void) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(socket) }
        source.resume()
        return source
    }

    /// Pad packets from a welcomed phone go to the game through its slot's bridge; anything else
    /// is dropped.
    private func fromPhone() {
        while let (data, source) = RemoteServer.receive(phoneSocket) {
            guard let session = RemotePacket.inputSession(data), let client = phones.first(where: { $0.session == session }), let slot = client.slot else { continue }
            client.address = source
            if var game = gameAddresses[slot] { RemoteServer.send(data, from: bridgeSockets[slot], to: &game) }
        }
    }

    /// A pad packet on a welcomed phone's own control channel goes to the game as if it had
    /// come on UDP.
    private func padFromChannel(_ data: Data, session: UInt64, client: Client) {
        guard client.session == session, phones.contains(where: { $0 === client }), let slot = client.slot, gameAddresses.indices.contains(slot) else { return }
        client.padOnChannel = true
        if var game = gameAddresses[slot] { RemoteServer.send(data, from: bridgeSockets[slot], to: &game) }
    }

    /// A hello names the game to send to on that bridge; its answers go back to the slot's phone.
    private func fromGame(_ slot: Int) {
        while let (data, source) = RemoteServer.receive(bridgeSockets[slot]) {
            if RemotePacket.isHello(data) {
                gameAddresses[slot] = source
                let player = RemotePacket.helloPlayer(data)
                if gamePlayers[slot] != player {
                    gamePlayers[slot] = player
                    events.players()
                }
            } else if RemotePacket.isOutput(data), let game = gameAddresses[slot], RemoteServer.same(source, game),
                      let client = phones.first(where: { $0.slot == slot }) {
                if client.padOnChannel {
                    let context = NWConnection.ContentContext(identifier: "pad", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
                    client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
                } else if var phone = client.address {
                    RemoteServer.send(data, from: phoneSocket, to: &phone)
                }
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

    /// Reads or changes the value in place, holding the lock.
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&stored) }
    }
}
