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
    private let file: URL
    private let deviceName: String
    private let model: String
    private let lock = NSLock()
    private var outbox: Outbox
    private var flushing = false

    public init(client: TogetherClient, file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Together/outbox.json"),
                deviceName: String, model: String) {
        self.client = client
        self.file = file
        self.deviceName = deviceName
        self.model = model
        outbox = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder.together.decode(Outbox.self, from: $0) } ?? Outbox()
    }

    /// Nothing waits to be sent.
    public var isEmpty: Bool {
        lock.withLock { outbox.sessions.isEmpty && pendingTrophies(outbox).isEmpty && outbox.sets.keys.allSatisfy { outbox.uploadedSets.contains(setKey(outbox.sets[$0]!)) } }
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

        if !snapshot.deviceRegistered {
            let id = snapshot.deviceId
            _ = try await client.authorized("POST", "me/devices", ["id": id, "platform": "macos", "name": deviceName, "model": model])
            change { $0.deviceRegistered = true }
        }
        for (titleId, name) in snapshot.gameNames where !snapshot.taughtGames.contains(titleId) {
            _ = try await client.authorized("PUT", "games/\(titleId)", ["names": ["en": name]])
            change { _ = $0.taughtGames.insert(titleId) }
        }
        for set in snapshot.sets.values where !snapshot.uploadedSets.contains(setKey(set)) {
            let trophies: [[String: Any]] = set.trophies.map {
                ["id": $0.id, "grade": $0.grade, "hidden": $0.hidden, "texts": [set.language: ["name": $0.name, "detail": $0.detail]]]
            }
            _ = try await client.authorized("PUT", "trophy-sets/\(set.titleId)/\(set.setHash)", ["trophies": trophies])
            change { _ = $0.uploadedSets.insert(setKey(set)) }
        }

        let sessions = Array(snapshot.sessions.prefix(200))
        if !sessions.isEmpty {
            let body: [String: Any] = ["sessions": sessions.map {
                ["id": $0.id, "titleId": $0.titleId, "deviceId": snapshot.deviceId, "startedAt": iso.string(from: $0.startedAt), "endedAt": iso.string(from: $0.endedAt), "exit": $0.exit]
            }]
            let results = try await TogetherSync.results(try await client.authorized("POST", "me/sessions", body))
            if results.contains(where: { $0.code == "unknown_device" }) { change { $0.deviceRegistered = false } }
            // Stored and duplicate ones are done; rejected ones for a bad item are dropped too, as resending cannot fix them.
            let keep = Set(results.filter { $0.status == "rejected" && $0.code == "unknown_device" }.map(\.index))
            let done = Set(sessions.enumerated().filter { !keep.contains($0.offset) }.map(\.element.id))
            change { $0.sessions.removeAll { done.contains($0.id) } }
        }

        let earned = Array(pendingTrophies(snapshot).prefix(200))
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

    private var snapshot: Outbox { lock.withLock { outbox } }

    private func change(_ body: (inout Outbox) -> Void) {
        lock.withLock {
            body(&outbox)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder.together.encode(outbox) { try? data.write(to: file, options: .atomic) }
        }
    }
}
