import Foundation

// MARK: Look

/// A profile's cover: a preset AnyTogether draws, or a game's artwork.
public struct TogetherProfileCover: Decodable, Equatable, Sendable {
    /// "preset" or "game".
    public let kind: String
    /// The preset ("cosmic-ribbons"), or the game's title ID.
    public let id: String
    public let url: String

    public init(kind: String, id: String, url: String) {
        self.kind = kind
        self.id = id
        self.url = url
    }
}

/// A Theme Hub theme a profile wears (only a published one is sent).
public struct TogetherProfileTheme: Decodable, Equatable, Sendable, Identifiable {
    public struct Maker: Decodable, Equatable, Sendable {
        public let handle: String
        public let displayName: String

        public init(handle: String, displayName: String) {
            self.handle = handle
            self.displayName = displayName
        }
    }

    public let id: String
    public let name: String
    public let colors: TogetherHubTheme.Colors
    /// 1280x720 and 640x360 WebP stills.
    public let preview: String
    public let thumb: String
    public let maker: Maker?

    public init(id: String, name: String, colors: TogetherHubTheme.Colors, preview: String, thumb: String, maker: Maker?) {
        self.id = id
        self.name = name
        self.colors = colors
        self.preview = preview
        self.thumb = thumb
        self.maker = maker
    }

    enum CodingKeys: String, CodingKey { case id, name, colors, preview, thumb, maker }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(String.self, forKey: .id), name: try container.decode(String.self, forKey: .name),
                  colors: try container.decode(TogetherHubTheme.Colors.self, forKey: .colors), preview: try container.decode(String.self, forKey: .preview),
                  thumb: container.lenient(String.self, .thumb) ?? "", maker: container.lenient(Maker.self, .maker))
    }

    /// A theme from the Hub's list, as a profile wears it.
    public init(_ theme: TogetherHubTheme) {
        self.init(id: theme.id, name: theme.name, colors: theme.colors, preview: theme.preview, thumb: theme.thumb,
                  maker: theme.maker.map { Maker(handle: $0.handle, displayName: $0.displayName) })
    }
}

/// How a profile looks: its cover, accent and the theme it wears. Every client draws it the same:
/// the cover's picture behind the header, else the theme's still; the accent, else the theme's;
/// and a worn theme tints the header from its deep tone to its middle one.
public struct TogetherProfileLook: Decodable, Equatable, Sendable {
    /// The accents a profile picks from, by name.
    public static let accents: [String: String] = [
        "blue": "#4f94ff", "mint": "#5cebbd", "coral": "#ff8066", "violet": "#a885ff", "gold": "#ffcc5c", "white": "#f0f0f0",
    ]

    public static let plain = TogetherProfileLook(cover: nil, accent: nil, theme: nil)

    public var cover: TogetherProfileCover?
    /// One of `accents`' names.
    public var accent: String?
    public var theme: TogetherProfileTheme?

    public init(cover: TogetherProfileCover?, accent: String?, theme: TogetherProfileTheme?) {
        self.cover = cover
        self.accent = accent
        self.theme = theme
    }

    enum CodingKeys: String, CodingKey { case cover, accent, theme }

    /// Each part left out (an older server), null or of a shape this launcher does not expect is nil.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(cover: container.lenient(TogetherProfileCover.self, .cover), accent: container.lenient(String.self, .accent),
                  theme: container.lenient(TogetherProfileTheme.self, .theme))
    }

    /// The picture behind the header: the cover's, else the theme's still.
    public var picture: String? { cover?.url ?? theme?.preview }
    /// The accent as "#rrggbb": the one picked, else the theme's.
    public var accentHex: String? { accent.flatMap { Self.accents[$0] } ?? theme?.colors.accent }
    /// The header's tint while a theme is worn.
    public var tint: (deep: String, middle: String)? { theme.map { ($0.colors.deep, $0.colors.middle) } }
    /// Nothing chosen: the launcher's own header.
    public var isPlain: Bool { picture == nil && accentHex == nil && theme == nil }
}

// MARK: Showcase pins

extension TogetherShowcase {
    /// Six pins in all, trophies and games together.
    public static let limit = 6

    /// What a profile shows: at most six, trophies first (a showcase saved before the shared limit
    /// may hold more). A part private to the reader stays nil.
    public var shown: TogetherShowcase {
        let trophies = self.trophies.map { Array($0.prefix(Self.limit)) }
        let room = Self.limit - (trophies?.count ?? 0)
        return TogetherShowcase(trophies: trophies, games: games.map { Array($0.prefix(max(0, room))) })
    }
}

/// The showcase being edited: trophies and games pinned together, six at most.
public struct TogetherShowcasePins: Equatable, Sendable {
    public struct Trophy: Equatable, Hashable, Sendable {
        public let titleId: String
        public let trophyId: Int

        public init(titleId: String, trophyId: Int) {
            self.titleId = titleId
            self.trophyId = trophyId
        }
    }

    public private(set) var trophies: [Trophy]
    public private(set) var games: [String]

    public init(trophies: [Trophy] = [], games: [String] = []) {
        let kept = Array(trophies.prefix(TogetherShowcase.limit))
        self.trophies = kept
        self.games = Array(games.prefix(max(0, TogetherShowcase.limit - kept.count)))
    }

    /// What is pinned now, as the owner sees it.
    public init(_ showcase: TogetherShowcase) {
        let shown = showcase.shown
        self.init(trophies: (shown.trophies ?? []).map { Trophy(titleId: $0.titleId, trophyId: $0.trophyId) }, games: (shown.games ?? []).map(\.titleId))
    }

    public var count: Int { trophies.count + games.count }
    public var isFull: Bool { count >= TogetherShowcase.limit }

    public func contains(trophy: TogetherEarnedTrophy) -> Bool { trophies.contains(Trophy(titleId: trophy.titleId, trophyId: trophy.trophyId)) }
    public func contains(game titleId: String) -> Bool { games.contains(titleId) }

    /// Pins or unpins; false (and nothing changes) when six are pinned already.
    @discardableResult
    public mutating func toggle(trophy: TogetherEarnedTrophy) -> Bool {
        let pin = Trophy(titleId: trophy.titleId, trophyId: trophy.trophyId)
        if let index = trophies.firstIndex(of: pin) {
            trophies.remove(at: index)
            return true
        }
        guard !isFull else { return false }
        trophies.append(pin)
        return true
    }

    @discardableResult
    public mutating func toggle(game titleId: String) -> Bool {
        if let index = games.firstIndex(of: titleId) {
            games.remove(at: index)
            return true
        }
        guard !isFull else { return false }
        games.append(titleId)
        return true
    }

    /// PUT /me/showcase's body: both lists always, as one left out keeps (and counts) the stored one.
    public var body: [String: Any] {
        ["trophies": trophies.map { ["titleId": $0.titleId, "trophyId": $0.trophyId] as [String: Any] }, "games": games]
    }
}

// MARK: Requests

extension TogetherClient {
    /// PATCH /me/look with a Hub theme's ID to wear it, or nil to take it off. The look the server keeps.
    public func setProfileTheme(_ id: String?) async throws -> TogetherProfileLook {
        let body: [String: Any] = ["theme": id.map { $0 as Any } ?? NSNull()]
        return try JSONDecoder.together.decode(TogetherProfileLook.self, from: try await authorized("PATCH", "me/look", body))
    }

    /// PUT /me/showcase with both lists; the showcase as the owner now sees it.
    public func setShowcase(_ pins: TogetherShowcasePins) async throws -> TogetherShowcase {
        try JSONDecoder.together.decode(TogetherShowcase.self, from: try await authorized("PUT", "me/showcase", pins.body))
    }

    /// GET /themes?sort=popular: the Hub's themes to wear, most popular first.
    public func popularThemes(limit: Int = 24) async throws -> [TogetherHubTheme] {
        struct List: Decodable { let themes: [TogetherHubTheme] }
        return try JSONDecoder.together.decode(List.self, from: try await authorized("GET", "themes?sort=popular&limit=\(limit)", nil)).themes
    }
}
