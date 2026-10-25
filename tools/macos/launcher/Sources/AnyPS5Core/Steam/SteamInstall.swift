import Foundation

/// A Steam installation: its folder and the accounts that signed in on this Mac.
public struct SteamInstall: Equatable {
    /// The folder holding userdata/ and config/ (~/Library/Application Support/Steam).
    public let root: URL

    public init(root: URL) { self.root = root }

    public var userdata: URL { root.appendingPathComponent("userdata") }
    public var loginUsers: URL { root.appendingPathComponent("config").appendingPathComponent("loginusers.vdf") }

    /// The accounts with a userdata folder, the most recently signed in first.
    public func users() -> [SteamUser] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: userdata.path) else { return [] }
        var logins: [String: TextVdf.Value] = [:]
        if let text = try? String(contentsOf: loginUsers, encoding: .utf8), let parsed = try? TextVdf.parse(text) {
            for (key, value) in parsed["users"]?.entries ?? [] {
                guard let steamID = UInt64(key) else { continue }
                logins[String(SteamUser.accountID(of: steamID))] = value
            }
        }
        var found: [SteamUser] = []
        for name in names {
            var directory: ObjCBool = false
            // 0 is the anonymous account some clients leave behind.
            guard UInt64(name) != nil, name != "0",
                  manager.fileExists(atPath: userdata.appendingPathComponent(name).path, isDirectory: &directory), directory.boolValue else { continue }
            let login = logins[name]
            found.append(SteamUser(id: name, persona: login?["PersonaName"]?.text, account: login?["AccountName"]?.text,
                                   mostRecent: login?["MostRecent"]?.text == "1", lastLogin: Int(login?["Timestamp"]?.text ?? "") ?? 0))
        }
        return found.sorted { a, b in
            if a.mostRecent != b.mostRecent { return a.mostRecent }
            if a.lastLogin != b.lastLogin { return a.lastLogin > b.lastLogin }
            return a.id < b.id
        }
    }
}

/// A Steam account on this Mac, by its userdata folder.
public struct SteamUser: Equatable, Hashable {
    /// The userdata folder's name: the account's 32-bit ID.
    public let id: String
    public var persona: String?
    public var account: String?
    /// Signed in last (loginusers.vdf's MostRecent).
    public var mostRecent: Bool
    /// When it last signed in, Unix seconds; 0 when unknown.
    public var lastLogin: Int

    public init(id: String, persona: String? = nil, account: String? = nil, mostRecent: Bool = false, lastLogin: Int = 0) {
        self.id = id
        self.persona = persona
        self.account = account
        self.mostRecent = mostRecent
        self.lastLogin = lastLogin
    }

    public var label: String { persona ?? account ?? id }

    /// The userdata folder of a 64-bit Steam ID: its low 32 bits.
    public static func accountID(of steamID: UInt64) -> UInt32 { UInt32(truncatingIfNeeded: steamID) }
}

/// Finds Steam where it installs itself on a Mac.
public enum SteamLocator {
    /// ~/Library/Application Support/Steam when it has a userdata folder.
    public static func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SteamInstall] {
        let root = home.appendingPathComponent("Library/Application Support/Steam")
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("userdata").path, isDirectory: &directory), directory.boolValue else { return [] }
        return [SteamInstall(root: root.resolvingSymlinksInPath())]
    }
}

/// Whether Steam runs, and asking it to quit: shortcuts.vdf is written only while it is closed,
/// as Steam writes its own copy over the file when it exits.
public struct SteamControl {
    /// Runs a program and gives its exit status (pgrep: 0 when Steam runs).
    public var run: (String, [String]) -> Int32
    /// Starts a program without waiting (the request to quit).
    public var start: (String, [String]) throws -> Void

    public init(run: @escaping (String, [String]) -> Int32 = SteamControl.runProcess,
                start: @escaping (String, [String]) throws -> Void = SteamControl.startProcess) {
        self.run = run
        self.start = start
    }

    public static func runProcess(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    public static func startProcess(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
    }

    public func running() -> Bool { run("/usr/bin/pgrep", ["-x", "steam_osx"]) == 0 }

    /// Steam's own quit, through its URL scheme.
    public static let shutdownCommand = ["/usr/bin/open", "steam://exit"]

    /// Asks Steam to quit and waits up to `timeout` for it; true once it is gone.
    public func shutdown(timeout: TimeInterval = 40, poll: TimeInterval = 0.5) async -> Bool {
        if !running() { return true }
        try? start(Self.shutdownCommand[0], Array(Self.shutdownCommand.dropFirst()))
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            try? await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
            if !running() {
                // Steam writes its files as it goes: a moment for the last of them.
                try? await Task.sleep(nanoseconds: UInt64(poll * 2_000_000_000))
                return true
            }
        }
        return false
    }
}

/// How this launch came from Steam: Steam starts a non-Steam shortcut with SteamGameId /
/// SteamAppId set (and AnyPS5's shortcuts pass --steam); with Steam Input on it hides the
/// controllers it took over through SDL_GAMECONTROLLER_IGNORE_DEVICES and offers its virtual pad.
public struct SteamLaunch: Equatable {
    public var fromSteam = false
    public var gameID: String?
    public var play: String?
    public var fullscreen = false
    public var ignoredPads: Set<SteamPadID> = []

    public init() {}

    public init(arguments: [String], environment: [String: String]) {
        func value(_ name: String) -> String? {
            guard let text = environment[name], !text.isEmpty, text != "0" else { return nil }
            return text
        }
        gameID = value("SteamGameId") ?? value("SteamAppId")
        fromSteam = arguments.contains(SteamShortcuts.launchFlag) || gameID != nil
        fullscreen = arguments.contains("--fullscreen")
        if let at = arguments.firstIndex(of: "--play"), at + 1 < arguments.count, !arguments[at + 1].hasPrefix("--") {
            play = arguments[at + 1].uppercased()
        }
        ignoredPads = Self.parseDevices(environment["SDL_GAMECONTROLLER_IGNORE_DEVICES"])
    }

    /// Valve's vendor ID and Steam Input's virtual gamepad.
    public static let virtualPad = SteamPadID(vendor: 0x28DE, product: 0x11FF)

    /// Whether a physical controller should be left alone because Steam Input reads it and offers
    /// it again as its virtual pad. Steam's own virtual pad is never skipped.
    public func skipPhysicalPad(vendor: Int, product: Int) -> Bool {
        let pad = SteamPadID(vendor: vendor, product: product)
        return fromSteam && pad != Self.virtualPad && ignoredPads.contains(pad)
    }

    /// SDL's device list: "0x054c/0x0ce6,0x28de/0x1142" (vendor/product, hex).
    public static func parseDevices(_ text: String?) -> Set<SteamPadID> {
        guard let text else { return [] }
        var found: Set<SteamPadID> = []
        for item in text.split(separator: ",") {
            let parts = item.trimmingCharacters(in: .whitespaces).split(separator: "/")
            guard parts.count == 2 else { continue }
            func hex(_ part: Substring) -> Int? { Int(part.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) }
            if let vendor = hex(parts[0]), let product = hex(parts[1]) { found.insert(SteamPadID(vendor: vendor, product: product)) }
        }
        return found
    }
}

public struct SteamPadID: Hashable, Sendable {
    public let vendor: Int
    public let product: Int

    public init(vendor: Int, product: Int) {
        self.vendor = vendor
        self.product = product
    }
}
