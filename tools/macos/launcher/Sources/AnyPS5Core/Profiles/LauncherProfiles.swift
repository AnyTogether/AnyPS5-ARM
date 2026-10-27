import Foundation

/// Someone who plays on this Mac: a name and a picture, offline or with an AnyTogether account,
/// their own settings, saves and trophies.
public struct LauncherProfile: Codable, Equatable, Identifiable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// No account: trophies and progress stay on this Mac.
        case offline
        /// An AnyTogether account (signed in, or to sign in again).
        case online
    }

    /// The account an online profile signed in with, to show while it is signed out.
    public struct Account: Codable, Equatable, Sendable {
        public let userId: String
        public let handle: String

        public init(userId: String, handle: String) {
            self.userId = userId
            self.handle = handle
        }
    }

    /// The tile's colour when there is no picture: an index in the launcher's palette.
    public struct Avatar: Codable, Equatable, Sendable {
        public var color: Int

        public init(color: Int) { self.color = color }
    }

    /// The profile made from the launcher's setup before there were profiles.
    public static let legacyID = "default"
    public static let maxName = 24
    public static let paletteSize = 8

    public let id: String
    public var name: String
    public var avatar: Avatar
    public var mode: Mode
    public var account: Account?
    public let createdAt: Date
    /// The profile's own settings (theme, sounds, …), as the launcher encodes them; nil until it
    /// first switches away from the profile, and then the launcher's defaults apply.
    public var settings: [String: TogetherJSON]?

    public init(id: String, name: String, avatar: Avatar, mode: Mode, account: Account? = nil, createdAt: Date = Date(), settings: [String: TogetherJSON]? = nil) {
        self.id = id
        self.name = LauncherProfile.clean(name)
        self.avatar = avatar
        self.mode = mode
        self.account = account
        self.createdAt = createdAt
        self.settings = settings
    }

    /// Trimmed and at most `maxName` characters; "Player" when nothing is left.
    public static func clean(_ name: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxName)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player" : trimmed
    }

    /// The first letter, for the tile without a picture.
    public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

/// Every profile on this Mac and which one plays.
public struct ProfileBook: Codable, Equatable, Sendable {
    public var profiles: [LauncherProfile] = []
    /// The profile in use (the last one picked).
    public var current: String?
    /// The picker shows at every start, one profile or more.
    public var askEveryTime = false
    /// Whose saves are in a game folder that has no profile mark: the first profile's (the saves
    /// from before profiles).
    public var legacyOwner: String?

    public init() {}

    public var currentProfile: LauncherProfile? { profiles.first { $0.id == current } ?? profiles.first }

    /// The picker's tiles: the profile in use first, then the others as they were made.
    public var pickerOrder: [LauncherProfile] {
        guard let current = currentProfile else { return profiles }
        return [current] + profiles.filter { $0.id != current.id }
    }
}

/// The profiles kept in Application Support/AnyPS5/Profiles/profiles.json.
public final class ProfileStore: @unchecked Sendable {
    /// What the launcher knew before profiles, for the one-time migration.
    public struct ExistingSetup: Sendable {
        public let onboarded: Bool
        public let user: TogetherUser?
        public let name: String

        public init(onboarded: Bool, user: TogetherUser?, name: String) {
            self.onboarded = onboarded
            self.user = user
            self.name = name
        }
    }

    public enum LaunchScreen: Equatable, Sendable {
        /// No profile yet: offline or online.
        case welcome
        /// "Who's playing?"
        case picker
        /// Straight in with this profile.
        case home(String)
    }

    public enum Refusal: Error, Equatable {
        case onlyProfile, inUse, unknown
    }

    public static let defaultFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Profiles")
    public static let legacyPictureFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/profile.png")

    public let folder: URL
    public var file: URL { folder.appendingPathComponent("profiles.json") }
    let legacyPicture: URL
    public private(set) var book: ProfileBook
    private let persists: Bool

    /// Reads the book; with none kept, a launcher set up before profiles (onboarded, or signed
    /// in) becomes its first profile at once, and a new one waits for the welcome.
    public init(folder: URL = ProfileStore.defaultFolder, existing: ExistingSetup, legacyPicture: URL = ProfileStore.legacyPictureFile, persists: Bool = true) {
        self.folder = folder
        self.legacyPicture = legacyPicture
        self.persists = persists
        if let data = try? Data(contentsOf: folder.appendingPathComponent("profiles.json")), let kept = try? JSONDecoder.together.decode(ProfileBook.self, from: data), !kept.profiles.isEmpty {
            book = kept
            return
        }
        book = ProfileBook()
        if existing.onboarded || existing.user != nil {
            let account = existing.user.map { LauncherProfile.Account(userId: $0.id, handle: $0.handle) }
            let profile = LauncherProfile(id: LauncherProfile.legacyID, name: existing.user?.displayName ?? existing.name, avatar: .init(color: 0),
                                          mode: existing.user == nil ? .offline : .online, account: account)
            book.profiles = [profile]
            book.current = profile.id
            book.legacyOwner = profile.id
            save()
        }
    }

    public var launchScreen: LaunchScreen {
        guard let current = book.currentProfile else { return .welcome }
        return book.profiles.count > 1 || book.askEveryTime ? .picker : .home(current.id)
    }

    public func profile(_ id: String) -> LauncherProfile? { book.profiles.first { $0.id == id } }

    /// A new profile; the first one also owns the saves already in the games' folders.
    @discardableResult
    /// `id` is the one a profile signing in was given before it was made.
    public func add(name: String, mode: LauncherProfile.Mode, account: LauncherProfile.Account? = nil, id: String? = nil) -> LauncherProfile {
        let used = Set(book.profiles.map(\.avatar.color))
        let color = (0 ..< LauncherProfile.paletteSize).first { !used.contains($0) } ?? book.profiles.count % LauncherProfile.paletteSize
        let first = book.profiles.isEmpty
        let made = id.flatMap { candidate in self.profile(candidate) == nil ? candidate : nil }
            ?? (first && book.legacyOwner == nil ? LauncherProfile.legacyID : UUID().uuidString.lowercased())
        let profile = LauncherProfile(id: made, name: name, avatar: .init(color: color), mode: mode, account: account)
        book.profiles.append(profile)
        if first {
            book.current = profile.id
            if book.legacyOwner == nil { book.legacyOwner = profile.id }
        }
        save()
        return profile
    }

    public func rename(_ id: String, to name: String) {
        change(id) { $0.name = LauncherProfile.clean(name) }
    }

    public func setMode(_ id: String, _ mode: LauncherProfile.Mode) {
        change(id) { $0.mode = mode }
    }

    public func setAccount(_ id: String, _ account: LauncherProfile.Account?) {
        change(id) { $0.account = account }
    }

    public func setColor(_ id: String, _ color: Int) {
        change(id) { $0.avatar.color = ((color % LauncherProfile.paletteSize) + LauncherProfile.paletteSize) % LauncherProfile.paletteSize }
    }

    public func setSettings(_ id: String, _ settings: [String: TogetherJSON]?) {
        change(id) { $0.settings = settings }
    }

    public func select(_ id: String) {
        guard profile(id) != nil, book.current != id else { return }
        book.current = id
        save()
    }

    public func setAskEveryTime(_ value: Bool) {
        guard book.askEveryTime != value else { return }
        book.askEveryTime = value
        save()
    }

    /// Takes a profile away; the one in use and the last one stay.
    public func remove(_ id: String) throws {
        guard profile(id) != nil else { throw Refusal.unknown }
        guard book.profiles.count > 1 else { throw Refusal.onlyProfile }
        guard book.currentProfile?.id != id else { throw Refusal.inUse }
        book.profiles.removeAll { $0.id == id }
        save()
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id))
    }

    /// The profile's picture: the first profile keeps the one from before profiles.
    public func pictureFile(for id: String) -> URL {
        id == book.legacyOwner ? legacyPicture : folder.appendingPathComponent(id).appendingPathComponent("profile.png")
    }

    private func change(_ id: String, _ body: (inout LauncherProfile) -> Void) {
        guard let index = book.profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = book.profiles[index]
        body(&profile)
        guard profile != book.profiles[index] else { return }
        book.profiles[index] = profile
        save()
    }

    public func save() {
        guard persists else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder.together
        guard let data = try? encoder.encode(book) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// Whether the launcher may change who plays now: never with a game open or starting.
public enum ProfileSwitch {
    public enum Refusal: Equatable, Sendable {
        /// The game playing (or starting) is to be closed first.
        case gameRunning(String)
        /// A game's saves are being synced.
        case syncing
        case alreadyCurrent
        case unknown
    }

    public static func check(to target: String, in book: ProfileBook, running: String?, starting: String?, syncing: Bool) -> Refusal? {
        guard book.profiles.contains(where: { $0.id == target }) else { return .unknown }
        if let game = running ?? starting { return .gameRunning(game) }
        if syncing { return .syncing }
        if book.currentProfile?.id == target { return .alreadyCurrent }
        return nil
    }

    /// Going online or offline signs in or out: not while a game plays either.
    public static func checkModeChange(running: String?, starting: String?) -> Refusal? {
        (running ?? starting).map { .gameRunning($0) }
    }
}

/// The settings that belong to a profile, taken out of and put back into the launcher's
/// encoded settings (a JSON object) by key.
public enum ProfileSettings {
    public static func pick(_ keys: Set<String>, from object: Data) -> [String: TogetherJSON] {
        guard let all = try? JSONDecoder().decode([String: TogetherJSON].self, from: object) else { return [:] }
        return all.filter { keys.contains($0.key) }
    }

    /// `object` with the profile's `values` for `keys`; a key the profile has no value for is
    /// left out, so the launcher's default applies.
    public static func merge(_ values: [String: TogetherJSON], keys: Set<String>, into object: Data) -> Data {
        guard var all = try? JSONDecoder().decode([String: TogetherJSON].self, from: object) else { return object }
        for key in keys { all[key] = values[key] }
        return (try? JSONEncoder().encode(all)) ?? object
    }
}
