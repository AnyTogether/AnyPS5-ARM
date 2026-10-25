import Darwin
import Foundation

/// A frame on Discord's local socket: a little-endian opcode and length, then JSON.
public enum DiscordFrame {
    public static func encode(op: UInt32, json: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: op.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(json)
        return data
    }

    public static func decode(_ data: Data) -> (op: UInt32, json: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return nil }
        let op = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let length = Int(UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24)
        guard bytes.count == 8 + length else { return nil }
        return (op, Data(bytes[8...]))
    }
}

/// The games Discord knows (its public applications/detectable list), by name: a game found in
/// it is shown on Discord as itself, with its own name and icon.
public struct DiscordGames: Sendable {
    public static let source = URL(string: "https://discord.com/api/v9/applications/detectable")!
    static let maxAge: TimeInterval = 7 * 24 * 3600

    private let ids: [String: String]

    public init() { ids = [:] }

    /// From the list as Discord serves it, or as the launcher caches it: objects with an id, a
    /// name and aliases.
    public init(json: Data) {
        var ids: [String: String] = [:]
        for entry in (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] ?? [] {
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { continue }
            for key in [name] + (entry["aliases"] as? [String] ?? []) {
                let normal = DiscordGames.normalized(key)
                if !normal.isEmpty, ids[normal] == nil { ids[normal] = id }
            }
        }
        self.ids = ids
    }

    public func applicationID(for game: String) -> String? { ids[DiscordGames.normalized(game)] }

    /// Lowercase letters and digits only, so "Plants vs. Zombies™: Replanted" finds "Plants vs.
    /// Zombies: Replanted".
    static func normalized(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        return folded.split { !($0.isLetter || $0.isNumber) }.joined(separator: " ")
    }

    public static var cacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/discord-games.json")
    }

    /// The cached list at once, then a fresh one from Discord when the cache is a week old or
    /// missing. Without a network the cache, or an empty list, stays.
    public static func load(cache: URL = cacheFile, update: @escaping @Sendable (DiscordGames) -> Void) {
        let cached = try? Data(contentsOf: cache)
        if let cached { update(DiscordGames(json: cached)) }
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) } ?? .infinity
        guard cached == nil || age > maxAge else { return }
        URLSession.shared.dataTask(with: source) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !entries.isEmpty else { return }
            let slim = entries.map { ["id": $0["id"] ?? "", "name": $0["name"] ?? "", "aliases": $0["aliases"] ?? []] }
            if let compact = try? JSONSerialization.data(withJSONObject: slim) {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? compact.write(to: cache, options: .atomic)
                update(DiscordGames(json: compact))
            }
        }.resume()
    }
}

/// What the user's Discord profile shows: the game, the party they are in (with its size), and a
/// Join button that opens the code's web page. Built here, with no socket, so it can be checked.
public struct DiscordActivity: Equatable, Sendable {
    /// A button under the activity: Discord takes two at most, a label of 32 characters at most
    /// and an https link of 512 at most.
    public struct Button: Equatable, Sendable {
        public static let maxLabel = 32
        public static let maxURL = 512

        public let label: String
        public let url: String

        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }

        /// As SET_ACTIVITY takes it; nil when Discord would refuse it.
        var json: [String: String]? {
            let label = String(self.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Button.maxLabel))
            guard !label.isEmpty, url.lowercased().hasPrefix("https://"), url.utf8.count <= Button.maxURL, URL(string: url)?.host != nil else { return nil }
            return ["label": label, "url": url]
        }
    }

    /// The party, shown as "(2 of 8)".
    public struct Party: Equatable, Sendable {
        public let id: String
        public let size: Int
        public let max: Int

        public init(id: String, size: Int, max: Int) {
            self.id = id
            self.size = size
            self.max = max
        }
    }

    public var game: String?
    public var since: Date?
    public var party: Party?
    public var buttons: [Button]
    /// "In a party", in the launcher's language.
    public var partyText: String

    public init(game: String? = nil, since: Date? = nil, party: Party? = nil, button: Button? = nil, partyText: String) {
        self.game = game
        self.since = since
        self.party = party
        buttons = button.map { [$0] } ?? []
        self.partyText = partyText
    }

    /// The activity for SET_ACTIVITY, nil when there is nothing to show (no game, no party). A
    /// game Discord knows (`knownGame`) shows as itself, so the launcher's name goes under it.
    public func json(knownGame: Bool) -> [String: Any]? {
        guard game != nil || party != nil else { return nil }
        var activity: [String: Any] = ["type": 0]
        if let since { activity["timestamps"] = ["start": Int(since.timeIntervalSince1970)] }
        if let game {
            if knownGame {
                activity["details"] = "AnyPS5 Launcher · Mac"
                // Discord shows the party's size next to the state.
                if party != nil { activity["state"] = partyText }
            } else {
                activity["details"] = game
                activity["state"] = "AnyPS5 · Mac"
            }
        } else {
            activity["details"] = partyText
            activity["state"] = "AnyPS5 · Mac"
        }
        if let party {
            let size = Swift.max(1, party.size)
            activity["party"] = ["id": party.id, "size": [size, Swift.max(size, party.max)]] as [String: Any]
        }
        let buttons = buttons.compactMap(\.json).prefix(2)
        if !buttons.isEmpty { activity["buttons"] = Array(buttons) }
        return activity
    }
}

/// Which code the Join button on Discord opens: one that works (the share play the user hosts
/// first, then the party), else a new one made for it, but only for the party's leader or the
/// share play's host, and never again where the user stopped the code themselves.
public enum DiscordJoin {
    public struct Source: Equatable, Sendable {
        public let id: String
        public let code: TogetherJoinCode?
        /// The user leads the party or hosts the share play.
        public let mine: Bool
        /// A code may be made for the button (the user did not stop one here, and none failed).
        public let mayMake: Bool

        public init(id: String, code: TogetherJoinCode?, mine: Bool, mayMake: Bool) {
            self.id = id
            self.code = code
            self.mine = mine
            self.mayMake = mayMake
        }
    }

    public enum Plan: Equatable, Sendable {
        case none
        case button(String)
        case makeShare(String)
        case makeParty(String)
    }

    public static func plan(share: Source?, party: Source?, now: Date = Date()) -> Plan {
        for source in [share, party].compactMap({ $0 }) {
            if let code = source.code, code.works(at: now) { return .button(code.url) }
        }
        if let share, share.mine, share.mayMake { return .makeShare(share.id) }
        if let party, party.mine, party.mayMake { return .makeParty(party.id) }
        return .none
    }
}

/// "Playing <game>" on the user's Discord profile, through the Discord app's local socket
/// (discord-ipc-N in the runtime or temporary folder). Without Discord, or without an application
/// ID, nothing happens; a Discord started later is found on the next game.
public final class DiscordPresence: @unchecked Sendable {
    /// The AnyPS5 application in the Discord Developer Portal; empty turns the presence off.
    public static let anyps5ApplicationID = "1562749843724566549"

    /// The application the launcher shows as: ANYPS5_DISCORD_APP_ID puts another one in its
    /// place, and set but empty turns the presence off.
    public static var applicationID: String { applicationID(environment: ProcessInfo.processInfo.environment) }

    static func applicationID(environment: [String: String]) -> String {
        environment["ANYPS5_DISCORD_APP_ID"].map { $0.trimmingCharacters(in: .whitespaces) } ?? anyps5ApplicationID
    }

    /// Where Discord makes its sockets: XDG_RUNTIME_DIR when set, the user's temporary folder, then /tmp.
    public static func socketDirectories(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var paths: [String] = []
        for value in [environment["XDG_RUNTIME_DIR"], environment["TMPDIR"] ?? NSTemporaryDirectory(), "/tmp"] {
            guard let value, !value.isEmpty else { continue }
            let path = URL(fileURLWithPath: value).standardizedFileURL.path
            if !paths.contains(path) { paths.append(path) }
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private let ownID: String
    private let directories: [URL]
    private let queue = DispatchQueue(label: "org.anyps5.discord")
    private var socket: Int32 = -1
    /// The application the open socket shook hands as.
    private var connectedID: String?
    private var games: DiscordGames

    public init(applicationID: String, directories: [URL] = DiscordPresence.socketDirectories(), games: DiscordGames = DiscordGames()) {
        self.ownID = applicationID
        self.directories = directories
        self.games = games
    }

    public convenience init(applicationID: String, directory: URL, games: DiscordGames = DiscordGames()) {
        self.init(applicationID: applicationID, directories: [directory], games: games)
    }

    public func use(_ games: DiscordGames) {
        queue.async { [self] in self.games = games }
    }

    deinit { if socket >= 0 { Darwin.close(socket) } }

    /// Shows the game, with the time it has been played since `since`. A game Discord knows shows
    /// as itself, with AnyPS5 under it; any other shows under AnyPS5. No image is named, so Discord
    /// shows the application's own icon.
    public func playing(_ game: String, since: Date) {
        show(DiscordActivity(game: game, since: since, partyText: ""))
    }

    /// The whole activity: the game (as itself when Discord knows it), the party and the Join
    /// button; nil, or one with nothing to show, clears it.
    public func show(_ activity: DiscordActivity?) {
        queue.async { [self] in
            let known = activity?.game.flatMap { games.applicationID(for: $0) }
            guard let json = activity?.json(knownGame: known != nil) else { return clearNow() }
            setActivity(json, as: known ?? ownID)
        }
    }

    public func clear() {
        queue.async { [self] in clearNow() }
    }

    private func clearNow() {
        guard socket >= 0, let connectedID else { return }
        setActivity(NSNull(), as: connectedID)
    }

    public func close() {
        queue.sync {
            if socket >= 0 { Darwin.close(socket) }
            socket = -1
        }
    }

    private func setActivity(_ activity: Any, as application: String) {
        guard !ownID.isEmpty, !application.isEmpty else { return }
        // Discord ties a socket to the application it shook hands as: another one needs its own.
        if socket >= 0, connectedID != application {
            Darwin.close(socket)
            socket = -1
        }
        let command: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(ProcessInfo.processInfo.processIdentifier), "activity": activity],
            "nonce": UUID().uuidString,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: command) else { return }
        // A Discord that restarted closed the old socket: connect once more and send again.
        for _ in 0..<2 {
            guard connected(as: application) else { return }
            if write(op: 1, json: json), read() != nil { return }
            Darwin.close(socket)
            socket = -1
        }
    }

    /// Connects and shakes hands with the first Discord socket that answers.
    private func connected(as application: String) -> Bool {
        if socket >= 0 { return true }
        for directory in directories {
            for index in 0..<10 where open(directory.appendingPathComponent("discord-ipc-\(index)").path, as: application) { return true }
        }
        return false
    }

    /// Connects to one socket and shakes hands; false leaves no socket open.
    private func open(_ path: String, as application: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let candidate = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard candidate >= 0 else { return false }
        var on: Int32 = 1
        setsockopt(candidate, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let fits = withUnsafeMutableBytes(of: &address.sun_path) { raw -> Bool in
            let bytes = Array(path.utf8) + [0]
            guard bytes.count <= raw.count else { return false }
            raw.copyBytes(from: bytes)
            return true
        }
        let reached = fits && withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
        guard reached else {
            Darwin.close(candidate)
            return false
        }
        socket = candidate
        let handshake = try? JSONSerialization.data(withJSONObject: ["v": 1, "client_id": application])
        if let handshake, write(op: 0, json: handshake), let ready = read(), ready.op == 1 {
            connectedID = application
            return true
        }
        Darwin.close(candidate)
        socket = -1
        return false
    }

    private func write(op: UInt32, json: Data) -> Bool {
        let frame = DiscordFrame.encode(op: op, json: json)
        return frame.withUnsafeBytes { Darwin.send(socket, $0.baseAddress, frame.count, 0) } == frame.count
    }

    private func read() -> (op: UInt32, json: Data)? {
        var header = [UInt8](repeating: 0, count: 8)
        guard recv(socket, &header, 8, MSG_WAITALL) == 8 else { return nil }
        let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
        guard length < 1 << 20 else { return nil }
        var body = [UInt8](repeating: 0, count: length)
        guard length == 0 || recv(socket, &body, length, MSG_WAITALL) == length else { return nil }
        return DiscordFrame.decode(Data(header + body))
    }
}
