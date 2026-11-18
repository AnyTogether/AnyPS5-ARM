import XCTest
@testable import AnyPS5Core

/// A fake GitHub for the host's releases: the API's list, and each release's files by their
/// download address. Every request is recorded.
final class RetroHostFakeGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var redirects: [String: String] = [:]
    nonisolated(unsafe) static var asked: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.withLock {
            files = [:]
            redirects = [:]
            asked = []
        }
    }

    static var requests: [String] { lock.withLock { asked } }

    /// `release`'s files at https://github.example/<tag>/<name>, and its entry for the list.
    static func publish(_ release: [String: Data], tag: String, prerelease: Bool = false, draft: Bool = false) -> [String: Any] {
        lock.withLock {
            for (name, data) in release { files["https://github.example/\(tag)/\(name)"] = data }
        }
        return ["tag_name": tag, "prerelease": prerelease, "draft": draft,
                "assets": release.keys.sorted().map { name in
                    ["name": name, "browser_download_url": "https://github.example/\(tag)/\(name)", "size": release[name]!.count,
                     "digest": "sha256:\(RetroHostRelease.sha256(release[name]!))"] as [String: Any]
                }]
    }

    static func list(_ releases: [[String: Any]]) {
        let data = try! JSONSerialization.data(withJSONObject: releases)
        lock.withLock { files["https://api.github.example/repos/\(RetroHostStore.repository)/releases?per_page=100"] = data }
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetroHostFakeGitHub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let address = request.url?.absoluteString ?? ""
        let (body, redirect): (Data?, String?) = Self.lock.withLock {
            asked.append(address)
            return (files[address], redirects[address])
        }
        if let redirect, let target = URL(string: redirect) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": redirect])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }
        let range = request.value(forHTTPHeaderField: "Range")
        guard var data = body else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var status = 200
        var headers: [String: String] = [:]
        if let range, range.hasPrefix("bytes="), let start = Int(range.dropFirst(6).dropLast()), start < data.count {
            headers["Content-Range"] = "bytes \(start)-\(data.count - 1)/\(data.count)"
            data = data.subdata(in: start..<data.count)
            status = 206
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The host download from the signed GitHub releases, as on Windows and Linux (AnyPS5 Desktop's
/// test/core/retro_host/retro_host_store_test.dart), against a fake GitHub.
final class RetroHostStoreTests: XCTestCase {
    private var scratch: URL!
    private var store: RetroHostStore!
    private let api = URL(string: "https://api.github.example")!

    override func setUpWithError() throws {
        RetroHostFakeGitHub.reset()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-retro-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        store = RetroHostStore(root: scratch, keys: RetroHostReleaseFixture.keys, system: .macosArm64)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        RetroHostFakeGitHub.reset()
    }

    private func releases() async throws -> [RetroHostUpstreamRelease] {
        try await RetroHostStore.releases(session: URLSession(configuration: RetroHostFakeGitHub.configuration), api: api)
    }

    private func fetch(_ release: RetroHostUpstreamRelease?) async throws -> RetroHostDownload {
        try await store.fetch(release, configuration: RetroHostFakeGitHub.configuration)
    }

    private func failure(_ body: () async throws -> Any) async -> RetroHostDownloadError? {
        do {
            _ = try await body()
            return nil
        } catch {
            return error as? RetroHostDownloadError
        }
    }

    func testTheNewestSignedReleaseIsDownloadedCheckedAndPutInPlace() async throws {
        RetroHostFakeGitHub.list([
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "1.3.0"), tag: "v1.3.0", prerelease: true),
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "1.4.0"), tag: "v1.4.0", draft: true),
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(), tag: "v1.0.0"),
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "1.2.0"), tag: "v1.2.0"),
            RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(version: "0.9.0"), tag: "v0.9.0"),
        ])
        let listed = try await releases()
        XCTAssertEqual(listed.map(\.tag), ["v1.3.0", "v1.2.0", "v1.0.0", "v0.9.0"], "newest first, without drafts")
        let newest = try XCTUnwrap(RetroHostStore.newest(listed))
        XCTAssertEqual(newest.tag, "v1.2.0", "no pre-release")
        XCTAssertEqual(newest.named(ReleaseSigning.sumsName)?.sha256?.count, 64, "GitHub's digest is read")

        let download = try await fetch(newest)
        XCTAssertEqual(download.tag, "v1.2.0")
        let fetched = RetroHostFakeGitHub.requests.filter { $0.hasPrefix("https://github.example/") }.map { URL(string: $0)!.lastPathComponent }
        XCTAssertEqual(fetched, [ReleaseSigning.sumsName, ReleaseSigning.signatureName, "anyps5-retro-host-1.2.0-macos-arm64.files",
                                 "anyps5-retro-host-1.2.0-macos-arm64.zip"], "the signature first, then only this system's files")
        XCTAssertNil(store.installed(), "nothing is installed by the download alone")
        let version = try await store.putInPlace(download)
        XCTAssertEqual(version, RetroHostVersion(1, 2, 0))
        let installed = try XCTUnwrap(store.installed())
        XCTAssertTrue(installed.checked)
        XCTAssertEqual(store.version, RetroHostVersion(1, 2, 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.appendingPathComponent(".downloads").path), "the downloads are let go")
        let checked = try await store.check()
        checked.release()
    }

    func testAReleaseWithoutSignatureOrWithoutThisSystemIsNotAvailable() async throws {
        var unsigned = try RetroHostReleaseFixture.files()
        unsigned[ReleaseSigning.signatureName] = nil
        RetroHostFakeGitHub.list([RetroHostFakeGitHub.publish(unsigned, tag: "v1.0.0")])
        let listed = try await releases()
        XCTAssertNil(RetroHostStore.newest(listed), "no way to take a release unsigned")
        let none = await failure { try await self.fetch(nil) }
        XCTAssertEqual(none?.kind, .notAvailable)
        XCTAssertEqual(none?.message, "no signed emulator host has been published yet")

        let other = RetroHostStore(root: scratch, keys: RetroHostReleaseFixture.keys,
                                   system: RetroHostSystem(name: "freebsd-x64", executable: "h", core: "c", ps2Core: "p"))
        let signed = RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(), tag: "v1.0.0")
        RetroHostFakeGitHub.list([signed])
        let release = try XCTUnwrap(RetroHostStore.newest(try await releases()))
        let notHere = await failure { try await other.fetch(release, configuration: RetroHostFakeGitHub.configuration) }
        XCTAssertEqual(notHere?.kind, .notAvailable)
    }

    func testAnOlderReleasePublishedAgainUnderAHigherTagIsRefusedBeforeItsZip() async throws {
        RetroHostFakeGitHub.list([RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(), tag: "v2.0.0")])
        let release = try XCTUnwrap(RetroHostStore.newest(try await releases()))
        let refused = await failure { try await self.fetch(release) }
        XCTAssertEqual(refused?.kind, .signature)
        XCTAssertEqual(refused?.message, "v2.0.0: the release tagged v2.0.0 is signed as host 1.0.0")
        XCTAssertFalse(RetroHostFakeGitHub.requests.contains { $0.hasSuffix(".zip") }, "nothing but the signature was fetched")
    }

    func testAFileThatDoesNotMatchTheSignedSumsIsDeleted() async throws {
        var files = try RetroHostReleaseFixture.files()
        files["anyps5-retro-host-1.0.0-macos-arm64.zip"] = Data(repeating: 7, count: files["anyps5-retro-host-1.0.0-macos-arm64.zip"]!.count)
        var entry = RetroHostFakeGitHub.publish(files, tag: "v1.0.0")
        // GitHub's own digest would be of the changed file: the signed sums still catch it.
        entry["assets"] = (entry["assets"] as! [[String: Any]]).map { asset in asset.filter { $0.key != "digest" } }
        RetroHostFakeGitHub.list([entry])
        let release = try XCTUnwrap(RetroHostStore.newest(try await releases()))
        let refused = await failure { try await self.fetch(release) }
        XCTAssertEqual(refused?.kind, .signature)
        XCTAssertEqual(refused?.message, "anyps5-retro-host-1.0.0-macos-arm64.zip does not match the signed release")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: scratch.appendingPathComponent(".downloads/v1.0.0/anyps5-retro-host-1.0.0-macos-arm64.zip").path))
    }

    func testADownloadRedirectedFromHttpsToHttpIsRefused() async throws {
        let entry = RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(), tag: "v1.0.0")
        RetroHostFakeGitHub.list([entry])
        RetroHostFakeGitHub.redirects["https://github.example/v1.0.0/\(ReleaseSigning.sumsName)"] = "http://github.example/plain/SHA256SUMS"
        let release = try XCTUnwrap(RetroHostStore.newest(try await releases()))
        let refused = await failure { try await self.fetch(release) }
        XCTAssertEqual(refused?.kind, .network)
        XCTAssertEqual(refused?.message, "SHA256SUMS: the download was redirected from https to http")
        XCTAssertFalse(RetroHostFakeGitHub.requests.contains { $0.hasPrefix("http://") }, "nothing was fetched in the clear")
    }

    func testAStoppedDownloadSaysSo() async throws {
        RetroHostFakeGitHub.list([RetroHostFakeGitHub.publish(try RetroHostReleaseFixture.files(), tag: "v1.0.0")])
        let release = try XCTUnwrap(RetroHostStore.newest(try await releases()))
        let store = self.store!
        let task = Task { try await store.fetch(release, configuration: RetroHostFakeGitHub.configuration) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a stopped download finished")
        } catch let error as RetroHostDownloadError {
            XCTAssertEqual(error.kind, .cancelled)
        } catch is CancellationError {
            // Stopped before its first file.
        }
    }
}
