import CryptoKit
import Foundation

/// Cloud saves and media on AnyTogether: one quota per account for both, kept by the server's
/// file store. Off until the server has one: `GET /storage` says so, and every feature hides.

/// What a server keeps, for anyone to ask before signing in.
public struct TogetherStorageInfo: Decodable, Equatable, Sendable {
    public struct MediaLimits: Decodable, Equatable, Sendable {
        public var image = 10 * 1_048_576
        public var clip = 25 * 1_048_576
        public var voice = 1_048_576
        public var poster = 2 * 1_048_576
        public var voiceMs = 60_000
        public var pixels = 40_000_000

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            image = try c.flexibleInt(.image) ?? image
            clip = try c.flexibleInt(.clip) ?? clip
            voice = try c.flexibleInt(.voice) ?? voice
            poster = try c.flexibleInt(.poster) ?? poster
            voiceMs = try c.flexibleInt(.voiceMs) ?? voiceMs
            pixels = try c.flexibleInt(.pixels) ?? pixels
        }

        enum CodingKeys: String, CodingKey { case image, clip, voice, poster, voiceMs, pixels }
    }

    public var enabled: Bool
    public var quota = 100 * 1_048_576
    public var saveMax = 50 * 1_048_576
    public var saveVersions = 3
    public var partSize = 4 * 1_048_576
    public var media = MediaLimits()
    public var galleryMax = 12

    public static let disabled = TogetherStorageInfo(enabled: false)

    public init(enabled: Bool) { self.enabled = enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        quota = try c.flexibleInt(.quota) ?? quota
        saveMax = try c.flexibleInt(.saveMax) ?? saveMax
        saveVersions = try c.flexibleInt(.saveVersions) ?? saveVersions
        partSize = try c.flexibleInt(.partSize) ?? partSize
        media = try c.decodeIfPresent(MediaLimits.self, forKey: .media) ?? media
        galleryMax = try c.flexibleInt(.galleryMax) ?? galleryMax
    }

    enum CodingKeys: String, CodingKey { case enabled, quota, saveMax, saveVersions, partSize, media, galleryMax }
}

/// Bytes used, in all and by what; `limit` is the account's quota.
public struct TogetherStorageUsage: Decodable, Equatable, Sendable {
    public let used: Int
    public let limit: Int
    public let saves: Int
    public let media: Int

    public init(used: Int, limit: Int, saves: Int, media: Int) {
        self.used = used
        self.limit = limit
        self.saves = saves
        self.media = media
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        used = try c.flexibleInt(.used) ?? 0
        limit = try c.flexibleInt(.limit) ?? 0
        saves = try c.flexibleInt(.saves) ?? 0
        media = try c.flexibleInt(.media) ?? 0
    }

    enum CodingKeys: String, CodingKey { case used, limit, saves, media }

    /// 0-1 of the quota.
    public var fraction: Double { limit > 0 ? min(1, Double(used) / Double(limit)) : 0 }
    public var free: Int { max(0, limit - used) }
}

/// One kept archive of a save slot.
public struct TogetherSaveVersion: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let version: Int
    public let size: Int
    public let sha256: String
    /// The Mac (or device) that uploaded it.
    public let device: String?
    public let launcherVersion: String?
    public let createdAt: Date
    /// A signed link to the archive that needs no token, good for an hour or two.
    public let download: String?

    public init(id: String, version: Int, size: Int, sha256: String, device: String?, launcherVersion: String? = nil, createdAt: Date, download: String? = nil) {
        self.id = id
        self.version = version
        self.size = size
        self.sha256 = sha256
        self.device = device
        self.launcherVersion = launcherVersion
        self.createdAt = createdAt
        self.download = download
    }
}

/// A game's save slot in the cloud, its versions newest first (at most three).
public struct TogetherSaveSlot: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let titleId: String
    /// The game's name when the server's catalogue knows it.
    public let game: String?
    public let slot: String
    public let updatedAt: Date
    public let versions: [TogetherSaveVersion]

    public init(id: String, titleId: String, game: String?, slot: String, updatedAt: Date, versions: [TogetherSaveVersion]) {
        self.id = id
        self.titleId = titleId
        self.game = game
        self.slot = slot
        self.updatedAt = updatedAt
        self.versions = versions
    }

    public var latest: TogetherSaveVersion? { versions.first }
    /// Bytes its versions take (the same bytes twice are counted once by the server).
    public var size: Int { Dictionary(versions.map { ($0.sha256, $0.size) }, uniquingKeysWith: { a, _ in a }).values.reduce(0, +) }
}

/// A photo, clip or voice note on AnyTogether. Links are signed and expire: read the list or the
/// message again for new ones.
public struct TogetherMedia: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    /// "image", "clip" or "voice".
    public let kind: String
    public let contentType: String?
    public let size: Int
    public let width: Int?
    public let height: Int?
    public let durationMs: Int?
    public let url: String?
    public let thumb: String?
    public let poster: String?
    /// Hidden by a moderator: only its owner still sees it.
    public let hidden: Bool?
    /// Its place in the owner's gallery, when pinned.
    public let gallery: Int?
    public let createdAt: Date?

    public init(id: String, kind: String, contentType: String? = nil, size: Int = 0, width: Int? = nil, height: Int? = nil, durationMs: Int? = nil,
                url: String?, thumb: String? = nil, poster: String? = nil, hidden: Bool? = nil, gallery: Int? = nil, createdAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.contentType = contentType
        self.size = size
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.url = url
        self.thumb = thumb
        self.poster = poster
        self.hidden = hidden
        self.gallery = gallery
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        size = try c.flexibleInt(.size) ?? 0
        width = try c.flexibleInt(.width)
        height = try c.flexibleInt(.height)
        durationMs = try c.flexibleInt(.durationMs)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        gallery = try c.flexibleInt(.gallery)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey { case id, kind, contentType, size, width, height, durationMs, url, thumb, poster, hidden, gallery, createdAt }

    /// The still to show: a photo's thumbnail, a clip's poster.
    public var still: String? { kind == "clip" ? poster : (thumb ?? url) }
    public var aspect: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

/// Media in a message as this member may see it: the media, or why it is not there.
public struct TogetherAttachment: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    /// Deleted by its owner or hidden by a moderator.
    public let removed: Bool
    /// One of the two blocked the other.
    public let blocked: Bool
    public let media: TogetherMedia?

    public init(media: TogetherMedia) {
        id = media.id
        kind = media.kind
        removed = false
        blocked = false
        self.media = media
    }

    public init(id: String, kind: String, removed: Bool = false, blocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.removed = removed
        self.blocked = blocked
        media = nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "image"
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        media = removed || blocked ? nil : try? TogetherMedia(from: decoder)
    }

    enum CodingKeys: String, CodingKey { case id, kind, removed, blocked }
}

/// Settings → Storage: the usage, every save and the newest media.
public struct TogetherStorageOverview: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let usage: TogetherStorageUsage?
    public let limits: TogetherStorageInfo?
    public let saves: [TogetherSaveSlot]
    public let media: [TogetherMedia]
    /// The last media ID when more are left (GET /me/media?before=…).
    public let next: String?

    public init(enabled: Bool, usage: TogetherStorageUsage?, limits: TogetherStorageInfo? = nil, saves: [TogetherSaveSlot] = [], media: [TogetherMedia] = [], next: String? = nil) {
        self.enabled = enabled
        self.usage = usage
        self.limits = limits
        self.saves = saves
        self.media = media
        self.next = next
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        usage = try c.decodeIfPresent(TogetherStorageUsage.self, forKey: .usage)
        limits = try c.decodeIfPresent(TogetherStorageInfo.self, forKey: .limits)
        saves = try c.decodeIfPresent([TogetherSaveSlot].self, forKey: .saves) ?? []
        media = try c.decodeIfPresent([TogetherMedia].self, forKey: .media) ?? []
        next = try c.decodeIfPresent(String.self, forKey: .next)
    }

    enum CodingKeys: String, CodingKey { case enabled, usage, limits, saves, media, next }
}

/// A save upload under way: which parts the server has.
public struct TogetherSaveUpload: Decodable, Equatable, Sendable {
    public let uploadId: String
    public let size: Int
    public let sha256: String
    public let partSize: Int
    public let parts: Int
    public let received: [Int]
}

/// A save version dropped to keep three per slot or to make room in the quota.
public struct TogetherDroppedVersion: Decodable, Equatable, Sendable {
    public let id: String
    public let version: Int
    public let size: Int
    /// "kept", "quota" or "replaced".
    public let reason: String
}

/// A finished upload: the slot now, the version kept, what went to make room.
public struct TogetherSaveCompleted: Decodable, Equatable, Sendable {
    public let save: TogetherSaveSlot?
    public let version: TogetherSaveVersion
    public let dropped: [TogetherDroppedVersion]?
    /// The same bytes as the newest version: nothing was stored.
    public let unchanged: Bool?
    public let usage: TogetherStorageUsage?
}

extension KeyedDecodingContainer {
    /// A count the server may send as a number or (a big integer) as text.
    func flexibleInt(_ key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }
}

extension TogetherProblem {
    /// A 413 quota_exceeded: the cloud is full.
    public var quotaExceeded: Bool { code == "quota_exceeded" }
    /// A 409 save_conflict: the cloud has a newer save than this Mac's base (in `latest`).
    public var saveConflict: Bool { code == "save_conflict" }
    /// The server keeps no files.
    public var storageDisabled: Bool { code == "storage_disabled" }
}

extension TogetherClient {
    // MARK: Is it on?

    /// Whether this server keeps files, and its limits; needs no sign-in.
    public func storageInfo() async throws -> TogetherStorageInfo {
        try JSONDecoder.together.decode(TogetherStorageInfo.self, from: try await send("GET", "storage", nil))
    }

    /// The usage, every save slot and the newest media.
    public func storage() async throws -> TogetherStorageOverview {
        try JSONDecoder.together.decode(TogetherStorageOverview.self, from: try await authorized("GET", "me/storage", nil))
    }

    // MARK: Saves

    /// The save slots (of one game), with their versions newest first.
    public func saveSlots(titleId: String? = nil) async throws -> (usage: TogetherStorageUsage?, slots: [TogetherSaveSlot]) {
        struct List: Decodable { let usage: TogetherStorageUsage?; let slots: [TogetherSaveSlot] }
        let query = titleId.map { "?titleId=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? ""
        let list = try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "me/saves" + query, nil))
        return (list.usage, list.slots)
    }

    /// Begins an upload, checked for a conflict (`baseVersion`) and the quota before any byte.
    public func beginSaveUpload(titleId: String, slot: String, size: Int, sha256: String, device: String?, launcherVersion: String?,
                                baseVersion: Int?, replaceLatest: Bool = false) async throws -> TogetherSaveUpload {
        var body: [String: Any] = ["titleId": titleId, "slot": slot, "size": size, "sha256": sha256]
        if let device { body["device"] = String(device.prefix(80)) }
        if let launcherVersion { body["launcherVersion"] = String(launcherVersion.prefix(40)) }
        if let baseVersion { body["baseVersion"] = baseVersion }
        if replaceLatest { body["replaceLatest"] = true }
        return try JSONDecoder.together.decode(TogetherSaveUpload.self, from: try await authorized("POST", "me/saves/uploads", body))
    }

    public func saveUpload(_ id: String) async throws -> TogetherSaveUpload {
        try JSONDecoder.together.decode(TogetherSaveUpload.self, from: try await authorized("GET", "me/saves/uploads/\(id)", nil))
    }

    /// One part (numbered from 1), checked against its SHA-256 on the way; the parts received.
    @discardableResult
    public func uploadSavePart(_ id: String, part: Int, data: Data) async throws -> [Int] {
        struct Answer: Decodable { let received: [Int] }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let body = TogetherRawBody(data: data, contentType: "application/octet-stream", headers: ["X-Part-SHA256": digest])
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("PUT", "me/saves/uploads/\(id)/parts/\(part)", body)).received
    }

    public func completeSaveUpload(_ id: String, baseVersion: Int?, replaceLatest: Bool = false) async throws -> TogetherSaveCompleted {
        var body: [String: Any] = [:]
        if let baseVersion { body["baseVersion"] = baseVersion }
        if replaceLatest { body["replaceLatest"] = true }
        return try JSONDecoder.together.decode(TogetherSaveCompleted.self, from: try await authorized("POST", "me/saves/uploads/\(id)/complete", body))
    }

    public func cancelSaveUpload(_ id: String) async throws {
        _ = try await authorized("DELETE", "me/saves/uploads/\(id)", nil)
    }

    /// Makes an older version the newest again (the same bytes: nothing more is counted).
    @discardableResult
    public func restoreSaveVersion(_ id: String) async throws -> TogetherSaveVersion {
        struct Answer: Decodable { let version: TogetherSaveVersion }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("POST", "me/saves/versions/\(id)/restore", nil)).version
    }

    @discardableResult
    public func deleteSaveVersion(_ id: String) async throws -> TogetherStorageUsage? {
        struct Answer: Decodable { let usage: TogetherStorageUsage? }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("DELETE", "me/saves/versions/\(id)", nil)).usage
    }

    @discardableResult
    public func deleteSaveSlot(_ id: String) async throws -> TogetherStorageUsage? {
        struct Answer: Decodable { let usage: TogetherStorageUsage? }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("DELETE", "me/saves/slots/\(id)", nil)).usage
    }

    /// A save version's archive into `file`. A part left by a broken download is asked for from
    /// where it stopped (Range), so it goes on instead of starting over.
    public func downloadSaveVersion(_ id: String, to file: URL) async throws {
        try await download("me/saves/versions/\(id)/download", to: file)
    }

    /// A signed-in download into a file, resuming a partial one.
    func download(_ path: String, to file: URL) async throws {
        let token = try await accessToken()
        do {
            try await downloadOnce(path, to: file, token: token)
        } catch let problem as TogetherProblem where problem.status == 401 {
            _ = try await refreshedToken()
            try await downloadOnce(path, to: file, token: try await accessToken())
        }
    }

    private func downloadOnce(_ path: String, to file: URL, token: String) async throws {
        var request = URLRequest(url: URL(string: base.appendingPathComponent("api/v1").absoluteString + "/" + path)!)
        request.timeoutInterval = 60
        request.setValue(clientName, forHTTPHeaderField: "AnyTogether-Client")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let have = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 416 {
            // Asked past the end: the part is whole already (or wrong); the caller checks it.
            return
        }
        guard (200 ..< 300).contains(status) else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw (try? JSONDecoder.together.decode(TogetherProblem.self, from: data)) ?? TogetherProblem(status: status, code: "internal", title: "AnyTogether answered \(status)")
        }
        if status != 206 || !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        if status == 206 { try handle.seekToEnd() } else { try handle.truncate(atOffset: 0) }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
    }

    // MARK: Media

    /// A photo, clip or voice note going up (the bytes decide what it is); it is deleted unless
    /// sent or pinned within a day.
    public func uploadMedia(kind: String, data: Data, contentType: String) async throws -> (media: TogetherMedia, usage: TogetherStorageUsage?) {
        struct Answer: Decodable { let media: TogetherMedia; let usage: TogetherStorageUsage? }
        let answer = try JSONDecoder.together.decode(Answer.self, from: try await authorized("POST", "me/media?kind=\(kind)", TogetherRawBody(data: data, contentType: contentType)))
        return (answer.media, answer.usage)
    }

    /// The still shown before a clip plays (PNG, JPEG or WebP up to 2 MB).
    @discardableResult
    public func setPoster(_ mediaId: String, data: Data, contentType: String) async throws -> TogetherMedia {
        struct Answer: Decodable { let media: TogetherMedia }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("PUT", "me/media/\(mediaId)/poster", TogetherRawBody(data: data, contentType: contentType))).media
    }

    @discardableResult
    public func deleteMedia(_ id: String) async throws -> TogetherStorageUsage? {
        struct Answer: Decodable { let usage: TogetherStorageUsage? }
        return try JSONDecoder.together.decode(Answer.self, from: try await authorized("DELETE", "me/media/\(id)", nil)).usage
    }

    /// Someone's pinned photos and clips, as their gallery setting lets this user see them.
    public func gallery(of handle: String) async throws -> TogetherSection<[TogetherMedia]> {
        struct List: Decodable { let items: [TogetherMedia]?; let enabled: Bool? }
        do {
            let list = try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "users/\(Self.path(handle))/gallery", nil))
            return .shown(list.items ?? [])
        } catch let problem as TogetherProblem where Self.isPrivate(problem) {
            return .private
        } catch let problem as TogetherProblem where problem.status == 401 {
            throw problem
        } catch {
            return .failed
        }
    }

    public func myGallery() async throws -> [TogetherMedia] {
        struct List: Decodable { let items: [TogetherMedia] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "me/gallery", nil)).items
    }

    /// The whole gallery, in order (at most 12 of the user's own photos and clips).
    @discardableResult
    public func setGallery(_ ids: [String]) async throws -> [TogetherMedia] {
        struct List: Decodable { let items: [TogetherMedia] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("PUT", "me/gallery", ["items": ids])).items
    }

    /// Pins a piece of the user's media at the end of the gallery; false when it is full.
    public func pinToGallery(_ mediaId: String, max: Int = 12) async throws -> Bool {
        let current = try await myGallery().map(\.id)
        if current.contains(mediaId) { return true }
        guard current.count < max else { return false }
        try await setGallery(current + [mediaId])
        return true
    }

    /// The SHA-256 of a file, in hex, read in pieces.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
