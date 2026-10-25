import Foundation

/// Where and how the game is broadcast: the service, the picture's quality, the microphone and
/// the LIVE badge. The stream key is kept apart, in BroadcastKeyStore.
public struct BroadcastSettings: Codable, Equatable, Sendable {
    public enum Service: String, Codable, CaseIterable, Sendable {
        case twitch, youtube, custom

        /// The service's own ingest over TLS. Twitch's and YouTube's RTMPS endpoints as they
        /// publish them for encoders; a custom server's URL is the user's.
        public var ingest: String? {
            switch self {
            case .twitch: return "rtmps://ingest.global-contribute.live-video.net/app"
            case .youtube: return "rtmps://a.rtmps.youtube.com/live2"
            case .custom: return nil
            }
        }

        public var name: String {
            switch self {
            case .twitch: return "Twitch"
            case .youtube: return "YouTube"
            case .custom: return "RTMP"
            }
        }

        /// Where the user finds the stream key.
        public var keyPage: URL? {
            switch self {
            case .twitch: return URL(string: "https://dashboard.twitch.tv/settings/stream")
            case .youtube: return URL(string: "https://www.youtube.com/live_dashboard")
            case .custom: return nil
            }
        }
    }

    /// The picture: size, frames a second and bit rate, as streaming services suggest them.
    public enum Quality: String, Codable, CaseIterable, Sendable {
        case hd720p60, hd1080p30, hd1080p60

        public var width: Int { self == .hd720p60 ? 1280 : 1920 }
        public var height: Int { self == .hd720p60 ? 720 : 1080 }
        public var frameRate: Int { self == .hd1080p30 ? 30 : 60 }
        public var bitRate: Int {
            switch self {
            case .hd720p60: return 3_000_000
            case .hd1080p30: return 4_500_000
            case .hd1080p60: return 6_000_000
            }
        }

        /// "720p60 · 3 Mbit/s"
        public var title: String {
            let rate = Double(bitRate) / 1_000_000
            let mbit = rate == rate.rounded() ? String(Int(rate)) : String(format: "%.1f", rate)
            return "\(height)p\(frameRate) · \(mbit) Mbit/s"
        }
    }

    public var service = Service.twitch
    /// The custom server, rtmp:// or rtmps://, with or without the key at its end.
    public var customURL = ""
    public var quality = Quality.hd720p60
    /// The microphone mixed into the game's sound, at `microphoneLevel` percent.
    public var microphone = false
    public var microphoneLevel = 80
    /// A small LIVE badge over the game while it is broadcast (not in the broadcast itself).
    public var liveBadge = true
    /// The page viewers watch on (twitch.tv/name), shown and copied while live.
    public var viewerLink = ""

    public init() {}

    public static let audioBitRate = 160_000
    public static let sampleRate = 48000

    /// The URL the service is reached at.
    public var serverURL: String { service.ingest ?? customURL }

    /// The link viewers open: the one given, or none.
    public var viewerURL: URL? {
        let text = viewerLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return URL(string: text.contains("://") ? text : "https://" + text)
    }

    // MARK: Kept in UserDefaults

    public static let defaultsKey = "AnyPS5.broadcast.v1"

    public static func load(from defaults: UserDefaults = .standard) -> BroadcastSettings {
        guard let data = defaults.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(BroadcastSettings.self, from: data) else { return BroadcastSettings() }
        return saved
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: BroadcastSettings.defaultsKey) }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BroadcastSettings.blank
        service = (try? values.decodeIfPresent(Service.self, forKey: .service)) ?? defaults.service
        customURL = (try? values.decodeIfPresent(String.self, forKey: .customURL)) ?? defaults.customURL
        quality = (try? values.decodeIfPresent(Quality.self, forKey: .quality)) ?? defaults.quality
        microphone = (try? values.decodeIfPresent(Bool.self, forKey: .microphone)) ?? defaults.microphone
        microphoneLevel = (try? values.decodeIfPresent(Int.self, forKey: .microphoneLevel)) ?? defaults.microphoneLevel
        liveBadge = (try? values.decodeIfPresent(Bool.self, forKey: .liveBadge)) ?? defaults.liveBadge
        viewerLink = (try? values.decodeIfPresent(String.self, forKey: .viewerLink)) ?? defaults.viewerLink
    }

    private static let blank = BroadcastSettings()
}

/// The server a broadcast is published to, read from an rtmp:// or rtmps:// URL and a stream
/// key: host, port (1935, or 443 over TLS), the application (live2, app, or app/instance with
/// any query) and the tcUrl the server is told.
public struct RTMPEndpoint: Equatable, Sendable {
    public let tls: Bool
    public let host: String
    public let port: UInt16
    public let app: String
    public let streamKey: String

    public var tcURL: String {
        let defaultPort: UInt16 = tls ? 443 : 1935
        return "\(tls ? "rtmps" : "rtmp")://\(host)\(port == defaultPort ? "" : ":\(port)")/\(app)"
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case notRTMP
        case noHost
        case noApplication
        case noKey

        public var description: String {
            switch self {
            case .notRTMP: return "the server's address does not start with rtmp:// or rtmps://"
            case .noHost: return "the server's address has no host"
            case .noApplication: return "the server's address has no application (like /live2)"
            case .noKey: return "there is no stream key"
            }
        }
    }

    /// `url` with `key`; with no key, a URL of more than one path part ends in it
    /// (rtmp://host/app/key), as some services hand out the whole thing.
    public static func parse(url: String, key: String) throws -> RTMPEndpoint {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let tls: Bool
        if lower.hasPrefix("rtmps://") { tls = true } else if lower.hasPrefix("rtmp://") { tls = false } else { throw Problem.notRTMP }
        let rest = String(text.dropFirst(tls ? 8 : 7))
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let authority = String(rest[..<slash])
        var path = slash < rest.endIndex ? String(rest[rest.index(after: slash)...]) : ""
        var host = authority
        var port: UInt16 = tls ? 443 : 1935
        if let colon = authority.lastIndex(of: ":"), !authority.hasSuffix("]") {
            host = String(authority[..<colon])
            if let given = UInt16(authority[authority.index(after: colon)...]) { port = given }
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { throw Problem.noHost }
        while path.hasSuffix("/") { path.removeLast() }
        if key.isEmpty, path.split(separator: "/").count > 1, let last = path.lastIndex(of: "/") {
            key = String(path[path.index(after: last)...])
            path = String(path[..<last])
        }
        guard !path.isEmpty else { throw Problem.noApplication }
        guard !key.isEmpty else { throw Problem.noKey }
        return RTMPEndpoint(tls: tls, host: host, port: port, app: path, streamKey: key)
    }
}

/// The stream keys, one a service, in a file only the user can read
/// (~/Library/Application Support/AnyPS5/Broadcast/keys.json, 0600), as AnyTogether's tokens
/// are kept: the launcher is signed ad hoc, so the Keychain would ask again after every update.
public final class BroadcastKeyStore: @unchecked Sendable {
    public let file: URL
    private let lock = NSLock()

    public init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Broadcast/keys.json")) {
        self.file = file
    }

    private func all() -> [String: String] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    public func key(for service: BroadcastSettings.Service) -> String {
        lock.withLock { all()[service.rawValue] ?? "" }
    }

    public func setKey(_ key: String, for service: BroadcastSettings.Service) {
        lock.withLock {
            var keys = all()
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            keys[service.rawValue] = trimmed.isEmpty ? nil : trimmed
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard let data = try? JSONEncoder().encode(keys) else { return }
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    /// Every key kept, for a report to take out wherever one appears.
    public var secrets: [String] { lock.withLock { Array(all().values) } }

    /// "live_••••••3f9a": enough to tell which key it is.
    public static func masked(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "•", count: key.count) }
        return String(repeating: "•", count: min(10, key.count - 4)) + key.suffix(4)
    }
}
