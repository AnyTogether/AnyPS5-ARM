import CryptoKit
import Foundation

/// What the launcher tells AnyTogether about playing: each session of a game, and the trophies
/// earned, with the game's name and its trophy set taught the first time. Everything waits in an
/// outbox on disk until the server has it, so playing offline loses nothing and nothing counts twice.
public final class TogetherSync: @unchecked Sendable {
    public struct TrophySetRecord: Codable, Equatable, Sendable {
        public struct Trophy: Codable, Equatable, Sendable {
            public var id: Int
            public var grade: String
            public var hidden: Bool
            public var name: String
            public var detail: String
            public var earnedAt: Date?

            public init(id: Int, grade: String, hidden: Bool, name: String, detail: String, earnedAt: Date?) {
                self.id = id
                self.grade = grade
                self.hidden = hidden
                self.name = name
                self.detail = detail
                self.earnedAt = earnedAt
            }
        }

        public var titleId: String
        public var gameName: String
        /// The language the texts are in ("en", "tr").
        public var language: String
        public var trophies: [Trophy]

        public init(titleId: String, gameName: String, language: String, trophies: [Trophy]) {
            self.titleId = titleId
            self.gameName = gameName
            self.language = language
            self.trophies = trophies
        }

        /// The set by what it is (its trophies and their grades), not by the language it is read in.
        public var setHash: String {
            let shape = trophies.sorted { $0.id < $1.id }.map { "\($0.id):\($0.grade):\($0.hidden)" }.joined(separator: ",")
            return SHA256.hash(data: Data(shape.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Session: Codable, Equatable {
        let id: String
        let titleId: String
        let startedAt: Date
        let endedAt: Date
        let exit: String
    }

    struct Outbox: Codable {
        var deviceId = UUID().uuidString.lowercased()
        var deviceRegistered = false
        var gameNames: [String: String] = [:]
        var taughtGames: Set<String> = []
        var sets: [String: TrophySetRecord] = [:]
        var uploadedSets: Set<String> = []
        var sentTrophies: Set<String> = []
        var sessions: [Session] = []
    }

    private let client: TogetherClient
    private let folder: URL
    private let deviceName: String
    private let model: String
    private let lock = NSLock()
    /// Whose outbox is loaded: the server and the account it was recorded for.
    private var owner: String?
    private var outbox = Outbox()
    private var flushing = false

    /// Each account on each server has its own outbox in `folder`: what one played is never sent
    /// as another's, nor to another server.
    public init(client: TogetherClient, folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Together"),
                deviceName: String, model: String) {
        self.client = client
        self.folder = folder
        self.deviceName = deviceName
        self.model = model
    }

    /// Nothing waits to be sent for the account signed in now.
    public var isEmpty: Bool {
        lock.withLock {
            guard current() != nil else { return true }
            return outbox.sessions.isEmpty && pendingTrophies(outbox).isEmpty && outbox.sets.keys.allSatisfy { outbox.uploadedSets.contains(setKey(outbox.sets[$0]!)) }
        }
    }

    public func recordSession(titleId: String, gameName: String, startedAt: Date, endedAt: Date, exit: String) {
        guard endedAt > startedAt.addingTimeInterval(5) else { return }
        change {
            $0.gameNames[titleId] = gameName
            $0.sessions.append(Session(id: UUID().uuidString.lowercased(), titleId: titleId, startedAt: startedAt, endedAt: endedAt, exit: exit))
        }
    }

    /// The game's trophy set as the launcher reads it now; the earned ones not sent yet go up.
    public func recordTrophies(_ set: TrophySetRecord) {
        change {
            $0.gameNames[set.titleId] = set.gameName
            $0.sets[set.titleId] = set
        }
    }

    /// Sends what waits, in the order the server needs it. Stops at the first failure; what was
    /// not sent stays for the next time.
    public func flush() async throws {
        guard lock.withLock({ () -> Bool in
            if flushing { return false }
            flushing = true
            return true
        }) else { return }
        defer { lock.withLock { flushing = false } }
        let iso = ISO8601DateFormatter()
        // Everything below is this account's, and stops if another signs in meanwhile.
        guard let owner = lock.withLock({ current() }) else { return }
        func snapshot() throws -> Outbox {
            try lock.withLock {
                guard current() == owner else { throw CancellationError() }
                return outbox
            }
        }
        func change(_ body: (inout Outbox) -> Void) { self.change(owner, body) }

        if try !snapshot().deviceRegistered {
            let id = try snapshot().deviceId
            do {
                _ = try await client.authorized("POST", "me/devices", ["id": id, "platform": "macos", "name": deviceName, "model": model])
            } catch let problem as TogetherProblem where problem.status == 409 {
                // Another account on this server has this ID: this outbox takes a new one.
                change { $0.deviceId = UUID().uuidString.lowercased() }
                throw problem
            }
            change { $0.deviceRegistered = true }
        }
        for (titleId, name) in try snapshot().gameNames {
            guard try !snapshot().taughtGames.contains(titleId) else { continue }
            _ = try await client.authorized("PUT", "games/\(titleId)", ["names": ["en": name]])
            change { _ = $0.taughtGames.insert(titleId) }
        }
        for set in try snapshot().sets.values {
            guard try !snapshot().uploadedSets.contains(setKey(set)) else { continue }
            let trophies: [[String: Any]] = set.trophies.map {
                ["id": $0.id, "grade": $0.grade, "hidden": $0.hidden, "texts": [set.language: ["name": $0.name, "detail": $0.detail]]]
            }
            _ = try await client.authorized("PUT", "trophy-sets/\(set.titleId)/\(set.setHash)", ["trophies": trophies])
            change { _ = $0.uploadedSets.insert(setKey(set)) }
        }

        let sessions = try Array(snapshot().sessions.prefix(200))
        if !sessions.isEmpty {
            let deviceId = try snapshot().deviceId
            let body: [String: Any] = ["sessions": sessions.map {
                ["id": $0.id, "titleId": $0.titleId, "deviceId": deviceId, "startedAt": iso.string(from: $0.startedAt), "endedAt": iso.string(from: $0.endedAt), "exit": $0.exit]
            }]
            let results = try await TogetherSync.results(try await client.authorized("POST", "me/sessions", body))
            if results.contains(where: { $0.code == "unknown_device" }) { change { $0.deviceRegistered = false } }
            // Stored and duplicate ones are done; rejected ones for a bad item are dropped too, as resending cannot fix them.
            let keep = Set(results.filter { $0.status == "rejected" && $0.code == "unknown_device" }.map(\.index))
            let done = Set(sessions.enumerated().filter { !keep.contains($0.offset) }.map(\.element.id))
            change { $0.sessions.removeAll { done.contains($0.id) } }
        }

        let earned = try Array(pendingTrophies(snapshot()).prefix(200))
        if !earned.isEmpty {
            let body: [String: Any] = ["trophies": earned.map { ["titleId": $0.titleId, "setHash": $0.setHash, "trophyId": $0.trophyId, "earnedAt": iso.string(from: $0.earnedAt)] }]
            let results = try await TogetherSync.results(try await client.authorized("POST", "me/trophies", body))
            var sent: Set<String> = []
            for result in results where result.status != "rejected" || result.code != "unknown_trophy" {
                if earned.indices.contains(result.index) { sent.insert(earned[result.index].key) }
            }
            if results.contains(where: { $0.code == "unknown_trophy" }) { change { $0.uploadedSets.removeAll() } }
            change { $0.sentTrophies.formUnion(sent) }
        }
    }

    // MARK: Inside

    private struct Earned {
        let titleId: String
        let setHash: String
        let trophyId: Int
        let earnedAt: Date
        var key: String { "\(titleId)/\(trophyId)" }
    }

    private struct Result: Decodable {
        let index: Int
        let status: String
        let code: String?
    }

    private static func results(_ data: Data) throws -> [Result] {
        struct Results: Decodable { let results: [Result] }
        return try JSONDecoder.together.decode(Results.self, from: data).results
    }

    private func pendingTrophies(_ outbox: Outbox) -> [Earned] {
        outbox.sets.values.flatMap { set in
            set.trophies.compactMap { trophy -> Earned? in
                guard let earnedAt = trophy.earnedAt, !outbox.sentTrophies.contains("\(set.titleId)/\(trophy.id)") else { return nil }
                return Earned(titleId: set.titleId, setHash: set.setHash, trophyId: trophy.id, earnedAt: earnedAt)
            }
        }
    }

    private func setKey(_ set: TrophySetRecord) -> String { "\(set.titleId)/\(set.setHash)" }

    /// The key of an account on a server.
    static func owner(base: URL, userId: String) -> String {
        SHA256.hash(data: Data("\(base.absoluteString)\n\(userId)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func file(_ owner: String) -> URL { folder.appendingPathComponent("outbox-\(owner).json") }

    /// The outbox kept in a single file before outboxes were kept by account.
    private var legacyFile: URL { folder.appendingPathComponent("outbox.json") }

    /// The owner signed in now, its outbox loaded; nil when no one is. Called with the lock held.
    private func current() -> String? {
        guard let user = client.user else { return nil }
        let key = TogetherSync.owner(base: client.base, userId: user.id)
        if key != owner {
            outbox = load(key)
            owner = key
        }
        return key
    }

    private func load(_ owner: String) -> Outbox {
        if let data = try? Data(contentsOf: file(owner)), let saved = try? JSONDecoder.together.decode(Outbox.self, from: data) { return saved }
        // The old single outbox goes to the first account that is signed in: the one it was
        // recorded for, as a server change signed out and an account was needed to record.
        guard let data = try? Data(contentsOf: legacyFile), let legacy = try? JSONDecoder.together.decode(Outbox.self, from: data) else { return Outbox() }
        save(legacy, to: owner)
        try? FileManager.default.removeItem(at: legacyFile)
        return legacy
    }

    private func save(_ outbox: Outbox, to owner: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.together.encode(outbox) { try? data.write(to: file(owner), options: .atomic) }
    }

    /// A change to the outbox of the account signed in now; dropped when no one is.
    private func change(_ body: (inout Outbox) -> Void) {
        lock.withLock {
            guard let owner = current() else { return }
            body(&outbox)
            save(outbox, to: owner)
        }
    }

    /// A change to one owner's outbox, loaded or not.
    private func change(_ owner: String, _ body: (inout Outbox) -> Void) {
        lock.withLock {
            if owner == self.owner {
                body(&outbox)
                save(outbox, to: owner)
            } else {
                var other = load(owner)
                body(&other)
                save(other, to: owner)
            }
        }
    }
}
