import Foundation
import Network
import XCTest
@testable import AnyPS5Core

/// A release file as GitHub serves it: `/download/<name>` redirects to `/blob/<name>?sig=<n>` (the
/// storage host, at an address signed afresh for each request), which honours
/// `Range: bytes=N-`. Each storage request takes the next answer of `script`, then `every` once
/// the script is used up (a whole answer by default). Every request is recorded.
final class RetryServer: @unchecked Sendable {
    enum Answer {
        /// The rest of the file.
        case whole
        /// The head and this many bytes, then the connection closes.
        case drop(after: Int)
        /// Only this status, as the storage host answers a signed address that expired (403).
        case refuse(Int)
        /// The head and this many bytes, then nothing more on a connection that stays open.
        case stall(after: Int)
    }

    struct Request: Equatable {
        var path: String
        var range: String?
        /// The signature number of a storage request, nil for the release's own address.
        var signature: Int?
    }

    let listener: NWListener
    let body: Data
    let name = "AnyPS5-toolkit-macos-0.2.41-arm.zip"
    private let lock = NSLock()
    private var script: [Answer]
    private let every: Answer
    private var signed = 0
    private var held: [NWConnection] = []
    private var asked: [Request] = []

    init(body: Data, script: [Answer] = [], every: Answer = .whole) throws {
        self.body = body
        self.script = script
        self.every = every
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.receiveHead(connection, Data())
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/download/\(name)")! }
    var requests: [Request] { lock.withLock { asked } }
    var storageRequests: [Request] { requests.filter { $0.signature != nil } }

    func stop() {
        listener.cancel()
        for connection in lock.withLock({ held }) { connection.cancel() }
    }

    private func receiveHead(_ connection: NWConnection, _ head: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, _ in
            let head = head + (data ?? Data())
            guard let text = String(data: head, encoding: .utf8), text.contains("\r\n\r\n") else {
                return done ? connection.cancel() : receiveHead(connection, head)
            }
            answer(connection, text)
        }
    }

    private func send(_ connection: NWConnection, _ data: Data, thenClose: Bool = true) {
        connection.send(content: data, completion: .contentProcessed { _ in
            // A moment for the client to take in what came before the connection goes.
            if thenClose { DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) { connection.cancel() } }
        })
    }

    private func answer(_ connection: NWConnection, _ request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let path = String(target.split(separator: "?").first ?? "")
        let range = lines.first { $0.lowercased().hasPrefix("range:") }.map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
        if path == "/download/\(name)" {
            let signature: Int = lock.withLock {
                asked.append(Request(path: path, range: range, signature: nil))
                signed += 1
                return signed
            }
            return send(connection, Data("HTTP/1.1 302 Found\r\nLocation: /blob/\(name)?sig=\(signature)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        }
        let signature = Int(target.split(separator: "=").last ?? "") ?? 0
        let next: Answer = lock.withLock {
            asked.append(Request(path: path, range: range, signature: signature))
            return script.isEmpty ? every : script.removeFirst()
        }
        var start = 0
        if let range, range.hasPrefix("bytes="), let from = Int(range.dropFirst(6).prefix { $0 != "-" }) { start = from }
        if case .refuse(let status) = next {
            return send(connection, Data("HTTP/1.1 \(status) Refused\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        }
        if start >= body.count && start > 0 {
            return send(connection, Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(body.count)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
        }
        let part = body.subdata(in: start..<body.count)
        let head = start > 0
            ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(body.count - 1)/\(body.count)\r\nContent-Length: \(part.count)\r\nConnection: close\r\n\r\n"
            : "HTTP/1.1 200 OK\r\nContent-Length: \(part.count)\r\nContent-Type: application/zip\r\nConnection: close\r\n\r\n"
        switch next {
        case .whole, .refuse:
            send(connection, Data(head.utf8) + part)
        case .drop(let after):
            send(connection, Data(head.utf8) + part.prefix(after))
        case .stall(let after):
            lock.withLock { held.append(connection) }
            send(connection, Data(head.utf8) + part.prefix(after), thenClose: false)
        }
    }
}

/// Downloads that fail on the way are tried again by themselves, from the release's own address
/// each time, going on from what came (issue #187 of AnyPS5 Desktop, the same on the Mac).
final class DownloadRetryTests: XCTestCase {
    private var scratch: URL!
    private var pauses: [Duration] = []
    private let body: Data = {
        var bytes = [UInt8](repeating: 0, count: 300_000)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 7 &+ index / 251) }
        return Data(bytes)
    }()

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("download-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        pauses = DownloadRetry.pauses
        DownloadRetry.pauses = [.milliseconds(10)]
    }

    override func tearDown() {
        DownloadRetry.pauses = pauses
        try? FileManager.default.removeItem(at: scratch)
    }

    private var file: URL { scratch.appendingPathComponent("AnyPS5-toolkit-macos-0.2.41-arm.zip.part") }

    private func configuration(timeout: TimeInterval = 30) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        return configuration
    }

    private func download(_ server: RetryServer, timeout: TimeInterval = 30) async throws {
        try await DownloadRetry.run(url: server.url, file: file, expected: Int64(body.count), configuration: configuration(timeout: timeout)) { _ in }
    }

    func testAResumeRefusedWith403RetriesFromTheAssetURLAndFinishes() async throws {
        let server = try RetryServer(body: body, script: [.drop(after: 120_000), .refuse(403)])
        defer { server.stop() }
        try await download(server)
        XCTAssertEqual(try Data(contentsOf: file), body)
        // Every try starts at the release's address, so the storage address is signed afresh.
        let pair: [String] = ["/download/\(server.name)", "/blob/\(server.name)"]
        let paths: [String] = server.requests.map { (request: RetryServer.Request) in request.path }
        XCTAssertEqual(paths, pair + pair + pair)
        let signatures: [Int?] = server.storageRequests.map { (request: RetryServer.Request) in request.signature }
        XCTAssertEqual(signatures, [1, 2, 3])
        // The two tries after the drop ask for the same rest of the file, at both addresses.
        let resumes: [String?] = server.requests.dropFirst(2).map { (request: RetryServer.Request) in request.range }
        XCTAssertEqual(Set(resumes).count, 1, "\(resumes)")
    }

    func testAResumeRefusedWith401And410IsTriedAgainEachTime() async throws {
        let server = try RetryServer(body: body, script: [.drop(after: 120_000), .refuse(401), .refuse(410)])
        defer { server.stop() }
        try await download(server)
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertEqual(server.storageRequests.count, 4)
    }

    func testAStalledConnectionIsGivenUpAndTheDownloadCarriesOn() async throws {
        let server = try RetryServer(body: body, script: [.stall(after: 90_000)])
        defer { server.stop() }
        try await download(server, timeout: 1)
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertEqual(server.storageRequests.count, 2)
        XCTAssertNotNil(server.storageRequests.last?.range, "the second try asks only for the rest")
    }

    func testAConnectionThatKeepsDroppingGivesUpAfterItsTriesKeepingThePart() async throws {
        let failing = try RetryServer(body: body, every: .drop(after: 20_000))
        do {
            try await download(failing)
            XCTFail("a download that keeps dropping finished")
        } catch {
            XCTAssertTrue(DownloadRetry.passing(error), "\(error)")
        }
        failing.stop()
        XCTAssertEqual(failing.storageRequests.count, DownloadRetry.attempts)
        let kept = FontDownloads.size(of: file)
        XCTAssertGreaterThan(kept, 0, "what came is kept")
        // The next download carries on from there.
        let server = try RetryServer(body: body)
        defer { server.stop() }
        try await download(server)
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertEqual(server.storageRequests.first?.range, "bytes=\(kept)-")
    }

    func testAFileTheStorageHostDoesNotHaveIsNotAskedForAgain() async throws {
        let server = try RetryServer(body: body, script: [.refuse(404), .refuse(404)])
        defer { server.stop() }
        do {
            try await download(server)
            XCTFail("a 404 finished")
        } catch let error as FontDownloadError {
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.message, "the server answered 404")
        }
        XCTAssertEqual(server.storageRequests.count, 1)
    }

    func testStoppingDuringThePauseBeforeTheNextTryStopsAtOnce() async throws {
        DownloadRetry.pauses = [.seconds(30)]
        let server = try RetryServer(body: body, every: .drop(after: 20_000))
        defer { server.stop() }
        let started = Date()
        let (url, file, size) = (server.url, file, Int64(body.count))
        let task = Task {
            let configuration = URLSessionConfiguration.ephemeral
            try await DownloadRetry.run(url: url, file: file, expected: size, configuration: configuration) { _ in }
        }
        // The first try drops, then the pause before the second begins.
        for _ in 0..<200 where server.storageRequests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(800))
        task.cancel()
        do {
            try await task.value
            XCTFail("a stopped download finished")
        } catch {
            XCTAssertFalse(DownloadRetry.passing(error), "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(server.storageRequests.count, 1)
    }

    func testWhichFailuresAreTriedAgain() {
        for status in [401, 403, 408, 410, 429, 500, 502, 503] { XCTAssertTrue(DownloadRetry.passing(status: status), "\(status)") }
        for status in [400, 404, 416] { XCTAssertFalse(DownloadRetry.passing(status: status), "\(status)") }
        XCTAssertTrue(DownloadRetry.passing(URLError(.networkConnectionLost)))
        XCTAssertTrue(DownloadRetry.passing(URLError(.timedOut)))
        XCTAssertFalse(DownloadRetry.passing(URLError(.cancelled)))
        XCTAssertFalse(DownloadRetry.passing(CancellationError()))
        XCTAssertFalse(DownloadRetry.passing(FontDownloadError("the download was redirected from https to http")))
    }
}
