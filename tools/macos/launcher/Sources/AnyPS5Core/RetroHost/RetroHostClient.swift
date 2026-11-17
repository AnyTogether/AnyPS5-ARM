import Darwin
import Foundation

/// How a connection to the emulator host ended (anyps5-retro-host docs/protocol.md "Fixtures",
/// `outcome`).
public enum RetroHostEnd: String, Sendable {
    /// The launcher shut the host down and it exited with code 0.
    case clean
    /// The host broke a rule; the launcher killed it.
    case protocolError
    /// The host speaks no version or pixel format this launcher offered: the emulator needs updating.
    case unsupported
    /// The host exited unasked or missed a time limit.
    case hostFailure
}

/// The host is gone and no game was loaded, so there is nothing to report for a call; also what
/// `start` gives once the connection has ended, since the next game needs a new host.
public struct RetroHostGone: Error, Equatable {
    public let end: RetroHostEnd
}

/// A call the client refuses before anything is sent.
public enum RetroHostClientError: Error, Equatable {
    /// No call, input or ping may be sent before `welcome` (protocol.md "welcome").
    case notWelcomed
    /// The host did not list the `ps1` capability, which every method but `volume` needs.
    case noPs1Capability
    /// This host has used every call id; start a new one for the next game.
    case idsUsedUp
    /// `stop` goes through `stopGame()`, which enforces its time limit.
    case useStopGame
    /// A controller value is outside what protocol.md "input" allows.
    case outOfRange(String)
}

/// A `frame` message, after the client pinned and checked the newest frame. `frame` is nil when
/// the ring had no frame to pin; `drawn` says whether the frame belongs to the current game, which
/// is the only kind the renderer may show. It may be read only during the `onFrame` call.
public struct RetroFrameEvent: @unchecked Sendable {
    public let frame: RetroPinnedFrame?
    public let drawn: Bool
}

/// The core's vibration for one controller port.
public struct RetroRumble: Equatable, Sendable {
    public let port: Int
    public let strong: Int
    public let weak: Int
}

/// A value that comes once, and everyone waiting for it. Used only on the client's queue.
private final class Latch<Value> {
    private(set) var value: Value?
    private var waiters: [(Value) -> Void] = []

    func complete(_ value: Value) {
        guard self.value == nil else { return }
        self.value = value
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter(value) }
    }

    func wait(_ body: @escaping (Value) -> Void) {
        if let value { body(value) } else { waiters.append(body) }
    }
}

/// The launcher's side of one emulator host process, as on Windows and Linux (AnyPS5 Desktop's
/// lib/core/retro_host/retro_host_client.dart), from protocol.md alone: starting it with its
/// control stream, `hello` and `welcome` (the `pid` checked against the spawned process), `volume`
/// as the first call, calls and their replies in order, pings, every time limit, the frame ring, and
/// what to report when the host fails.
///
/// All of its state lives on one serial queue of its own, and the stream is read and written only
/// by the connection's threads, so nothing here waits on the host on the caller's thread, the main
/// thread included (protocol.md "Timeouts"). `onFrame` is called on that queue, because a frame that
/// is not drawn may be read only until the next message; `onRumble` is called on another queue, so
/// it may call anything on the client, `close()` included. Call `close()` when done with a client.
public final class RetroHostClient: @unchecked Sendable {
    public static let welcomeLimit = 10.0
    public static let replyLimit = 5.0
    public static let pingEvery = 2.0
    public static let writeLimit = 5.0
    public static let stopLimit = 10.0
    public static let shutdownLimit = 15.0
    static let tick = 0.1
    static let stopPoll: UInt64 = 250_000_000

    private struct Pending {
        let id: Int
        let method: String
        let args: RetroJSON
        let deadline: UInt64
        let done: (Result<RetroJSON, Error>) -> Void
    }

    private typealias Expected = (live: Bool, paused: Bool, ports: Int)

    private let queue = DispatchQueue(label: "org.anyps5.retro-host.client")
    private let rumbleQueue = DispatchQueue(label: "org.anyps5.retro-host.rumble")
    private static let queueKey = DispatchSpecificKey<ObjectIdentifier>()

    private let volume: Double
    private let muted: Bool
    private let offeredFormats: [RetroPixelFormat]
    private let frameHandler: ((RetroFrameEvent) -> Void)?
    private let rumbleHandler: ((RetroRumble) -> Void)?

    private var connection: RetroHostConnection?
    private var processID: pid_t = 0
    private var timer: DispatchSourceTimer?
    private let readyLatch = Latch<Result<Void, Error>>()
    private let endedLatch = Latch<RetroHostEnd>()
    private let exitLatch = Latch<RetroHostExit>()
    private var unsupportedKill: DispatchWorkItem?
    private var calls: [Pending] = []
    private var pings: [(id: Int, deadline: UInt64)] = []

    private var welcomeDeadline: UInt64 = 0
    private var nextPing: UInt64?
    private var stopDeadline: UInt64?
    private var stopID = 0
    private var shutdownDeadline: UInt64?
    private var nextCallID = 1
    private var nextPingID = 1
    private var greeted = false
    private var unsupportedSeen = false
    private var shutdownSent = false
    private var closing = false
    private var agreedFormat: RetroPixelFormat?
    private var hostCapabilities: [String] = []
    private var hostRelease = ""
    private var endValue: RetroHostEnd?
    private var reason: String?

    private var gameLoaded = false
    private var lastStatusEnded = false
    private var paused = false
    private var hasInputFocus = true
    private var ports = 1
    private var epoch: Int?
    private var failedStatus: RetroStatus?

    private var ring: RetroFrameRing?
    private var previousRing: RetroFrameRing?
    private var shownFrame: RetroPinnedFrame?
    private var shownRing: RetroFrameRing?
    private var releasing = false
    private var released = false
    private var releaseWaiters: [() -> Void] = []

    private init(volume: Double, muted: Bool, pixelFormats: [RetroPixelFormat],
                 onFrame: ((RetroFrameEvent) -> Void)?, onRumble: ((RetroRumble) -> Void)?) {
        self.volume = volume
        self.muted = muted
        offeredFormats = pixelFormats
        frameHandler = onFrame
        rumbleHandler = onRumble
        queue.setSpecific(key: Self.queueKey, value: ObjectIdentifier(self))
    }

    /// Starts the host: `command` is the executable's absolute path and any arguments before the
    /// protocol's own; `environment` adds to the launcher's environment for the host. `volume` and
    /// `muted` are sent as the first call after `welcome`. The process is started off the caller's
    /// thread; the client is returned once it exists, with `hello` on its way.
    public static func start(command: [String], environment: [String: String] = [:], volume: Double = 1,
                             muted: Bool = false, pixelFormats: [RetroPixelFormat] = [.rgba8, .bgra8],
                             onFrame: ((RetroFrameEvent) -> Void)? = nil,
                             onRumble: ((RetroRumble) -> Void)? = nil) async throws -> RetroHostClient {
        let client = RetroHostClient(volume: volume, muted: muted, pixelFormats: pixelFormats,
                                     onFrame: onFrame, onRumble: onRumble)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.queue.async {
                do {
                    try client.open(command: command, environment: environment)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return client
    }

    private func open(command: [String], environment: [String: String]) throws {
        var merged = ProcessInfo.processInfo.environment
        for (name, value) in environment { merged[name] = value }
        let made = try RetroHostConnection(command: command, environment: merged) { [weak self] event in
            if let self {
                self.queue.async { self.handle(event) }
            } else if case .message(_, let descriptor) = event, descriptor >= 0 {
                Darwin.close(descriptor)
            }
        }
        connection = made
        processID = made.pid
        welcomeDeadline = now + RetroClock.seconds(Self.welcomeLimit)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + Self.tick, repeating: Self.tick)
        source.setEventHandler { [weak self] in self?.checkTime() }
        source.resume()
        timer = source
        write(.object([
            "type": .string("hello"), "minVersion": .int(RetroProtocol.version), "maxVersion": .int(RetroProtocol.version),
            "pixelFormats": .array(offeredFormats.map { .string($0.rawValue) }),
        ]))
    }

    private var now: UInt64 { RetroClock.now() }

    private func onQueue<T>(_ body: () -> T) -> T {
        DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) ? body() : queue.sync(execute: body)
    }

    private func perform<T>(_ body: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { body { continuation.resume(with: $0) } }
        }
    }

    // MARK: What the UI reads

    /// The host's process id, from `posix_spawn`: the one for audio capture, focus and killing.
    public var pid: pid_t { onQueue { processID } }
    public var hostVersion: String { onQueue { hostRelease } }
    public var capabilities: [String] { onQueue { hostCapabilities } }
    public var pixelFormat: RetroPixelFormat? { onQueue { agreedFormat } }
    /// The reason the client gave up on the host, for logs.
    public var failureReason: String? { onQueue { reason } }
    /// The host's exit, once it has exited.
    public var exit: RetroHostExit? { onQueue { exitLatch.value } }
    /// How the connection ended, once it has.
    public var end: RetroHostEnd? { onQueue { endedLatch.value } }
    /// The newest frame of the current game, pinned; nil before one came. Read it on the client's
    /// queue (in `onFrame`) to be sure it is not unmapped while it is read.
    public var frame: RetroPinnedFrame? { onQueue { shownFrame } }

    /// Returns once `welcome` came and the first `volume` call was answered; throws `RetroHostGone`
    /// when the connection ended first.
    public func ready() async throws {
        try await perform { (done: @escaping (Result<Void, Error>) -> Void) in self.readyLatch.wait { done($0) } }
    }

    /// How the connection ended.
    public func ended() async -> RetroHostEnd {
        await withCheckedContinuation { continuation in
            queue.async { self.endedLatch.wait { continuation.resume(returning: $0) } }
        }
    }

    /// The host's exit, when its process has ended.
    public func exited() async -> RetroHostExit {
        await withCheckedContinuation { continuation in
            queue.async { self.exitLatch.wait { continuation.resume(returning: $0) } }
        }
    }

    // MARK: Calls

    /// Sends a call and gives its result; an `error` reply throws `RetroCallError`. After a host
    /// failure with a game loaded this gives what protocol.md "Host failure" lists, until `release`.
    /// `stop` goes through `stopGame()`, which enforces its time limit.
    public func call(_ method: String, _ args: RetroJSON = .null) async throws -> RetroJSON {
        if method == "stop" { throw RetroHostClientError.useStopGame }
        return try await perform { (done: @escaping (Result<RetroJSON, Error>) -> Void) in self.send(method, args, done) }
    }

    /// `call(_:_:)` for a caller whose calls must go out in the order it makes them: each is queued
    /// at once, before this returns, and `done` is called on the client's queue.
    public func call(_ method: String, _ args: RetroJSON = .null, done: @escaping (Result<RetroJSON, Error>) -> Void) {
        if method == "stop" { return done(.failure(RetroHostClientError.useStopGame)) }
        queue.async { self.send(method, args, done) }
    }

    /// `start`: loads a game and gives its epoch. Once the connection has ended it throws
    /// `RetroHostGone`, also while a failed game is still reported: the next game needs a new host.
    public func startGame(_ args: RetroJSON) async throws -> Int {
        let result = try await call("start", args)
        guard let epoch = result.objectValue?["epoch"]?.intValue else { throw RetroHostGone(end: end ?? .hostFailure) }
        return epoch
    }

    /// `status`: nil with no game loaded, and the short report of protocol.md "Host failure" after one.
    public func status() async throws -> RetroStatus? {
        let result = try await call("status")
        if result.isNull { return nil }
        if RetroStatus.isFailureReport(result), let map = result.objectValue {
            return .failed(error: map["error"]?.stringValue ?? "", errorCode: map["errorCode"]?.stringValue ?? "")
        }
        return try RetroStatus.parse(result)
    }

    /// `stop`, then `status` until the game has ended, which it gives. The host is killed if the game
    /// has not ended 10 seconds after `stop` (protocol.md "Timeouts"), and the status then is the
    /// failure report. Nil when no game was loaded.
    public func stopGame() async throws -> RetroStatus? {
        _ = try await perform { (done: @escaping (Result<RetroJSON, Error>) -> Void) in
            if self.endedLatch.value == nil {
                guard self.greeted else { return done(.failure(RetroHostClientError.notWelcomed)) }
                if self.stopDeadline == nil {
                    self.stopDeadline = self.now + RetroClock.seconds(Self.stopLimit)
                    self.stopID = self.nextCallID
                }
            }
            self.send("stop", .null, done)
        }
        while true {
            let current = try await status()
            if current == nil || current?.ended == true {
                queue.async { self.stopDeadline = nil }
                return current
            }
            try await Task.sleep(nanoseconds: Self.stopPoll)
        }
    }

    /// The controller state of one port (protocol.md "input").
    public func input(port: Int, buttons: Int, leftX: Int = 0, leftY: Int = 0, rightX: Int = 0, rightY: Int = 0) throws {
        guard (0...1).contains(port) else { throw RetroHostClientError.outOfRange("port") }
        guard (0...0xFFFF).contains(buttons) else { throw RetroHostClientError.outOfRange("buttons") }
        for stick in [leftX, leftY, rightX, rightY] where !(-32768...32767).contains(stick) {
            throw RetroHostClientError.outOfRange("stick")
        }
        queue.async { self.sendInput(port, buttons, leftX, leftY, rightX, rightY) }
    }

    /// Whether the launcher's window has input focus; losing it zeroes the controllers' input and
    /// their motors (protocol.md "input" and "rumble"). Once the connection has ended a change is
    /// ignored.
    public func setInputFocus(_ focused: Bool) {
        queue.async {
            guard self.endedLatch.value == nil, self.hasInputFocus != focused else { return }
            self.hasInputFocus = focused
            if !focused {
                self.zeroInput()
                self.zeroRumble()
            }
        }
    }

    /// Asks the host to stop its game and exit; it is killed if it has not exited 15 seconds later.
    /// Before `welcome` nothing may be sent, so the host is killed instead.
    public func shutdown() {
        queue.async {
            guard !self.shutdownSent, self.endedLatch.value == nil, self.connection != nil, !self.unsupportedSeen else { return }
            guard self.greeted else {
                self.finish(.hostFailure, kill: true, reason: "Shut down before welcome.")
                return
            }
            self.shutdownSent = true
            self.shutdownDeadline = self.now + RetroClock.seconds(Self.shutdownLimit)
            self.write(.object(["type": .string("shutdown")]))
        }
    }

    /// Kills the host if it still runs, and frees everything the connection holds. The waiting is
    /// done off the client's queue and off the caller's thread.
    public func close() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true)
                self.release { continuation.resume() }
            }
        }
    }

    private func send(_ method: String, _ args: RetroJSON, _ done: @escaping (Result<RetroJSON, Error>) -> Void) {
        if endedLatch.value != nil { return done(afterFailure(method)) }
        guard greeted else { return done(.failure(RetroHostClientError.notWelcomed)) }
        if method != "volume", !hostCapabilities.contains(RetroProtocol.ps1Capability) {
            return done(.failure(RetroHostClientError.noPs1Capability))
        }
        guard nextCallID <= RetroProtocol.maxID else { return done(.failure(RetroHostClientError.idsUsedUp)) }
        let body: [UInt8]
        do {
            body = try Self.encode(.object([
                "type": .string("call"), "id": .int(nextCallID), "method": .string(method), "args": args,
            ]))
        } catch {
            return done(.failure(RetroCallError(code: RetroCallError.argument, message: "The call cannot be sent: \(error)")))
        }
        let pending = Pending(id: nextCallID, method: method, args: args,
                              deadline: now + RetroClock.seconds(Self.replyLimit), done: done)
        nextCallID += 1
        let before = expectedRumble()
        calls.append(pending)
        if method == "start" || method == "release" {
            zeroRumble()
        } else {
            zeroIfStricter(before)
        }
        write(body: body)
    }

    private func sendInput(_ port: Int, _ buttons: Int, _ leftX: Int, _ leftY: Int, _ rightX: Int, _ rightY: Int) {
        guard greeted, endedLatch.value == nil else { return }
        write(.object([
            "type": .string("input"), "port": .int(port), "buttons": .int(buttons), "leftX": .int(leftX),
            "leftY": .int(leftY), "rightX": .int(rightX), "rightY": .int(rightY),
        ]))
    }

    private func zeroInput() {
        for port in 0...1 { sendInput(port, 0, 0, 0, 0, 0) }
    }

    /// What a call gives once the connection has ended: protocol.md "Host failure" for a game that
    /// was loaded, and `RetroHostGone` for `start`, which that section does not list, and for any
    /// call with no game loaded.
    private func afterFailure(_ method: String) -> Result<RetroJSON, Error> {
        let gone = RetroHostGone(end: endValue ?? .hostFailure)
        guard let failed = failedStatus else { return .failure(gone) }
        switch method {
        case "status": return .success(failed.failureJSON)
        case "release":
            failedStatus = nil
            gameLoaded = false
            return .success(.null)
        case "connectedPorts", "changeDisc", "option": return .success(.bool(false))
        case "pause", "stop", "volume": return .success(.null)
        default: return .failure(gone)
        }
    }

    // MARK: Events

    private func handle(_ event: RetroHostConnectionEvent) {
        switch event {
        case .message(let value, let descriptor):
            if closing || endedLatch.value != nil || connection == nil {
                if descriptor >= 0 { Darwin.close(descriptor) }
                return
            }
            do {
                try onMessage(value, descriptor)
            } catch let error as RetroProtocolError {
                protocolError(error.message)
            } catch {
                finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true, reason: "\(error)")
            }
        case .protocolError(let problem):
            if endedLatch.value == nil { protocolError(problem) }
        case .endOfStream:
            if endedLatch.value == nil, !unsupportedSeen, !shutdownSent {
                finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true, reason: "The control stream ended.")
            }
        case .writeFailed:
            if endedLatch.value == nil, !shutdownSent, !unsupportedSeen {
                finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true, reason: "A write to the host failed.")
            }
        case .exited(let exit):
            exitLatch.complete(exit)
            unsupportedKill?.cancel()
            if unsupportedSeen {
                finish(.unsupported)
            } else if shutdownSent, exit == .code(0) || exit == .unknown, calls.isEmpty {
                finish(.clean)
            } else {
                finish(.hostFailure, errorCode: RetroErrorCode.hostExited, reason: "The host exited (\(exit)).")
            }
            release(nil)
        }
    }

    private func onMessage(_ value: RetroJSON, _ descriptor: Int32) throws {
        let map = value.objectValue ?? [:]
        let type = map["type"]?.stringValue ?? ""
        func refuse(_ message: String) -> RetroProtocolError {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return RetroProtocolError(message)
        }
        if descriptor >= 0, type != "ring" { throw refuse("A descriptor came with a \(type) message.") }
        if unsupportedSeen { throw refuse("A \(type) message came after unsupported.") }
        if !greeted, type != "welcome", type != "unsupported" {
            throw refuse("The first message is \(type), not welcome or unsupported.")
        }
        let fields = RetroFields(map, type)
        switch type {
        case "welcome": try onWelcome(fields)
        case "unsupported": try onUnsupported(fields)
        case "reply": try onReply(fields)
        case "pong": try onPong(fields)
        case "ring": try onRing(fields, descriptor)
        case "frame": try onFrame()
        case "rumble": try onRumble(fields)
        default: break
        }
    }

    private func onWelcome(_ f: RetroFields) throws {
        if greeted { throw RetroProtocolError("A second welcome came.") }
        let version = try f.integer("version", 1...RetroProtocol.maxUInt32)
        let hostPid = try f.integer("pid", 1...RetroProtocol.maxUInt32)
        hostRelease = try f.string("hostVersion")
        hostCapabilities = try f.strings("capabilities")
        let format = try f.string("pixelFormat")
        guard version == RetroProtocol.version, let agreed = RetroPixelFormat(rawValue: format),
              offeredFormats.contains(agreed) else {
            unsupportedSeen = true
            finish(.unsupported, kill: true,
                   reason: "welcome picked version \(version) and pixel format \(format), which hello did not offer.")
            return
        }
        guard hostPid == Int(processID) else {
            throw RetroProtocolError("welcome.pid is \(hostPid), not the host's process id \(processID).")
        }
        greeted = true
        agreedFormat = agreed
        nextPing = now + RetroClock.seconds(Self.pingEvery)
        send("volume", .object(["level": .number(volume), "muted": .bool(muted)])) { [self] result in
            readyLatch.complete(result.map { _ in () })
        }
    }

    private func onUnsupported(_ f: RetroFields) throws {
        if greeted { throw RetroProtocolError("unsupported came after welcome.") }
        let low = try f.integer("minVersion", 1...RetroProtocol.maxUInt32)
        let high = try f.integer("maxVersion", 1...RetroProtocol.maxUInt32)
        guard low <= high else { throw RetroProtocolError("unsupported.minVersion is above maxVersion.") }
        _ = try f.strings("pixelFormats")
        unsupportedSeen = true
        reason = "The host speaks versions \(low) to \(high), not this launcher's."
        timer?.cancel()
        timer = nil
        let kill = DispatchWorkItem { [weak self] in self?.finish(.unsupported, kill: true) }
        unsupportedKill = kill
        queue.asyncAfter(deadline: .now() + Self.welcomeLimit, execute: kill)
    }

    private func onReply(_ f: RetroFields) throws {
        let id = try f.integer("id", 1...RetroProtocol.maxID)
        guard let pending = calls.first, pending.id == id else {
            throw RetroProtocolError("reply.id \(id) is not the oldest call still waiting.")
        }
        let hasResult = f.has("result")
        guard hasResult != f.has("error") else { throw RetroProtocolError("A reply needs exactly one of result and error.") }
        let before = expectedRumble()
        if !hasResult {
            let error = try f.object("error")
            let failure = RetroCallError(code: try error.string("code"), message: try error.string("message"))
            calls.removeFirst()
            zeroIfStricter(before)
            pending.done(.failure(failure))
            return
        }
        let result = try checkResult(pending, f.map["result"] ?? .null)
        calls.removeFirst()
        zeroIfStricter(before)
        pending.done(.success(result))
        if pending.method == "start" { zeroInput() }
    }

    private func checkResult(_ pending: Pending, _ result: RetroJSON) throws -> RetroJSON {
        let afterStop = pending.id > stopID
        switch pending.method {
        case "start":
            let started = try RetroFields(result, "start").integer("epoch", 1...RetroProtocol.maxID)
            epoch = started
            gameLoaded = true
            paused = false
            ports = 1
            lastStatusEnded = false
            setFrame(nil, nil)
        case "status":
            if result.isNull {
                if gameLoaded { zeroRumble() }
                gameLoaded = false
                epoch = nil
                lastStatusEnded = false
                if afterStop { stopDeadline = nil }
            } else {
                let status = try RetroStatus.parse(result)
                if status.ended, !lastStatusEnded { zeroRumble() }
                lastStatusEnded = status.ended
                if status.ended, afterStop { stopDeadline = nil }
            }
        case "release":
            try Self.expectNull(pending.method, result)
            if lastStatusEnded {
                gameLoaded = false
                epoch = nil
                if afterStop { stopDeadline = nil }
            }
        case "connectedPorts", "changeDisc", "option":
            guard let accepted = result.boolValue else { throw RetroProtocolError("The result of \(pending.method) must be a boolean.") }
            if pending.method == "connectedPorts", accepted, let count = pending.args.intValue { ports = count }
        case "pause":
            try Self.expectNull(pending.method, result)
            if gameLoaded, let pause = pending.args.boolValue { paused = pause }
        case "volume", "stop":
            try Self.expectNull(pending.method, result)
        default:
            break
        }
        return result
    }

    private static func expectNull(_ method: String, _ value: RetroJSON) throws {
        guard value.isNull else { throw RetroProtocolError("The result of \(method) must be null.") }
    }

    private func onPong(_ f: RetroFields) throws {
        let id = try f.integer("id", 1...RetroProtocol.maxID)
        guard let oldest = pings.first, oldest.id == id else { throw RetroProtocolError("pong.id \(id) is not the oldest ping.") }
        pings.removeFirst()
    }

    /// Maps a new ring. The oldest ring, and the frame shown from it, are let go first, so no more
    /// than two rings are ever mapped (protocol.md "Memory objects"). The descriptor is closed once
    /// mapped, or on any failure.
    private func onRing(_ f: RetroFields, _ descriptor: Int32) throws {
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        let bytes = try f.integer("bytes", RetroFrameRing.minBytes...RetroFrameRing.maxBytes)
        guard descriptor >= 0 else { throw RetroProtocolError("A ring came without its descriptor.") }
        if let previous = previousRing {
            if shownRing === previous {
                shownFrame = nil
                shownRing = nil
            }
            previous.unmap()
            previousRing = nil
        }
        guard let format = agreedFormat else { throw RetroProtocolError("A ring came before welcome.") }
        let made = try RetroFrameRing.map(descriptor: descriptor, bytes: bytes, pixelFormat: format, current: ring)
        previousRing = ring
        ring = made
    }

    private func onFrame() throws {
        guard let current = ring else { throw RetroProtocolError("A frame came before any ring.") }
        let pinned = try current.pin()
        let drawn = pinned != nil && gameLoaded && pinned?.epoch == epoch
        if drawn {
            setFrame(pinned, current)
        } else if current.gaveUpPin, shownRing === current {
            setFrame(nil, nil)
        }
        frameHandler?(RetroFrameEvent(frame: pinned, drawn: drawn))
    }

    /// Keeps `frame`, in `owner`, as the frame to show, and unmaps the older ring once nothing shown
    /// is in it.
    private func setFrame(_ frame: RetroPinnedFrame?, _ owner: RetroFrameRing?) {
        shownFrame = frame
        shownRing = owner
        if let previous = previousRing, shownRing !== previous {
            previous.unmap()
            previousRing = nil
        }
    }

    private func onRumble(_ f: RetroFields) throws {
        let event = RetroRumble(port: try f.integer("port", 0...1), strong: try f.integer("strong", 0...0xFFFF),
                                weak: try f.integer("weak", 0...0xFFFF))
        let expected = expectedRumble()
        guard expected.live, !expected.paused, hasInputFocus, event.port < expected.ports else { return }
        forward(event)
    }

    private func forward(_ event: RetroRumble) {
        guard let handler = rumbleHandler else { return }
        rumbleQueue.async { handler(event) }
    }

    /// Zeroes the motors when the state rumble follows has become stricter than `before`: paused, or
    /// fewer ports with a controller. The end of a game zeroes them where a `status` shows it.
    private func zeroIfStricter(_ before: Expected) {
        let after = expectedRumble()
        if (after.paused && !before.paused) || after.ports < before.ports { zeroRumble() }
    }

    /// Whether a game runs (its `start` answered and its end not seen), whether it is paused and how
    /// many ports have a controller once the host has taken every call sent so far, as it takes them
    /// in order: what the replies confirmed, then each call still waiting as if it succeeds, except
    /// a `start` while a game is loaded, which the host refuses with `busy`. A `start` still waiting
    /// makes no game run, since its game loads only after the reply.
    private func expectedRumble() -> Expected {
        var loaded = gameLoaded
        var live = gameLoaded && !lastStatusEnded
        var paused = self.paused
        var ports = self.ports
        for call in calls {
            switch call.method {
            case "start" where !loaded:
                loaded = true
                live = false
                paused = false
                ports = 1
            case "release" where lastStatusEnded:
                loaded = false
            case "pause" where loaded:
                if let pause = call.args.boolValue { paused = pause }
            case "connectedPorts" where loaded:
                if let count = call.args.intValue, count == 1 || count == 2 { ports = count }
            default:
                break
            }
        }
        return (live: live, paused: paused, ports: ports)
    }

    private func zeroRumble() {
        for port in 0...1 { forward(RetroRumble(port: port, strong: 0, weak: 0)) }
    }

    // MARK: Time limits and the end

    private func checkTime() {
        guard endedLatch.value == nil, let connection else { return }
        let now = self.now
        let writing = connection.writeState()
        if writing.failed, !shutdownSent {
            finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true, reason: "A write to the host failed.")
            return
        }
        var missed: String?
        if let started = writing.startedAt, now > started + RetroClock.seconds(Self.writeLimit) {
            missed = "A write to the host took longer than 5 s."
        } else if !greeted, !unsupportedSeen, now > welcomeDeadline {
            missed = "No welcome within 10 s."
        } else if let first = calls.first, now > first.deadline {
            missed = "No reply to \(first.method) within 5 s."
        } else if let first = pings.first, now > first.deadline {
            missed = "No pong within 5 s."
        } else if let stop = stopDeadline, now > stop {
            missed = "The game had not ended 10 s after stop."
        } else if let shutdown = shutdownDeadline, now > shutdown {
            missed = "The host had not exited 15 s after shutdown."
        }
        if let missed {
            finish(.hostFailure, errorCode: RetroErrorCode.hostHung, kill: true, reason: missed)
            return
        }
        if let next = nextPing, !shutdownSent, now > next, nextPingID <= RetroProtocol.maxID {
            let id = nextPingID
            nextPingID += 1
            pings.append((id: id, deadline: now + RetroClock.seconds(Self.replyLimit)))
            nextPing = now + RetroClock.seconds(Self.pingEvery)
            write(.object(["type": .string("ping"), "id": .int(id)]))
        }
    }

    private func protocolError(_ message: String) {
        finish(.protocolError, errorCode: RetroErrorCode.hostExited, kill: true, reason: message)
    }

    private func finish(_ end: RetroHostEnd, errorCode: String? = nil, kill: Bool = false, reason: String? = nil) {
        guard endedLatch.value == nil else { return }
        endValue = end
        if let reason { self.reason = reason }
        timer?.cancel()
        timer = nil
        if kill { connection?.kill() }
        if gameLoaded { zeroRumble() }
        if end != .clean, end != .unsupported, gameLoaded, let errorCode {
            failedStatus = .failed(
                error: errorCode == RetroErrorCode.hostHung
                    ? "The emulator stopped responding and was closed." : "The emulator closed unexpectedly.",
                errorCode: errorCode)
        }
        while !calls.isEmpty {
            let pending = calls.removeFirst()
            pending.done(afterFailure(pending.method))
        }
        pings.removeAll()
        readyLatch.complete(.failure(RetroHostGone(end: end)))
        endedLatch.complete(end)
        if kill { release(nil) }
    }

    /// Frees the connection once; every caller waits for the same release. The connection's threads
    /// are waited for on another queue, never on this one.
    private func release(_ done: (() -> Void)?) {
        if released {
            done?()
            return
        }
        if let done { releaseWaiters.append(done) }
        guard !releasing else { return }
        releasing = true
        closing = true
        let connection = self.connection
        DispatchQueue.global(qos: .utility).async {
            connection?.close()
            self.queue.async {
                self.connection = nil
                self.previousRing?.unmap()
                self.ring?.unmap()
                self.previousRing = nil
                self.ring = nil
                self.shownFrame = nil
                self.shownRing = nil
                self.released = true
                if self.exitLatch.value == nil { self.exitLatch.complete(.unknown) }
                let waiting = self.releaseWaiters
                self.releaseWaiters = []
                for waiter in waiting { waiter() }
            }
        }
    }

    // MARK: Writing

    /// A message's body, or throws when it cannot be sent: not JSON, or larger than 1 MiB.
    static func encode(_ message: RetroJSON) throws -> [UInt8] {
        let body = try message.encoded()
        guard body.count <= RetroProtocol.maxBody else {
            throw RetroCallError(code: RetroCallError.tooLarge, message: "A message is larger than 1 MiB.")
        }
        return body
    }

    /// The 4-byte little-endian length and `body`.
    static func framed(_ body: [UInt8]) -> [UInt8] {
        let count = UInt32(body.count)
        return [UInt8(count & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count >> 16 & 0xFF), UInt8(count >> 24 & 0xFF)] + body
    }

    private func write(_ message: RetroJSON) {
        guard let body = try? Self.encode(message) else { return }
        write(body: body)
    }

    private func write(body: [UInt8]) {
        guard let connection, !closing else { return }
        if !connection.send(Self.framed(body)), !shutdownSent, endedLatch.value == nil {
            finish(.hostFailure, errorCode: RetroErrorCode.hostExited, kill: true, reason: "A write to the host failed.")
        }
    }
}
