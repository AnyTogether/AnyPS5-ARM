import Foundation

/// Who may see a part of a profile; the owner always sees everything.
public enum TogetherVisibility: String, Codable, CaseIterable, Sendable {
    case everyone, friends, nobody
}

/// The user's privacy settings, one visibility per section.
public struct TogetherPrivacy: Decodable, Equatable, Sendable {
    /// library: games and play time; friends: the friends list; presence: online and what is
    /// being played; search: who finds the account by name; gallery: the pinned photos and
    /// clips (only where the server keeps files).
    public enum Section: String, CaseIterable, Sendable {
        case library, trophies, friends, presence, search, gallery
    }

    private var values: [Section: TogetherVisibility]

    /// The server's defaults.
    public static let standard = TogetherPrivacy(values: [.library: .friends, .trophies: .friends, .friends: .friends, .presence: .friends, .search: .everyone, .gallery: .friends])

    init(values: [Section: TogetherVisibility]) { self.values = values }

    public init(from decoder: Decoder) throws {
        // Only the sections known here, whatever else a newer server adds (and of any type).
        struct AnyKey: CodingKey {
            let stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }
        let container = try decoder.container(keyedBy: AnyKey.self)
        var raw: [String: String] = [:]
        for key in container.allKeys { raw[key.stringValue] = try? container.decode(String.self, forKey: key) }
        values = TogetherPrivacy.standard.values
        for section in Section.allCases {
            if let value = raw[section.rawValue].flatMap(TogetherVisibility.init(rawValue:)) { values[section] = value }
        }
    }

    public subscript(section: Section) -> TogetherVisibility {
        get { values[section] ?? .friends }
        set { values[section] = newValue }
    }
}

/// The signed-in user's own profile, as only they see it.
public struct TogetherOwnProfile: Decodable, Equatable, Sendable {
    public let handle: String
    public let displayName: String
    public let bio: String?
    public let avatar: String?
    public let country: String?
    /// When the handle may change again; nil when it may now.
    public let handleChangeAt: Date?
    public var privacy: TogetherPrivacy

    public init(handle: String, displayName: String, bio: String?, avatar: String?, country: String?, handleChangeAt: Date?, privacy: TogetherPrivacy) {
        self.handle = handle
        self.displayName = displayName
        self.bio = bio
        self.avatar = avatar
        self.country = country
        self.handleChangeAt = handleChangeAt
        self.privacy = privacy
    }

    enum CodingKeys: String, CodingKey { case handle, displayName, bio, avatar, country, handleChangeAt, privacy }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handle = try container.decode(String.self, forKey: .handle)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        handleChangeAt = try container.decodeIfPresent(Date.self, forKey: .handleChangeAt)
        privacy = try container.decodeIfPresent(TogetherPrivacy.self, forKey: .privacy) ?? .standard
    }
}

extension TogetherClient {
    public func myProfile() async throws -> TogetherOwnProfile {
        struct Me: Decodable { let profile: TogetherOwnProfile }
        return try kept(JSONDecoder.together.decode(Me.self, from: try await authorized("GET", "me", nil)).profile)
    }

    /// Only the fields given change; an empty bio or country clears it.
    public func updateProfile(displayName: String? = nil, bio: String? = nil, country: String? = nil) async throws -> TogetherOwnProfile {
        var changes: [String: Any] = [:]
        if let displayName { changes["displayName"] = displayName }
        if let bio { changes["bio"] = bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSNull() : bio }
        if let country { changes["country"] = country.trimmingCharacters(in: .whitespaces).isEmpty ? NSNull() : country.trimmingCharacters(in: .whitespaces).uppercased() }
        return try kept(JSONDecoder.together.decode(TogetherOwnProfile.self, from: try await authorized("PATCH", "me/profile", changes)))
    }

    /// A new handle: "handle_taken", "handle_reserved", "handle_cooldown" (with `handleChangeAt`)
    /// or "bad_request" when it is refused.
    public func changeHandle(_ handle: String) async throws -> TogetherOwnProfile {
        let cleaned = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        return try kept(JSONDecoder.together.decode(TogetherOwnProfile.self, from: try await authorized("PATCH", "me/handle", ["handle": cleaned])))
    }

    public func updatePrivacy(_ section: TogetherPrivacy.Section, to visibility: TogetherVisibility) async throws -> TogetherPrivacy {
        try JSONDecoder.together.decode(TogetherPrivacy.self, from: try await authorized("PATCH", "me/privacy", [section.rawValue: visibility.rawValue]))
    }

    /// A new avatar (PUT /me/avatar): a PNG or JPEG, at most 5 MB, that the server makes a
    /// square JPEG; returns its address, which the session's user keeps.
    public func uploadAvatar(_ picture: Data) async throws -> String {
        struct Answer: Decodable { let avatar: String }
        let body = TogetherRawBody(data: picture, contentType: ProfilePicture.contentType(picture))
        let answer = try JSONDecoder.together.decode(Answer.self, from: try await authorized("PUT", "me/avatar", body))
        store.update { user in
            user = TogetherUser(id: user.id, handle: user.handle, displayName: user.displayName, avatar: answer.avatar)
        }
        return answer.avatar
    }

    /// The session's user follows the profile: its handle, name and avatar.
    private func kept(_ profile: TogetherOwnProfile) -> TogetherOwnProfile {
        store.update { user in
            user = TogetherUser(id: user.id, handle: profile.handle, displayName: profile.displayName, avatar: profile.avatar)
        }
        return profile
    }
}
