import Foundation

/// A game's saves and trophies kept in step through the user's AnyTogether cloud: the same zip
/// SaveBackup makes, as one save slot per game. Each Mac remembers the cloud version it last had
/// and a digest of the saves then. A side that alone changed since is taken; where both did, the
/// player chooses. Uploads go in parts and pick up where they stopped; downloads too.
public struct TogetherCloudSave: Sendable {
    public enum Outcome: Equatable, Sendable {
        case unchanged
        case uploaded(version: Int)
        /// The cloud's saves replaced this Mac's (kept in Backups first).
        case downloaded(version: Int, from: String?)
        /// The player chose to leave it for now.
        case skipped
    }

    /// Both this Mac and the cloud changed since they last agreed.
    public enum ConflictChoice: Sendable {
        case keepThisMac
        case takeCloud
        case notNow
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Asks the player, on the main thread or anywhere the caller likes.
    public struct Questions: Sendable {
        /// The cloud has `latest` from another device; this Mac has its own changes.
        public var conflict: @Sendable (_ latest: TogetherSaveVersion?) async -> ConflictChoice
        /// The quota has room only if the slot's newest version (`latest`) goes.
        public var replaceLatest: @Sendable (_ latest: TogetherSaveVersion?, _ problem: TogetherProblem) async -> Bool

        public init(conflict: @escaping @Sendable (TogetherSaveVersion?) async -> ConflictChoice,
                    replaceLatest: @escaping @Sendable (TogetherSaveVersion?, TogetherProblem) async -> Bool) {
            self.conflict = conflict
            self.replaceLatest = replaceLatest
        }
    }

    /// What this Mac last agreed with the cloud, and an upload under way.
    struct State: Codable, Equatable {
        struct Pending: Codable, Equatable {
            var uploadId: String
            var sha256: String
            var size: Int
            /// The saves' digest when the zip was made: a later change makes the zip stale.
            var digest: String
            var baseVersion: Int
            var replaceLatest: Bool
        }

        var version: Int?
        var digest: String?
        var pending: Pending?
    }

    /// The slot every game's saves go in: the whole of _sd, _sd_mem and _trophy.
    public static let slot = "AnyPS5 saves"

    public let client: TogetherClient
    public let game: URL
    public let titleID: String
    public let backups: URL
    /// Where this Mac keeps its record and the zips going up or down, per account.
    public let workspace: URL
    public let device: String
    public let launcherVersion: String?
    public let questions: Questions

    /// `game` is the game folder (_sd, _sd_mem, _trophy), `backups` where this Mac's saves go
    /// before a download replaces them, `workspace` a folder for this account's records.
    public init(client: TogetherClient, game: URL, titleID: String, backups: URL, workspace: URL, device: String, launcherVersion: String?, questions: Questions) {
        self.client = client
        self.game = game
        self.titleID = titleID
        self.backups = backups
        self.workspace = workspace
        self.device = device
        self.launcherVersion = launcherVersion
        self.questions = questions
    }

    /// This account's records: Application Support/AnyPS5/Together/CloudSaves/<user ID>.
    public static func workspace(for userID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AnyPS5/Together/CloudSaves/\(userID.replacingOccurrences(of: "/", with: "-"))")
    }

    var stateFile: URL { workspace.appendingPathComponent("\(titleID).json") }
    var outgoing: URL { workspace.appendingPathComponent("\(titleID).zip") }
    func incoming(_ version: Int) -> URL { workspace.appendingPathComponent("\(titleID)-v\(version).zip.part") }

    // MARK: Sync

    public func sync(date: Date = Date()) async throws -> Outcome {
        let local = SaveSync.digest(of: game)
        var state = loadState()
        let latest = try await latestVersion()
        switch (local, latest) {
        case (nil, nil):
            return .unchanged
        case (_?, nil):
            return try await upload(&state, base: 0, date: date)
        case (nil, let latest?):
            return try await download(latest, state: &state, date: date)
        case let (local?, latest?):
            let localChanged = local != state.digest
            let cloudChanged = latest.version != state.version
            switch (localChanged, cloudChanged) {
            case (false, false): return .unchanged
            case (true, false): return try await upload(&state, base: latest.version, date: date)
            case (false, true): return try await download(latest, state: &state, date: date)
            case (true, true):
                return try await choose(latest, state: &state, date: date)
            }
        }
    }

    /// Takes the cloud's newest saves now, whatever this Mac has (backed up first): after the
    /// player restored an older version, say.
    public func takeCloud(date: Date = Date()) async throws -> Outcome {
        var state = loadState()
        guard let latest = try await latestVersion() else { return .unchanged }
        return try await download(latest, state: &state, date: date)
    }

    private func latestVersion() async throws -> TogetherSaveVersion? {
        try await client.saveSlots(titleId: titleID).slots.first { $0.slot == Self.slot }?.latest
    }

    private func choose(_ latest: TogetherSaveVersion?, state: inout State, date: Date) async throws -> Outcome {
        switch await questions.conflict(latest) {
        case .keepThisMac: return try await upload(&state, base: latest?.version ?? 0, date: date)
        case .takeCloud:
            guard let latest else { return try await upload(&state, base: 0, date: date) }
            return try await download(latest, state: &state, date: date)
        case .notNow: return .skipped
        }
    }

    // MARK: Upload

    private func upload(_ state: inout State, base: Int, date: Date) async throws -> Outcome {
        guard let digest = SaveSync.digest(of: game) else { return .unchanged }
        var base = base
        var replace = false
        var upload: TogetherSaveUpload
        // An upload of these very saves that stopped part way goes on.
        if let pending = state.pending, pending.digest == digest, FileManager.default.fileExists(atPath: outgoing.path),
           let resumed = try? await client.saveUpload(pending.uploadId), resumed.sha256 == pending.sha256 {
            upload = resumed
            base = max(base, pending.baseVersion)
            replace = pending.replaceLatest
        } else {
            if let stale = state.pending {
                try? await client.cancelSaveUpload(stale.uploadId)
                state.pending = nil
                saveState(state)
            }
            try makeZip(date: date)
            let sha = try TogetherClient.sha256(of: outgoing)
            let size = (try FileManager.default.attributesOfItem(atPath: outgoing.path)[.size] as? Int) ?? 0
            while true {
                do {
                    upload = try await client.beginSaveUpload(titleId: titleID, slot: Self.slot, size: size, sha256: sha, device: device,
                                                              launcherVersion: launcherVersion, baseVersion: base, replaceLatest: replace)
                    break
                } catch let problem as TogetherProblem where problem.saveConflict {
                    switch await questions.conflict(problem.latest) {
                    case .keepThisMac: base = problem.latest?.version ?? 0
                    case .takeCloud:
                        guard let latest = problem.latest else { base = 0; continue }
                        return try await download(latest, state: &state, date: date)
                    case .notNow: return .skipped
                    }
                } catch let problem as TogetherProblem where problem.quotaExceeded && problem.canReplace == true && !replace {
                    guard await questions.replaceLatest(problem.latest, problem) else { throw problem }
                    replace = true
                }
            }
            state.pending = .init(uploadId: upload.uploadId, sha256: sha, size: size, digest: digest, baseVersion: base, replaceLatest: replace)
            saveState(state)
        }
        try await sendParts(of: upload, missing: nil)
        while true {
            do {
                let done = try await client.completeSaveUpload(upload.uploadId, baseVersion: base, replaceLatest: replace)
                state = State(version: done.version.version, digest: digest, pending: nil)
                saveState(state)
                try? FileManager.default.removeItem(at: outgoing)
                return done.unchanged == true ? .unchanged : .uploaded(version: done.version.version)
            } catch let problem as TogetherProblem where problem.code == "conflict" && problem.missing?.isEmpty == false {
                try await sendParts(of: upload, missing: problem.missing)
            } catch let problem as TogetherProblem where problem.saveConflict {
                switch await questions.conflict(problem.latest) {
                case .keepThisMac:
                    // Completing again over the newer one keeps this upload; nothing goes twice.
                    base = problem.latest?.version ?? 0
                    state.pending?.baseVersion = base
                    saveState(state)
                case .takeCloud:
                    try? await client.cancelSaveUpload(upload.uploadId)
                    state.pending = nil
                    saveState(state)
                    try? FileManager.default.removeItem(at: outgoing)
                    guard let latest = problem.latest else { return .skipped }
                    return try await download(latest, state: &state, date: date)
                case .notNow:
                    return .skipped
                }
            } catch let problem as TogetherProblem where problem.quotaExceeded && problem.canReplace == true && !replace {
                guard await questions.replaceLatest(problem.latest, problem) else { throw problem }
                replace = true
                state.pending?.replaceLatest = true
                saveState(state)
            } catch let problem as TogetherProblem where problem.code == "checksum_mismatch" || problem.status == 404 {
                // The server dropped the upload: it starts again next time.
                state.pending = nil
                saveState(state)
                throw problem
            }
        }
    }

    /// Sends the parts the server does not have (`missing`, or all it has not received).
    private func sendParts(of upload: TogetherSaveUpload, missing: [Int]?) async throws {
        let wanted = missing ?? Array(1 ... max(1, upload.parts)).filter { !upload.received.contains($0) }
        guard !wanted.isEmpty else { return }
        let handle = try FileHandle(forReadingFrom: outgoing)
        defer { try? handle.close() }
        for part in wanted {
            try handle.seek(toOffset: UInt64((part - 1) * upload.partSize))
            let data = try handle.read(upToCount: upload.partSize) ?? Data()
            var tries = 0
            while true {
                tries += 1
                do {
                    try await client.uploadSavePart(upload.uploadId, part: part, data: data)
                    break
                } catch let problem as TogetherProblem where problem.code == "checksum_mismatch" && tries < 3 {
                    continue
                } catch let error as URLError where tries < 3 && error.code != .cancelled {
                    try await Task.sleep(for: .milliseconds(300 * tries))
                }
            }
        }
    }

    private func makeZip(date: Date) throws {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-cloud-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        let made = try SaveBackup.backUp(game, to: stage, date: date)
        try? FileManager.default.removeItem(at: outgoing)
        try FileManager.default.moveItem(at: made, to: outgoing)
    }

    // MARK: Download

    private func download(_ version: TogetherSaveVersion, state: inout State, date: Date) async throws -> Outcome {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let file = incoming(version.version)
        try await client.downloadSaveVersion(version.id, to: file)
        guard try TogetherClient.sha256(of: file) == version.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: file)
            throw Failure(description: "the cloud save arrived damaged; it will be fetched again")
        }
        defer { try? FileManager.default.removeItem(at: file) }
        try SaveBackup.restore(file, into: game, keepingIn: backups, date: date)
        if let pending = state.pending { try? await client.cancelSaveUpload(pending.uploadId) }
        state = State(version: version.version, digest: SaveSync.digest(of: game), pending: nil)
        saveState(state)
        try? FileManager.default.removeItem(at: outgoing)
        return .downloaded(version: version.version, from: version.device)
    }

    // MARK: State

    func loadState() -> State {
        (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    func saveState(_ state: State) {
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateFile, options: .atomic) }
    }

    /// The cloud version this Mac last had, nil when it never synced the game.
    public var lastVersion: Int? { loadState().version }

    /// Forgets what this Mac had of the game (its cloud slot was deleted).
    public func forget() {
        try? FileManager.default.removeItem(at: stateFile)
        try? FileManager.default.removeItem(at: outgoing)
    }
}
