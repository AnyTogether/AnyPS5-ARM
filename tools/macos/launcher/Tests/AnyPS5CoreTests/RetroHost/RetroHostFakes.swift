import Foundation
import XCTest
@testable import AnyPS5Core

/// Something a test opens by hand, and everyone waiting for it.
final class RetroGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let waiting = waiters
        waiters = []
        lock.unlock()
        for waiter in waiting { waiter.resume() }
    }
}

/// A value that comes once, and everyone waiting for it.
final class RetroLatch<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    var value: Value? { lock.withLock { stored } }

    func complete(_ value: Value) {
        lock.lock()
        guard stored == nil else { return lock.unlock() }
        stored = value
        let waiting = waiters
        waiters = []
        lock.unlock()
        for waiter in waiting { waiter.resume(returning: value) }
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let stored {
                lock.unlock()
                continuation.resume(returning: stored)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// A host session that records what the launcher asked and answers as the test says, as AnyPS5
/// Desktop's test/ui/retro_host/fake_retro_host_session.dart does.
final class FakeRetroHostSession: RetroHostSession, @unchecked Sendable {
    private let lock = NSLock()
    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    let greeting = RetroLatch<Bool>()
    let ending = RetroLatch<RetroHostEnd>()

    private var calledStore: [(String, RetroJSON)] = []
    private var inputStore: [(Int, RetroPadInput)] = []
    private var focusStore: [Bool] = []
    private var frameHandler: ((RetroFrameEvent) -> Void)?
    private var rumbleHandler: ((RetroRumble) -> Void)?

    /// When set, every call is answered only once it opens.
    var callGate: RetroGate?
    /// What a call returns, by method; null for any other.
    var callResults: [String: RetroJSON] = [:]
    /// What a call throws, by method.
    var callErrors: [String: Error] = [:]
    var startArgs: RetroJSON?
    var startError: Error?
    /// When set, `start` is answered only once it opens.
    var startGate: RetroGate?
    var nextStatus: RetroStatus?
    var statusError: Error?
    var stopStatus: RetroStatus? = RetroStatus(ready: true, ended: true, error: "", errorCode: "")
    var shutdownAsked = false
    /// Whether the host exits when it is told to shut down; false for one that never does.
    var exitsOnShutdown = true
    var closed = false
    /// Focus was set after the session was closed.
    var focusAfterClose = false
    var canPlayPs2 = true
    /// Whether the host lists `saveStates`; false, as for the signed host v1.0.0, unless a test says.
    var canSaveStates = false
    /// Whether the host lists `ps2ResolutionLimits`; false, as for the signed host v1.0.0, unless a
    /// test says.
    var limitsPs2Resolution = false
    /// Runs as each call is taken, before it is answered: what the host does meanwhile (writes a
    /// state's file).
    var onCall: ((String, RetroJSON) -> Void)?

    var calls: [(String, RetroJSON)] { locked { calledStore } }
    var methods: [String] { calls.map(\.0) }
    var inputs: [(Int, RetroPadInput)] { locked { inputStore } }
    var focusChanges: [Bool] { locked { focusStore } }
    var hasHandlers: Bool { locked { frameHandler != nil } }

    /// The host greets the launcher, or (`false`) never does.
    func greet(_ greeted: Bool = true) { greeting.complete(greeted) }
    func end(_ end: RetroHostEnd) { ending.complete(end) }

    func ready() async throws {
        if await greeting.wait() == false { throw RetroHostGone(end: .hostFailure) }
    }

    func ended() async -> RetroHostEnd { await ending.wait() }
    var end: RetroHostEnd? { ending.value }

    func setInputFocus(_ focused: Bool) {
        locked {
            if closed { focusAfterClose = true }
            focusStore.append(focused)
        }
    }

    func startGame(_ args: RetroJSON) async throws -> Int {
        locked { startArgs = args }
        await startGate?.wait()
        if let startError { throw startError }
        return 1
    }

    /// `release` forgets an ended game, as protocol.md "release" says: `status` is then null.
    func call(_ method: String, _ args: RetroJSON) async throws -> RetroJSON {
        locked { calledStore.append((method, args)) }
        onCall?(method, args)
        await callGate?.wait()
        if let error = callErrors[method] { throw error }
        if method == "release", nextStatus?.ended ?? true { nextStatus = nil }
        return callResults[method] ?? .null
    }

    func status() async throws -> RetroStatus? {
        if let statusError { throw statusError }
        return nextStatus
    }

    /// `stop`: the game has ended, and `status` says so until `release`.
    func stopGame() async throws -> RetroStatus? {
        locked { calledStore.append(("stop", .null)) }
        if nextStatus != nil { nextStatus = stopStatus }
        return stopStatus
    }

    func input(port: Int, buttons: Int, leftX: Int, leftY: Int, rightX: Int, rightY: Int) {
        locked { inputStore.append((port, RetroPadInput(buttons: buttons, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY))) }
    }

    func clearInputs() { locked { inputStore = [] } }
    func clearCalls() { locked { calledStore = [] } }
    func clearFocusChanges() { locked { focusStore = [] } }

    func shutdown() {
        shutdownAsked = true
        if exitsOnShutdown { ending.complete(.clean) }
    }

    func close() async { closed = true }

    func setHandlers(frame: ((RetroFrameEvent) -> Void)?, rumble: ((RetroRumble) -> Void)?) {
        locked {
            frameHandler = frame
            rumbleHandler = rumble
        }
    }

    /// A `frame` event, handled where the test calls it.
    func send(_ frame: RetroPinnedFrame?, drawn: Bool = true) {
        locked { frameHandler }?(RetroFrameEvent(frame: frame, drawn: drawn))
    }

    /// A `rumble` message from the host.
    func sendRumble(_ port: Int, _ strong: Int, _ weak: Int) {
        locked { rumbleHandler }?(RetroRumble(port: port, strong: strong, weak: weak))
    }
}

/// Pixels in memory, as a ring slot would hold them.
final class FakeSlot {
    let width: Int
    let height: Int
    let pixels: UnsafeMutableRawPointer

    init(_ width: Int, _ height: Int) {
        self.width = width
        self.height = height
        pixels = UnsafeMutableRawPointer.allocate(byteCount: width * height * 4, alignment: 16)
        pixels.initializeMemory(as: UInt8.self, repeating: 0, count: width * height * 4)
    }

    deinit { pixels.deallocate() }

    func fill(_ pixel: [UInt8]) {
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        for index in 0..<(width * height * 4) { bytes[index] = pixel[index % 4] }
    }

    func pin(epoch: Int = 1, format: RetroPixelFormat = .rgba8) -> RetroPinnedFrame {
        RetroPinnedFrame(slot: 0, width: width, height: height, epoch: epoch, visible: true, pixels: UnsafeRawPointer(pixels),
                         pixelFormat: format)
    }
}

func fakeStatus(ready: Bool = true, ended: Bool = false, aspect: Double = 4.0 / 3.0, errorCode: String = "",
                cardUnreadable: Bool = false) -> RetroStatus {
    var status = RetroStatus(ready: ready, ended: ended, error: "", errorCode: errorCode)
    status.aspect = aspect
    status.cardUnreadable = cardUnreadable
    return status
}

/// Controllers the test holds by hand.
final class FakePads {
    var order: [String] = []
    var states: [String: PadState] = [:]

    var reader: RetroPadReader { RetroPadReader(pads: { [unowned self] in self.order }, state: { [unowned self] in self.states[$0] }) }

    func connect(_ id: String, _ state: PadState = .idle) {
        order.append(id)
        states[id] = state
    }

    func disconnect(_ id: String) {
        order.removeAll { $0 == id }
        states[id] = nil
    }
}

/// Motors that record what they were told.
@MainActor
final class FakeMotors: RetroPadMotors {
    var vibrating: Set<String> = []
    var orders: [(pad: String, strong: Double, weak: Double, hold: Duration)] = []

    func canRumble(_ pad: String) -> Bool { vibrating.contains(pad) }

    func rumble(_ pad: String, strong: Double, weak: Double, hold: Duration) {
        orders.append((pad, strong, weak, hold))
    }
}

/// Waits, a little at a time, until `condition` holds.
@MainActor
func settleRetro(_ condition: () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(condition(), message, file: file, line: line)
}

/// Lets the main queue and the tasks waiting on it run.
@MainActor
func yieldRetro(_ times: Int = 5) async {
    for _ in 0..<times {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}
