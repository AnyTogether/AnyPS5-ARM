import Foundation
import Network

/// A phone that is not paired yet, waiting for the user to allow it on the Mac.
public struct PairingRequest: Identifiable, Sendable {
    public let id: UUID
    public let deviceName: String
    public let code: String
}

/// The launcher's side of the phone controller: it advertises itself on the local network,
/// pairs phones over a WebSocket control channel and tells the phone where to send its pad.
/// One phone is connected at a time. Everything runs on one private queue.
public final class RemoteServer: @unchecked Sendable {
    public static let serviceType = "_anyps5-remote._tcp"

    public struct Events: Sendable {
        public var pairing: @Sendable (PairingRequest) -> Void
        public var connected: @Sendable (String) -> Void
        public var disconnected: @Sendable () -> Void
        public var latency: @Sendable (Double) -> Void

        public init(pairing: @escaping @Sendable (PairingRequest) -> Void = { _ in }, connected: @escaping @Sendable (String) -> Void = { _ in },
                    disconnected: @escaping @Sendable () -> Void = {}, latency: @escaping @Sendable (Double) -> Void = { _ in }) {
            self.pairing = pairing
            self.connected = connected
            self.disconnected = disconnected
            self.latency = latency
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
    let queue = DispatchQueue(label: "org.anyps5.remote")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    /// The welcomed phone, or the one being asked about.
    var current: Client?

    public init(name: String, devices: PairedDevices, events: Events, advertise: Bool = true, controlPort: UInt16 = 0) {
        self.name = name
        self.devices = devices
        self.events = events
        self.advertise = advertise
        self.requestedPort = controlPort
    }

    /// Starts listening and returns once the control port is open.
    public func start() throws {
        let parameters = NWParameters.tcp
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

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for client in clients.values { client.connection.cancel() }
            clients = [:]
            current = nil
            stopRelay()
        }
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
            if let current, current !== client { return reject(client, "busy") }
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
        case .pairing, .welcome, .rejected:
            break
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

    /// The UDP port the phone sends its pad to; set once the relay runs.
    var relayPort: UInt16? { nil }

    func startRelay() throws {}

    func stopRelay() {}

    func phoneEnded() {}
}

/// A value shared with a callback on another thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
