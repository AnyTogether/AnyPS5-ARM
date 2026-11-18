import CRetroHostTesting
import Darwin
import XCTest
@testable import AnyPS5Core

/// The control stream's framing on the launcher's side (protocol.md "Framing"): the reader on one end
/// of a socketpair, this test writing the host's end.
final class RetroHostFramingTests: XCTestCase {
    private var launcherEnd: Int32 = -1
    private var hostEnd: Int32 = -1
    private let lock = NSLock()
    private var events: [RetroHostConnectionEvent] = []
    /// Left once the reader has returned. A group rather than an expectation: a test that never
    /// reads (the pure framing ones at the end) would leave an expectation unwaited, which fails it.
    private let reading = DispatchGroup()

    override func setUpWithError() throws {
        var ends: [Int32] = [-1, -1]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &ends), 0)
        launcherEnd = ends[0]
        hostEnd = ends[1]
        var on: Int32 = 1
        setsockopt(hostEnd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        events = []
        let reader = RetroHostReader(socket: launcherEnd) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.events.append(event)
            self.lock.unlock()
        }
        let group = reading
        group.enter()
        Thread {
            reader.run()
            group.leave()
        }.start()
    }

    /// Ends the host's side and lets the reader return before its socket is closed, so the reader is
    /// never left reading a descriptor that is closed (and maybe reused) under it.
    override func tearDown() {
        if hostEnd >= 0 { close(hostEnd) }
        XCTAssertEqual(reading.wait(timeout: .now() + 10), .success, "the reader ends")
        if launcherEnd >= 0 { close(launcherEnd) }
        hostEnd = -1
        launcherEnd = -1
    }

    private func frame(_ text: String) -> [UInt8] { RetroHostClient.framed(Array(text.utf8)) }

    private func send(_ bytes: [UInt8], descriptors: [Int32] = []) {
        let sent = bytes.withUnsafeBytes { raw in
            descriptors.withUnsafeBufferPointer { fds in
                anyps5_retro_test_send(hostEnd, raw.baseAddress, raw.count, fds.baseAddress, fds.count)
            }
        }
        XCTAssertEqual(sent, bytes.count)
    }

    private func endHost() {
        close(hostEnd)
        hostEnd = -1
    }

    private func finish() -> [RetroHostConnectionEvent] {
        XCTAssertEqual(reading.wait(timeout: .now() + 10), .success, "the reader ends")
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    private func spare() -> Int32 { open("/dev/null", O_RDONLY) }

    private func messages(_ events: [RetroHostConnectionEvent]) -> [(RetroJSON, Int32)] {
        events.compactMap { event in
            if case .message(let value, let descriptor) = event { return (value, descriptor) }
            return nil
        }
    }

    private func problem(_ events: [RetroHostConnectionEvent]) -> String? {
        for event in events {
            if case .protocolError(let text) = event { return text }
        }
        return nil
    }

    func testWholeMessagesComeInOrderAndTheEndIsReported() {
        send(frame(#"{"type":"welcome"}"#) + frame(#"{"type":"frame"}"#))
        let split = frame(#"{"type":"pong","id":1}"#)
        send(Array(split[0..<2]))
        send(Array(split[2..<7]))
        send(Array(split[7...]))
        endHost()
        let seen = finish()
        XCTAssertEqual(messages(seen).map { $0.0.objectValue?["type"]?.stringValue }, ["welcome", "frame", "pong"])
        XCTAssertTrue(messages(seen).allSatisfy { $0.1 == -1 })
        guard case .endOfStream? = seen.last else { return XCTFail("\(seen)") }
    }

    func testALengthOutsideTwoToOneMiBIsAnError() {
        send([1, 0, 0, 0, 0x7B])
        XCTAssertNotNil(problem(finish()))
    }

    func testALengthAboveOneMiBIsAnErrorBeforeTheBody() {
        send([0x01, 0x00, 0x10, 0x00])
        XCTAssertNotNil(problem(finish()))
    }

    func testABodyThatIsNotOneJSONObjectWithATypeIsAnError() {
        send(frame("[1,2]"))
        XCTAssertNotNil(problem(finish()))
    }

    func testARingKeepsItsOneDescriptorWithCloseOnExec() throws {
        let memory = spare()
        let bytes = frame(#"{"type":"ring","bytes":4108}"#)
        send(Array(bytes[0..<1]), descriptors: [memory])
        send(Array(bytes[1...]))
        close(memory)
        endHost()
        let seen = finish()
        let ring = try XCTUnwrap(messages(seen).first)
        XCTAssertEqual(ring.0.objectValue?["type"]?.stringValue, "ring")
        XCTAssertGreaterThanOrEqual(ring.1, 0)
        XCTAssertNotEqual(fcntl(ring.1, F_GETFD) & FD_CLOEXEC, 0)
        close(ring.1)
    }

    func testADescriptorOnAnotherMessageIsAnError() {
        let stray = spare()
        send(frame(#"{"type":"frame"}"#), descriptors: [stray])
        close(stray)
        let seen = finish()
        XCTAssertNotNil(problem(seen))
        XCTAssertTrue(messages(seen).isEmpty)
    }

    func testTwoDescriptorsOnARingAreAnError() {
        let first = spare()
        let second = spare()
        send(frame(#"{"type":"ring","bytes":4108}"#), descriptors: [first, second])
        close(first)
        close(second)
        XCTAssertNotNil(problem(finish()))
    }

    func testADescriptorAfterTheFirstReadOfAMessageIsAnError() {
        let late = spare()
        let bytes = frame(#"{"type":"ring","bytes":4108}"#)
        send(Array(bytes[0..<4]))
        Thread.sleep(forTimeInterval: 0.2)
        send(Array(bytes[4...]), descriptors: [late])
        close(late)
        XCTAssertNotNil(problem(finish()))
    }

    func testTheStreamEndingInsideAMessageIsTheEndWithNoMessage() {
        let memory = spare()
        let bytes = frame(#"{"type":"ring","bytes":4108}"#)
        send(Array(bytes[0..<6]), descriptors: [memory])
        close(memory)
        endHost()
        let seen = finish()
        XCTAssertTrue(messages(seen).isEmpty)
        guard case .endOfStream? = seen.last else { return XCTFail("\(seen)") }
    }

    func testAFramedMessageIsTheLittleEndianLengthAndTheBody() {
        XCTAssertEqual(RetroHostClient.framed([0x7B, 0x7D]), [2, 0, 0, 0, 0x7B, 0x7D])
        XCTAssertEqual(Array(RetroHostClient.framed(Array(repeating: 0x20, count: 0x0102_03))[0..<4]), [0x03, 0x02, 0x01, 0x00])
    }

    func testAMessageOverOneMiBIsRefusedBeforeItIsSent() {
        let large = RetroJSON.object(["type": .string("call"), "args": .string(String(repeating: "x", count: 1_100_000))])
        XCTAssertThrowsError(try RetroHostClient.encode(large))
    }
}
