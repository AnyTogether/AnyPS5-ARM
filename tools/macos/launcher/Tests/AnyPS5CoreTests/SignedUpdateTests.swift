import CryptoKit
import Foundation
import Network
import XCTest
@testable import AnyPS5Core

/// Files over HTTP by path, for the signed self-update and engine downloads.
final class FileServer: @unchecked Sendable {
    let listener: NWListener
    let files: Locked<[String: Data]>
    let requests = Locked<[String]>([])

    init(files: [String: Data]) throws {
        self.files = Locked(files)
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [files = self.files, requests] connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                let line = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                requests.value.append(path)
                let body = files.value[path]
                var reply = Data((body == nil ? "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n" : "HTTP/1.1 200 OK\r\nContent-Length: \(body!.count)\r\n").utf8)
                reply.append(Data("Connection: close\r\n\r\n".utf8))
                reply.append(body ?? Data())
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: .global())
        _ = ready.wait(timeout: .now() + 5)
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)\(path)")! }
}

final class SignedUpdateTests: XCTestCase {
    let key = Curve25519.Signing.PrivateKey()
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    var trusted: [ReleaseSigning.Key] { [ReleaseSigning.Key(name: "test", raw: key.publicKey.rawRepresentation)!] }

    func sums(_ files: [String: Data]) -> Data {
        Data(files.keys.sorted().map { "\(FileDigest.hex(SHA256.hash(data: files[$0]!)))  \($0)\n" }.joined().utf8)
    }

    func signature(_ sums: Data, by signer: Curve25519.Signing.PrivateKey) throws -> Data {
        Data("ed25519 \(ReleaseSigning.keyID(of: signer.publicKey.rawRepresentation)) \(try signer.signature(for: sums).base64EncodedString())\n".utf8)
    }

    /// AnyPS5.app at `version`, zipped as the release has it.
    func appZip(version: String) throws -> Data {
        let app = folder.appendingPathComponent("build/AnyPS5.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "org.anyps5.test", "CFBundleShortVersionString": version]
        info.write(to: app.appendingPathComponent("Info.plist"), atomically: true)
        let zip = folder.appendingPathComponent("AnyPS5-macOS.zip")
        try Updates.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.deletingLastPathComponent().path, zip.path])
        return try Data(contentsOf: zip)
    }

    func release(_ server: FileServer, signed: Bool = true) -> Updates.Release {
        Updates.Release(tag: "v9.9.9-arm", version: "9.9.9", page: URL(string: "https://example.com/release")!, download: server.url("/AnyPS5-macOS.zip"), size: nil,
                        signature: signed ? ReleaseSigning.Assets(sums: server.url("/SHA256SUMS"), signature: server.url("/SHA256SUMS.sig")) : nil)
    }

    func failure(_ body: () async throws -> Any) async -> String? {
        do {
            _ = try await body()
            return nil
        } catch let error as LocalizedError {
            return error.errorDescription
        } catch {
            return "\(error)"
        }
    }

    func testASignedUpdateIsInstalled() async throws {
        let zip = try appZip(version: "9.9.9")
        let sums = sums(["AnyPS5-macOS.zip": zip, "install.sh": Data("#!/bin/sh\n".utf8)])
        let server = try FileServer(files: ["/AnyPS5-macOS.zip": zip, "/SHA256SUMS": sums, "/SHA256SUMS.sig": try signature(sums, by: key)])
        defer { server.listener.cancel() }
        let app = try await Updates.prepare(release(server), bundleIdentifier: "org.anyps5.test", current: "0.2.17", keys: trusted)
        XCTAssertEqual(app.lastPathComponent, "AnyPS5.app")
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent().deletingLastPathComponent())
    }

    func testATamperedUpdateIsRefusedBeforeItIsUnpacked() async throws {
        let zip = try appZip(version: "9.9.9")
        let sums = sums(["AnyPS5-macOS.zip": zip])
        var tampered = zip
        tampered.append(0)
        let server = try FileServer(files: ["/AnyPS5-macOS.zip": tampered, "/SHA256SUMS": sums, "/SHA256SUMS.sig": try signature(sums, by: key)])
        defer { server.listener.cancel() }
        let refused = await failure { try await Updates.prepare(self.release(server), bundleIdentifier: "org.anyps5.test", current: "0.2.17", keys: self.trusted) }
        XCTAssertEqual(refused, "the update was not installed: AnyPS5-macOS.zip does not match the signed release (sha256)")
    }

    func testAnUpdateSignedByAnotherKeyIsRefusedBeforeTheDownload() async throws {
        let zip = try appZip(version: "9.9.9")
        let sums = sums(["AnyPS5-macOS.zip": zip])
        let server = try FileServer(files: ["/AnyPS5-macOS.zip": zip, "/SHA256SUMS": sums, "/SHA256SUMS.sig": try signature(sums, by: Curve25519.Signing.PrivateKey())])
        defer { server.listener.cancel() }
        let refused = await failure { try await Updates.prepare(self.release(server), bundleIdentifier: "org.anyps5.test", current: "0.2.17", keys: self.trusted) }
        XCTAssertTrue(refused?.hasPrefix("the update was not installed: the release is signed with a key this launcher does not trust") == true, refused ?? "")
        XCTAssertFalse(server.requests.value.contains("/AnyPS5-macOS.zip"))
    }

    func testAnUnsignedUpdateIsNeverInstalled() async throws {
        let zip = try appZip(version: "9.9.9")
        let server = try FileServer(files: ["/AnyPS5-macOS.zip": zip])
        defer { server.listener.cancel() }
        let refused = await failure { try await Updates.prepare(self.release(server, signed: false), bundleIdentifier: "org.anyps5.test", current: "0.2.17", keys: self.trusted) }
        XCTAssertEqual(refused, "AnyPS5 9.9.9 is not signed, so it was not installed; get it from https://example.com/release only if you trust it")
        XCTAssertTrue(server.requests.value.isEmpty)
        // A signature file that is missing on the server is no signature either.
        let missing = await failure { try await Updates.prepare(self.release(server), bundleIdentifier: "org.anyps5.test", current: "0.2.17", keys: self.trusted) }
        XCTAssertEqual(missing, "the update was not installed: SHA256SUMS could not be downloaded")
    }

    func testTheReleaseListNamesTheSignatureFiles() throws {
        let json: [String: Any] = ["tag_name": "v0.2.17-arm", "html_url": "https://example.com/r", "assets": [
            ["name": "AnyPS5-macOS.zip", "browser_download_url": "https://example.com/a.zip"],
            ["name": "SHA256SUMS", "browser_download_url": "https://example.com/s"],
            ["name": "SHA256SUMS.sig", "browser_download_url": "https://example.com/g"],
            ["name": "AnyPS5-toolkit-macos-0.2.17-arm.zip", "browser_download_url": "https://example.com/t.zip", "digest": "sha256:" + String(repeating: "a", count: 64)],
        ]]
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(Updates.release(from: data)?.signature?.signature, URL(string: "https://example.com/g"))
        let entry = try XCTUnwrap(EngineCatalogue.entries(from: try JSONSerialization.data(withJSONObject: [json]))?.first)
        XCTAssertEqual(entry.trust, .signed)
        XCTAssertEqual(entry.assetName, "AnyPS5-toolkit-macos-0.2.17-arm.zip")
    }

    // MARK: Engines

    func entry(_ release: String, server: FileServer?, digest: String? = nil) -> EngineCatalogue.Entry {
        let page = URL(string: "https://example.com/r")!
        return EngineCatalogue.Entry(release: release, tag: "v" + release, title: release, summary: "", date: nil, page: page, download: page, size: nil, digest: digest,
                                     prerelease: false, signature: server.map { ReleaseSigning.Assets(sums: $0.url("/SHA256SUMS"), signature: $0.url("/SHA256SUMS.sig")) })
    }

    func testASignedEngineMustMatchItsSignedSums() async throws {
        let toolkit = Data("toolkit".utf8)
        let sums = sums(["AnyPS5-toolkit-macos-0.2.17-arm.zip": toolkit])
        let server = try FileServer(files: ["/SHA256SUMS": sums, "/SHA256SUMS.sig": try signature(sums, by: key)])
        defer { server.listener.cancel() }
        let digest = try await ToolkitStore.expectedDigest(of: entry("0.2.17-arm", server: server, digest: String(repeating: "b", count: 64)), allowUnsigned: false, keys: trusted, session: .shared)
        XCTAssertEqual(digest, FileDigest.hex(SHA256.hash(data: toolkit)))
        let other = await failure { try await ToolkitStore.expectedDigest(of: self.entry("0.2.18-arm", server: server), allowUnsigned: false, keys: self.trusted, session: .shared) }
        XCTAssertEqual(other, "engine 0.2.18-arm was refused: the signed release does not list AnyPS5-toolkit-macos-0.2.18-arm.zip")
        let stranger = [ReleaseSigning.Key(name: "other", raw: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)!]
        let wrongKey = await failure { try await ToolkitStore.expectedDigest(of: self.entry("0.2.17-arm", server: server), allowUnsigned: false, keys: stranger, session: .shared) }
        XCTAssertTrue(wrongKey?.contains("does not trust") == true, wrongKey ?? "")
    }

    func testUnsignedEnginesBeforeSigningNeedTheUsersOKAndLaterOnesAreRefused() async throws {
        let digest = String(repeating: "c", count: 64)
        let older = entry("0.2.15-arm", server: nil, digest: digest)
        XCTAssertEqual(older.trust, .unsignedOlder)
        let refused = await failure { try await ToolkitStore.expectedDigest(of: older, allowUnsigned: false, keys: self.trusted, session: .shared) }
        XCTAssertEqual(refused, "engine 0.2.15-arm is unsigned (an older release)")
        let allowed = try await ToolkitStore.expectedDigest(of: older, allowUnsigned: true, keys: trusted, session: .shared)
        XCTAssertEqual(allowed, digest)
        let noChecksum = await failure { try await ToolkitStore.expectedDigest(of: self.entry("0.2.15-arm", server: nil), allowUnsigned: true, keys: self.trusted, session: .shared) }
        XCTAssertEqual(noChecksum, "engine 0.2.15-arm has neither a signature nor a checksum from GitHub")
        let newer = entry("0.2.17-arm", server: nil, digest: digest)
        XCTAssertEqual(newer.trust, .unsignedRefused)
        let never = await failure { try await ToolkitStore.expectedDigest(of: newer, allowUnsigned: true, keys: self.trusted, session: .shared) }
        XCTAssertEqual(never, "engine 0.2.17-arm is not signed, though it came out after releases began to be signed: refused")
    }

    func testACatalogueCachedBeforeSigningStillReads() throws {
        let old = #"{"entries":[{"release":"0.2.15-arm","tag":"v0.2.15-arm","title":"t","summary":"","page":"https://e.com","download":"https://e.com/a.zip","prerelease":false}],"checked":"2026-10-24T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cached = try decoder.decode(ToolkitStore.CachedCatalogue.self, from: Data(old.utf8))
        XCTAssertNil(cached.entries[0].signature)
        XCTAssertEqual(cached.entries[0].trust, .unsignedOlder)
    }
}
