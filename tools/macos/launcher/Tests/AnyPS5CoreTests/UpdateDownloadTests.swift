import Foundation
import Network
import XCTest
@testable import AnyPS5Core

/// One file over HTTP, sent in slow pieces so a download takes a while.
final class SlowServer: @unchecked Sendable {
    let listener: NWListener
    let body: Data

    init(body: Data) throws {
        self.body = body
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [body] connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let head = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nContent-Type: application/zip\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: head, completion: .idempotent)
                let pieces = 6
                let size = body.count / pieces
                for piece in 0..<pieces {
                    let end = piece == pieces - 1 ? body.count : (piece + 1) * size
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(120 * piece)) {
                        connection.send(content: body.subdata(in: piece * size..<end), completion: .contentProcessed { _ in
                            if piece == pieces - 1 { connection.cancel() }
                        })
                    }
                }
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/AnyPS5-macOS.zip")! }
}

final class UpdateDownloadTests: XCTestCase {
    func testTheDownloadReportsHowFarItIs() async throws {
        let body = Data((0..<300_000).map { UInt8($0 % 251) })
        let server = try SlowServer(body: body)
        defer { server.listener.cancel() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: file) }
        let seen = Locked<[Double]>([])
        try await Updates.download(server.url, to: file) { fraction in seen.value.append(fraction) }
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertTrue(seen.value.contains { $0 > 0 && $0 < 1 }, "progress seen: \(seen.value)")
        XCTAssertEqual(seen.value.last, 1)
    }
}
