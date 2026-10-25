import CryptoKit
import Foundation
import XCTest
@testable import AnyPS5Core

/// A pretend AnyTogether cloud for saves: slots keeping three versions, uploads in parts, the
/// conflict hint, a quota and ranged downloads, as docs/cloud-storage.md describes them.
final class FakeCloud: @unchecked Sendable {
    struct Version {
        let id: String
        let number: Int
        let data: Data
        let device: String?
        let created: Date
        var sha: String { FakeCloud.sha(data) }
    }

    struct Slot {
        let id: String
        let titleId: String
        let slot: String
        var versions: [Version] = []
        var last = 0
    }

    struct Upload {
        let titleId: String
        let slot: String
        let size: Int
        let sha: String
        let parts: Int
        var received: [Int: Data] = [:]
        let base: Int?
        let replace: Bool
        let device: String?
    }

    var slots: [Slot] = []
    var uploads: [String: Upload] = [:]
    var quota = 100 * 1_048_576
    var partSize = 1024
    /// Parts asked for, in order, and parts to refuse once (a dropped connection).
    var partsSent: [Int] = []
    var dropOnce: Set<Int> = []
    /// Runs just before an upload completes (another Mac uploading meanwhile, say).
    var beforeComplete: (() -> Void)?
    var completeBodies: [[String: Any]] = []
    var beginBodies: [[String: Any]] = []
    var ranges: [String] = []
    var family: String?

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    var used: Int {
        Set(slots.flatMap(\.versions).map(\.sha)).reduce(0) { sum, sha in sum + (slots.flatMap(\.versions).first { $0.sha == sha }?.data.count ?? 0) }
    }

    func json(_ version: Version) -> [String: Any] {
        ["id": version.id, "version": version.number, "size": version.data.count, "sha256": version.sha, "device": version.device ?? NSNull(),
         "launcherVersion": NSNull(), "createdAt": Self.iso(version.created), "download": "https://anytogether.test/api/v1/files/save/\(version.id)/x.zip"]
    }

    func json(_ slot: Slot) -> [String: Any] {
        ["id": slot.id, "titleId": slot.titleId, "game": "Astro Bot", "slot": slot.slot, "updatedAt": Self.iso(Date()), "versions": slot.versions.map(json)]
    }

    var usage: [String: Any] { ["used": used, "limit": quota, "saves": used, "media": 0] }

    func problem(_ status: Int, _ code: String, _ extra: [String: Any] = [:]) -> (Int, Any) {
        (status, ["type": "x", "title": code, "status": status, "code": code].merging(extra) { a, _ in a })
    }

    /// Another device's upload, straight in.
    @discardableResult
    func put(_ data: Data, titleId: String = "PPSA01234", slot: String = TogetherCloudSave.slot, device: String = "Other Mac") -> Version {
        var index = slots.firstIndex { $0.titleId == titleId && $0.slot == slot }
        if index == nil {
            slots.append(Slot(id: UUID().uuidString.lowercased(), titleId: titleId, slot: slot))
            index = slots.count - 1
        }
        slots[index!].last += 1
        let version = Version(id: UUID().uuidString.lowercased(), number: slots[index!].last, data: data, device: device, created: Date())
        slots[index!].versions.insert(version, at: 0)
        slots[index!].versions = Array(slots[index!].versions.prefix(3))
        return version
    }

    /// Whether `size` new bytes fit when the slot drops what it may; nil fits, else whether
    /// dropping its newest too would.
    func room(_ size: Int, in slot: Slot?, sha: String) -> (fits: Bool, byReplacing: Bool) {
        let versions = slot?.versions ?? []
        var dropped = Array(versions.dropFirst(2))
        func fits(_ drop: [Version]) -> Bool {
            let keep = slots.flatMap(\.versions).filter { v in !drop.contains { $0.id == v.id } }
            let kept = Set(keep.map(\.sha))
            let usedAfter = kept.reduce(0) { sum, s in sum + (keep.first { $0.sha == s }?.data.count ?? 0) }
            return usedAfter + (kept.contains(sha) ? 0 : size) <= quota
        }
        if fits(dropped) { return (true, false) }
        if versions.count > 1 { dropped = Array(versions.dropFirst()) }
        if fits(dropped) { return (true, false) }
        return (false, versions.first.map { fits(dropped + [$0]) } ?? false)
    }

    func handle(_ request: URLRequest, _ body: Data?) -> (Int, Any) {
        let path = request.url!.path.replacingOccurrences(of: "/api/v1/", with: "")
        let parts = path.split(separator: "/").map(String.init)
        let input = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let family { return problem(403, "restricted_by_family", ["feature": family, "side": "self"]) }
        let method = request.httpMethod!
        /// The wildcards of `pattern` ("me/saves/uploads/*") when the request is one.
        func route(_ verb: String, _ pattern: String) -> [String]? {
            let want = pattern.split(separator: "/").map(String.init)
            guard verb == method, want.count == parts.count else { return nil }
            var found: [String] = []
            for (a, b) in zip(want, parts) {
                if a == "*" { found.append(b) } else if a != b { return nil }
            }
            return found
        }
        if route("GET", "me/saves") != nil {
            let title = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "titleId" }?.value
            return (200, ["usage": usage, "slots": slots.filter { title == nil || $0.titleId == title }.map(json)])
        } else if route("POST", "me/saves/uploads") != nil {
            beginBodies.append(input)
            let titleId = input["titleId"] as! String, slotName = input["slot"] as! String
            let slot = slots.first { $0.titleId == titleId && $0.slot == slotName }
            if let base = input["baseVersion"] as? Int, (slot?.versions.first?.number ?? 0) != base {
                return problem(409, "save_conflict", ["latest": slot?.versions.first.map(json) ?? NSNull()])
            }
            let size = input["size"] as! Int, sha = input["sha256"] as! String
            let replace = input["replaceLatest"] as? Bool ?? false
            let room = room(size, in: slot, sha: sha)
            if !room.fits && !(room.byReplacing && replace) {
                return problem(413, "quota_exceeded", ["used": used, "limit": quota, "needed": size, "canReplace": room.byReplacing,
                                                       "latest": room.byReplacing ? slot?.versions.first.map(json) ?? NSNull() : NSNull()])
            }
            let id = UUID().uuidString.lowercased()
            let count = (size + partSize - 1) / partSize
            uploads[id] = Upload(titleId: titleId, slot: slotName, size: size, sha: sha, parts: count, base: input["baseVersion"] as? Int, replace: replace, device: input["device"] as? String)
            return (201, ["uploadId": id, "size": size, "sha256": sha, "partSize": partSize, "parts": count, "received": [Int](), "expiresAt": Self.iso(Date().addingTimeInterval(86400))])
        } else if let id = route("GET", "me/saves/uploads/*")?.first {
            guard let upload = uploads[id] else { return problem(404, "not_found") }
            return (200, ["uploadId": id, "size": upload.size, "sha256": upload.sha, "partSize": partSize, "parts": upload.parts, "received": upload.received.keys.sorted(), "expiresAt": Self.iso(Date())])
        } else if let found = route("PUT", "me/saves/uploads/*/parts/*") {
            let id = found[0], number = found[1]
            guard var upload = uploads[id], let n = Int(number) else { return problem(404, "not_found") }
            partsSent.append(n)
            if dropOnce.remove(n) != nil { return problem(500, "internal") }
            let data = body ?? Data()
            if let declared = request.value(forHTTPHeaderField: "X-Part-SHA256"), declared != Self.sha(data) { return problem(400, "checksum_mismatch") }
            upload.received[n] = data
            uploads[id] = upload
            return (200, ["part": n, "sha256": Self.sha(data), "received": upload.received.keys.sorted()])
        } else if let id = route("DELETE", "me/saves/uploads/*")?.first {
            uploads[id] = nil
            return (204, [:])
        } else if let id = route("POST", "me/saves/uploads/*/complete")?.first {
            completeBodies.append(input)
            beforeComplete?()
            beforeComplete = nil
            guard let upload = uploads[id] else { return problem(404, "not_found") }
            let missing = (1 ... upload.parts).filter { upload.received[$0] == nil }
            if !missing.isEmpty { return problem(409, "conflict", ["missing": missing]) }
            let data = (1 ... upload.parts).reduce(into: Data()) { $0.append(upload.received[$1]!) }
            guard Self.sha(data) == upload.sha else {
                uploads[id] = nil
                return problem(400, "checksum_mismatch")
            }
            let slot = slots.first { $0.titleId == upload.titleId && $0.slot == upload.slot }
            let base = input["baseVersion"] as? Int ?? upload.base
            if let base, (slot?.versions.first?.number ?? 0) != base {
                return problem(409, "save_conflict", ["latest": slot?.versions.first.map(json) ?? NSNull()])
            }
            let replace = input["replaceLatest"] as? Bool ?? upload.replace
            let room = room(data.count, in: slot, sha: upload.sha)
            if !room.fits && !(room.byReplacing && replace) {
                return problem(413, "quota_exceeded", ["used": used, "limit": quota, "needed": data.count, "canReplace": room.byReplacing,
                                                       "latest": room.byReplacing ? slot?.versions.first.map(json) ?? NSNull() : NSNull()])
            }
            if let latest = slot?.versions.first, latest.sha == upload.sha {
                uploads[id] = nil
                return (200, ["save": json(slot!), "version": json(latest), "dropped": [Any](), "unchanged": true, "usage": usage])
            }
            if !room.fits, let index = slots.firstIndex(where: { $0.id == slot?.id }) { slots[index].versions = [] }
            let version = put(data, titleId: upload.titleId, slot: upload.slot, device: upload.device ?? "?")
            uploads[id] = nil
            return (201, ["save": json(slots.first { $0.titleId == upload.titleId }!), "version": json(version), "dropped": [Any](), "unchanged": false, "usage": usage])
        } else if let id = route("GET", "me/saves/versions/*/download")?.first {
            guard let version = slots.flatMap(\.versions).first(where: { $0.id == id }) else { return problem(404, "not_found") }
            if let range = request.value(forHTTPHeaderField: "Range") {
                ranges.append(range)
                let start = Int(range.dropFirst("bytes=".count).dropLast()) ?? 0
                return (206, FakeTogether.Raw(data: version.data.subdata(in: start ..< version.data.count), headers: ["Content-Range": "bytes \(start)-\(version.data.count - 1)/\(version.data.count)"]))
            }
            return (200, FakeTogether.Raw(data: version.data, headers: ["Content-Type": "application/zip"]))
        } else if let id = route("POST", "me/saves/versions/*/restore")?.first {
            guard let index = slots.firstIndex(where: { $0.versions.contains { $0.id == id } }) else { return problem(404, "not_found") }
            let old = slots[index].versions.first { $0.id == id }!
            let made = put(old.data, titleId: slots[index].titleId, slot: slots[index].slot, device: old.device ?? "?")
            return (200, ["save": json(slots[index]), "version": json(made), "dropped": [Any](), "usage": usage])
        } else if let id = route("DELETE", "me/saves/versions/*")?.first {
            for index in slots.indices { slots[index].versions.removeAll { $0.id == id } }
            slots.removeAll { $0.versions.isEmpty }
            return (200, ["usage": usage])
        } else if let id = route("DELETE", "me/saves/slots/*")?.first {
            slots.removeAll { $0.id == id }
            return (200, ["usage": usage])
        }
        return problem(404, "not_found")
    }
}

final class TogetherCloudSaveTests: XCTestCase {
    var root: URL!
    var client: TogetherClient!
    var cloud: FakeCloud!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cloudsave-\(UUID().uuidString.prefix(8))")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeTogether.self]
        FakeTogether.requests = []
        FakeTogether.delay = 0
        let store = TokenStore(file: root.appendingPathComponent("session.json"))
        store.save(.init(accessToken: "access", accessExpiry: Date().addingTimeInterval(3600), refreshToken: "refresh",
                         user: TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)))
        client = TogetherClient(base: URL(string: "https://anytogether.test")!, store: store, session: URLSession(configuration: configuration), clientName: "launcher-macos/test")
        cloud = FakeCloud()
        let cloud = cloud!
        FakeTogether.handler = { request, body in cloud.handle(request, body) }
    }

    override func tearDown() {
        FakeTogether.handler = nil
        try? FileManager.default.removeItem(at: root)
    }

    func game(_ mac: String) -> URL { root.appendingPathComponent("\(mac)/game") }

    func save(_ text: String, on mac: String, bytes: Int = 0) throws {
        let file = game(mac).appendingPathComponent("_sd/savedata0/save.dat")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Random bytes do not compress: the zip spans several 1 KiB parts.
        var data = Data((text + "\n").utf8)
        data.append(Data((0 ..< bytes).map { _ in UInt8.random(in: 0 ... 255) }))
        try data.write(to: file)
    }

    func read(on mac: String) -> String? {
        guard let data = try? Data(contentsOf: game(mac).appendingPathComponent("_sd/savedata0/save.dat")) else { return nil }
        return String(decoding: data.prefix { $0 != 0x0A }, as: UTF8.self)
    }

    final class Asked: @unchecked Sendable {
        var conflicts: [TogetherSaveVersion?] = []
        var replaces = 0
    }

    func sync(_ mac: String, choose: TogetherCloudSave.ConflictChoice = .notNow, replace: Bool = false, asked: Asked = Asked()) async throws -> TogetherCloudSave.Outcome {
        try await engine(mac, choose: choose, replace: replace, asked: asked).sync()
    }

    func engine(_ mac: String, choose: TogetherCloudSave.ConflictChoice = .notNow, replace: Bool = false, asked: Asked = Asked()) -> TogetherCloudSave {
        let questions = TogetherCloudSave.Questions(conflict: { latest in
            asked.conflicts.append(latest)
            return choose
        }, replaceLatest: { _, _ in
            asked.replaces += 1
            return replace
        })
        return TogetherCloudSave(client: client, game: game(mac), titleID: "PPSA01234", backups: root.appendingPathComponent("\(mac)/Backups"),
                                 workspace: root.appendingPathComponent("\(mac)/Cloud"), device: mac, launcherVersion: "0.2.14", questions: questions)
    }

    func testTheFirstMacUploadsInPartsAndThenHasNothingToDo() async throws {
        try save("level 1", on: "A", bytes: 3000)
        let outcome = try await sync("A")
        XCTAssertEqual(outcome, .uploaded(version: 1))
        XCTAssertGreaterThanOrEqual(Set(cloud.partsSent).count, 3, "a 3 KB zip goes in 1 KiB parts")
        XCTAssertEqual(cloud.slots.first?.versions.first?.device, "A")
        XCTAssertEqual(cloud.beginBodies.first?["baseVersion"] as? Int, 0, "a first upload says it had nothing")
        XCTAssertEqual(cloud.beginBodies.first?["slot"] as? String, TogetherCloudSave.slot)
        let parts = FakeTogether.requests.filter { $0.0.url!.path.contains("/parts/") }
        XCTAssertTrue(parts.allSatisfy { $0.0.value(forHTTPHeaderField: "X-Part-SHA256")?.count == 64 }, "each part says its SHA-256")
        let again = try await sync("A")
        XCTAssertEqual(again, .unchanged)
    }

    func testAnotherMacTakesTheSavesAndPlaysOn() async throws {
        try save("level 1", on: "A", bytes: 2000)
        _ = try await sync("A")
        let taken = try await sync("B")
        XCTAssertEqual(taken, .downloaded(version: 1, from: "A"))
        XCTAssertEqual(read(on: "B"), "level 1")
        try save("level 2", on: "B")
        let uploaded = try await sync("B")
        XCTAssertEqual(uploaded, .uploaded(version: 2))
        XCTAssertEqual(cloud.beginBodies.last?["baseVersion"] as? Int, 1)
        let back = try await sync("A")
        XCTAssertEqual(back, .downloaded(version: 2, from: "B"))
        XCTAssertEqual(read(on: "A"), "level 2")
        XCTAssertFalse(SaveBackup.backups(in: root.appendingPathComponent("A/Backups")).isEmpty, "A's saves are backed up before the download")
    }

    /// A connection that drops part way: the next sync sends only what did not arrive.
    func testAnUploadThatStoppedPicksUpWhereItWas() async throws {
        try save("level 1", on: "A", bytes: 4000)
        cloud.dropOnce = [3]
        do {
            _ = try await sync("A")
            XCTFail("the dropped part did not fail the sync")
        } catch {}
        XCTAssertEqual(cloud.uploads.count, 1, "the upload stays open")
        let before = cloud.partsSent
        let outcome = try await sync("A")
        XCTAssertEqual(outcome, .uploaded(version: 1))
        let resent = cloud.partsSent.dropFirst(before.count)
        XCTAssertFalse(resent.contains(1), "part 1 went again")
        XCTAssertTrue(resent.contains(3))
        XCTAssertEqual(cloud.beginBodies.count, 1, "a new upload was begun instead of going on")
    }

    func testPlayedOnBothMacsAsksAndKeepsThisMacs() async throws {
        try save("level 1", on: "A")
        _ = try await sync("A")
        _ = try await sync("B")
        try save("B's level 2", on: "B")
        _ = try await sync("B")
        try save("A's level 3", on: "A")
        let asked = Asked()
        let outcome = try await sync("A", choose: .keepThisMac, asked: asked)
        XCTAssertEqual(asked.conflicts.count, 1)
        XCTAssertEqual(asked.conflicts.first??.device, "B", "the question names the other Mac")
        XCTAssertEqual(outcome, .uploaded(version: 3))
        XCTAssertEqual(cloud.beginBodies.last?["baseVersion"] as? Int, 2)
    }

    func testPlayedOnBothMacsCanTakeTheNewerOne() async throws {
        try save("level 1", on: "A")
        _ = try await sync("A")
        _ = try await sync("B")
        try save("B's level 2", on: "B")
        _ = try await sync("B")
        try save("A's level 3", on: "A")
        let outcome = try await sync("A", choose: .takeCloud)
        XCTAssertEqual(outcome, .downloaded(version: 2, from: "B"))
        XCTAssertEqual(read(on: "A"), "B's level 2")
    }

    func testNotNowLeavesBothAsTheyAre() async throws {
        try save("level 1", on: "A")
        _ = try await sync("A")
        cloud.put(Data("other".utf8))
        try save("A's level 2", on: "A")
        let outcome = try await sync("A", choose: .notNow)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(read(on: "A"), "A's level 2")
        XCTAssertEqual(cloud.slots.first?.versions.count, 2)
    }

    /// Another Mac uploads while this one sends: complete answers 409 save_conflict; keeping this
    /// Mac's completes the same upload again over it, nothing sent twice.
    func testAConflictAtCompleteKeepsTheUploadWithoutSendingItAgain() async throws {
        try save("level 1", on: "A")
        _ = try await sync("A")
        try save("level 2", on: "A", bytes: 2000)
        let cloud = cloud!
        cloud.beforeComplete = { cloud.put(Data("from B".utf8), device: "B") }
        let asked = Asked()
        let partsBefore = cloud.partsSent.count
        let outcome = try await sync("A", choose: .keepThisMac, asked: asked)
        XCTAssertEqual(asked.conflicts.count, 1)
        XCTAssertEqual(outcome, .uploaded(version: 3))
        XCTAssertEqual(cloud.completeBodies.last?["baseVersion"] as? Int, 2)
        let sent = cloud.partsSent.dropFirst(partsBefore)
        XCTAssertEqual(sent.count, Set(sent).count, "a part went twice")
    }

    func testAFullCloudAsksBeforeReplacingTheNewest() async throws {
        try save("level 1", on: "A", bytes: 3000)
        _ = try await sync("A")
        cloud.quota = (cloud.slots.first?.versions.first?.data.count ?? 0) + 500
        try save("level 2", on: "A", bytes: 3000)
        let asked = Asked()
        do {
            _ = try await sync("A", replace: false, asked: asked)
            XCTFail("a full cloud took the upload")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.code, "quota_exceeded")
            XCTAssertEqual(problem.canReplace, true)
            XCTAssertNotNil(problem.limit)
        }
        XCTAssertEqual(asked.replaces, 1)
        let outcome = try await sync("A", replace: true)
        XCTAssertEqual(outcome, .uploaded(version: 2))
        XCTAssertEqual(cloud.beginBodies.last?["replaceLatest"] as? Bool, true)
        XCTAssertEqual(cloud.slots.first?.versions.count, 1)
    }

    func testAFullCloudWithNothingToReplaceSaysSo() async throws {
        cloud.quota = 100
        try save("level 1", on: "A", bytes: 3000)
        let asked = Asked()
        do {
            _ = try await sync("A", asked: asked)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertTrue(problem.quotaExceeded)
            XCTAssertEqual(problem.canReplace, false)
        }
        XCTAssertEqual(asked.replaces, 0, "nothing to replace: nothing to ask")
    }

    func testABrokenDownloadGoesOnFromWhereItStopped() async throws {
        let version = cloud.put(Data((0 ..< 5000).map { _ in UInt8.random(in: 0 ... 255) }))
        let file = root.appendingPathComponent("part.zip")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try version.data.prefix(1200).write(to: file)
        try await client.downloadSaveVersion(version.id, to: file)
        XCTAssertEqual(cloud.ranges, ["bytes=1200-"])
        XCTAssertEqual(try Data(contentsOf: file), version.data)
    }

    func testAnOlderVersionRestoredComesDown() async throws {
        try save("level 1", on: "A")
        _ = try await sync("A")
        try save("level 2", on: "A")
        _ = try await sync("A")
        let first = try XCTUnwrap(cloud.slots.first?.versions.last)
        XCTAssertEqual(first.number, 1)
        let restored = try await client.restoreSaveVersion(first.id)
        XCTAssertEqual(restored.version, 3)
        let outcome = try await sync("A")
        XCTAssertEqual(outcome, .downloaded(version: 3, from: "A"))
        XCTAssertEqual(read(on: "A"), "level 1")
    }

    func testAFamilyRefusalComesBackAsSuch() async throws {
        try save("level 1", on: "A")
        cloud.family = "media_sharing"
        do {
            _ = try await sync("A")
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.familyFeature, .mediaSharing)
        }
    }

    func testDeletingASlotAndAVersion() async throws {
        let one = cloud.put(Data("one".utf8))
        cloud.put(Data("two".utf8))
        let usage = try await client.deleteSaveVersion(one.id)
        XCTAssertEqual(cloud.slots.first?.versions.count, 1)
        XCTAssertEqual(usage?.limit, cloud.quota)
        try await client.deleteSaveSlot(cloud.slots[0].id)
        XCTAssertTrue(cloud.slots.isEmpty)
    }
}
