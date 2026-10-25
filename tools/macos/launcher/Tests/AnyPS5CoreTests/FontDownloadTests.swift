import Foundation
import Network
import XCTest
@testable import AnyPS5Core

/// One file over HTTP that honours `Range: bytes=N-` as GitHub's storage does, and can send it
/// to another path first, drop the first connection part way or ignore Range altogether.
final class RangeServer: @unchecked Sendable {
    let listener: NWListener
    let body: Data
    var redirect = false
    var ignoreRange = false
    /// The first connection sends this many bytes of the body and then closes.
    var dropFirstAfter: Int?
    private let lock = NSLock()
    private var connections = 0
    private(set) var ranges: [String?] = []

    init(body: Data) throws {
        self.body = body
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/\(redirect ? "latest" : "fonts")/03_NotoSansCJK-OTC.zip")! }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        receiveHead(connection, Data())
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

    private func answer(_ connection: NWConnection, _ request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let range = lines.first { $0.lowercased().hasPrefix("range:") }.map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
        if path.hasPrefix("/latest/") {
            let head = "HTTP/1.1 302 Found\r\nLocation: /fonts/03_NotoSansCJK-OTC.zip\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            return connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        let first: Bool = lock.withLock {
            ranges.append(range)
            connections += 1
            return connections == 1
        }
        var start = 0
        if !ignoreRange, let range, range.hasPrefix("bytes="), let from = Int(range.dropFirst(6).prefix { $0 != "-" }) { start = from }
        var head: String
        if start >= body.count && start > 0 {
            head = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(body.count)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            return connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        let part = body.subdata(in: start..<body.count)
        if start > 0 {
            head = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(body.count - 1)/\(body.count)\r\nContent-Length: \(part.count)\r\nConnection: close\r\n\r\n"
        } else {
            head = "HTTP/1.1 200 OK\r\nContent-Length: \(part.count)\r\nContent-Type: application/zip\r\nConnection: close\r\n\r\n"
        }
        var sent = part
        if first, let drop = dropFirstAfter { sent = part.prefix(drop) }
        connection.send(content: Data(head.utf8) + sent, completion: .contentProcessed { _ in connection.cancel() })
    }
}

final class FontDownloadTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("font-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A small archive like Noto's: two collections in it and its licence, plus one not wanted.
    private func archive() throws -> (zip: Data, files: [String: Data]) {
        let source = scratch.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let files = [
            "NotoSansCJK-Regular.ttc": Data((0..<180_000).map { UInt8(($0 * 7) % 251) }),
            "NotoSansCJK-Bold.ttc": Data((0..<120_000).map { UInt8(($0 * 13) % 241) }),
            "LICENSE": Data("SIL Open Font License, Version 1.1".utf8),
            "NotoSansCJK-Thin.ttc": Data(repeating: 9, count: 1000),
        ]
        for (name, data) in files { try data.write(to: source.appendingPathComponent(name)) }
        let zip = scratch.appendingPathComponent("fonts.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -0 stores them as they are, so the archive is big enough to come in several pieces.
        process.arguments = ["-q", "-0", "-j", zip.path] + files.keys.sorted().map { source.appendingPathComponent($0).path }
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return (try Data(contentsOf: zip), files)
    }

    private func digest(_ data: Data) throws -> String {
        let file = scratch.appendingPathComponent("digest-\(UUID().uuidString)")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try FontDownloads.sha256(of: file)
    }

    private func package(_ url: URL, zip: Data, files: [String: Data], archiveDigest: String? = nil, regularDigest: String? = nil) throws -> FontPackage {
        FontPackage(url: url, sha256: try archiveDigest ?? digest(zip), size: Int64(zip.count), files: [
            .init(member: "NotoSansCJK-Regular.ttc", name: "NotoSansCJK-Regular.ttc", sha256: try regularDigest ?? digest(files["NotoSansCJK-Regular.ttc"]!), size: Int64(files["NotoSansCJK-Regular.ttc"]!.count)),
            .init(member: "NotoSansCJK-Bold.ttc", name: "NotoSansCJK-Bold.ttc", sha256: try digest(files["NotoSansCJK-Bold.ttc"]!), size: Int64(files["NotoSansCJK-Bold.ttc"]!.count)),
            .init(member: "LICENSE", name: "LICENSE-NotoSansCJK.txt", sha256: try digest(files["LICENSE"]!), size: Int64(files["LICENSE"]!.count)),
        ])
    }

    private var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return configuration
    }

    func testTheFontsComeInCheckedAndTheArchiveGoes() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        XCTAssertFalse(downloads.installed)
        let seen = Locked<[Double]>([])
        try await downloads.install(configuration: configuration) { seen.value.append($0) }
        XCTAssertTrue(downloads.installed)
        XCTAssertEqual(try Data(contentsOf: downloads.folder.appendingPathComponent("NotoSansCJK-Regular.ttc")), files["NotoSansCJK-Regular.ttc"])
        XCTAssertEqual(try Data(contentsOf: downloads.folder.appendingPathComponent("LICENSE-NotoSansCJK.txt")), files["LICENSE"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: downloads.folder.path).sorted(),
                       ["LICENSE-NotoSansCJK.txt", "NotoSansCJK-Bold.ttc", "NotoSansCJK-Regular.ttc"], "the font not asked for and the archive are gone")
        XCTAssertEqual(seen.value.last, 1)
        XCTAssertEqual(server.ranges, [nil])
    }

    func testADroppedConnectionGoesOnWhereItStopped() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        server.dropFirstAfter = zip.count * 2 / 5
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        try await downloads.install(configuration: configuration)
        XCTAssertTrue(downloads.installed)
        XCTAssertEqual(server.ranges.count, 2)
        XCTAssertEqual(server.ranges.last, "bytes=\(zip.count * 2 / 5)-")
    }

    func testADownloadKeptFromBeforeIsGoneOnFromAcrossTheRedirect() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        server.redirect = true
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        try FileManager.default.createDirectory(at: downloads.downloads, withIntermediateDirectories: true)
        try zip.prefix(1000).write(to: downloads.partial)
        XCTAssertEqual(downloads.resumable, 1000)
        try await downloads.install(configuration: configuration)
        XCTAssertTrue(downloads.installed)
        XCTAssertEqual(server.ranges, ["bytes=1000-"])
    }

    func testAServerThatSendsTheWholeFileStartsItAgain() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        server.ignoreRange = true
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        try FileManager.default.createDirectory(at: downloads.downloads, withIntermediateDirectories: true)
        try Data(repeating: 0xEE, count: 700).write(to: downloads.partial)
        try await downloads.install(configuration: configuration)
        XCTAssertTrue(downloads.installed)
        XCTAssertEqual(server.ranges, ["bytes=700-"])
    }

    func testAWholeButWrongDownloadKeptFromBeforeIsFetchedAgain() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        try FileManager.default.createDirectory(at: downloads.downloads, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: zip.count).write(to: downloads.partial)
        try await downloads.install(configuration: configuration)
        XCTAssertTrue(downloads.installed)
        XCTAssertEqual(server.ranges, [nil], "the full-size file kept is checked, refused and fetched once more from the start")
    }

    func testAnArchiveThatDoesNotMatchItsDigestIsRefused() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files, archiveDigest: String(repeating: "0", count: 64)), folder: scratch.appendingPathComponent("CJK"))
        do {
            try await downloads.install(configuration: configuration)
            XCTFail("a download that does not match was installed")
        } catch let error as FontDownloadError {
            XCTAssertTrue(error.message.contains("SHA-256"), error.message)
        }
        XCTAssertFalse(downloads.installed)
        XCTAssertEqual(downloads.resumable, -1, "the bad download is not kept to go on from")
    }

    func testAFontThatDoesNotMatchItsDigestIsNotInstalled() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files, regularDigest: String(repeating: "a", count: 64)), folder: scratch.appendingPathComponent("CJK"))
        do {
            try await downloads.install(configuration: configuration)
            XCTFail("a font that does not match was installed")
        } catch let error as FontDownloadError {
            XCTAssertTrue(error.message.contains("NotoSansCJK-Regular.ttc"), error.message)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.folder.appendingPathComponent("NotoSansCJK-Bold.ttc").path), "nothing goes in unless everything matches")
    }

    func testRemovingThemTakesTheFolder() async throws {
        let (zip, files) = try archive()
        let server = try RangeServer(body: zip)
        defer { server.listener.cancel() }
        let downloads = FontDownloads(package: try package(server.url, zip: zip, files: files), folder: scratch.appendingPathComponent("CJK"))
        try await downloads.install(configuration: configuration)
        try downloads.remove()
        XCTAssertFalse(downloads.installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.folder.path))
    }

    func testNotosOwnReleaseIsPinned() {
        let package = FontPackage.notoCJK
        XCTAssertEqual(package.url.host, "github.com")
        XCTAssertTrue(package.url.path.hasPrefix("/notofonts/noto-cjk/releases/download/"))
        XCTAssertEqual(package.sha256.count, 64)
        XCTAssertTrue(package.files.allSatisfy { $0.sha256.count == 64 && $0.size > 0 })
        XCTAssertEqual(Set(package.files.map(\.name)).subtracting(["LICENSE-NotoSansCJK.txt"]), Set(FontScript.japanese.notoFiles))
        XCTAssertEqual(ResumableDownload.start(ofContentRange: "bytes 1000-1999/2000"), 1000)
        XCTAssertNil(ResumableDownload.start(ofContentRange: "bytes */2000"))
    }
}
