import Foundation

/// What a parent lets a child do, as AnyTogether sends it (GET me/family/restrictions). Read the
/// way the server's `restrictionsOf` reads stored limits: anything unknown, missing or invalid
/// falls back to the careful default, field by field and day by day, so a newer server never
/// breaks an older launcher and a broken field never opens everything up.

public enum FamilyWeekday: String, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun
}

/// Whom the child may send friend requests to and get them from.
public enum FamilyFriendRule: String, Sendable {
    case everyone
    case friendsOfFriends = "friends_of_friends"
    case approved
    case nobody
}

/// Whom the child may message and call (family is always reachable).
public enum FamilyMessageRule: String, Sendable {
    case friends, approved, nobody
}

public enum FamilyLimitAction: String, Sendable {
    /// Warn and tell the parents, but let the child go on.
    case notify
    /// Warn at 10 and 1 minutes, show the big notice and close the game after the grace period.
    case close
}

public enum FamilyUnknownAge: String, Sendable {
    case allow, block
}

/// One day of the week: how long the child may play (nil: no limit) and between which times
/// (nil: any time), "07:30" on the child's clock.
public struct FamilyDayPlan: Decodable, Equatable, Sendable {
    public var limitMinutes: Int?
    public var from: String?
    public var until: String?

    public static let anyTime = FamilyDayPlan(limitMinutes: nil, from: nil, until: nil)

    public init(limitMinutes: Int?, from: String?, until: String?) {
        self.limitMinutes = limitMinutes
        self.from = from
        self.until = until
    }

    enum CodingKeys: String, CodingKey { case limitMinutes, from, until }

    /// As the server's DayPlan: all three present (null or a value), a limit within a day, both
    /// times or neither, and `until` after `from`. Anything else throws, and the day falls back.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func nullable<T: Decodable>(_ type: T.Type, _ key: CodingKeys) throws -> T? {
            guard container.contains(key) else { throw DecodingError.keyNotFound(key, .init(codingPath: container.codingPath, debugDescription: "missing")) }
            return try container.decodeNil(forKey: key) ? nil : container.decode(type, forKey: key)
        }
        limitMinutes = try nullable(Int.self, .limitMinutes)
        from = try nullable(String.self, .from)
        until = try nullable(String.self, .until)
        let invalid = DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "not a day plan"))
        if let limit = limitMinutes, !(0 ... 1440).contains(limit) { throw invalid }
        if (from == nil) != (until == nil) { throw invalid }
        if let from, let until {
            guard let start = FamilyPolicy.clockMinutes(from), let end = FamilyPolicy.clockMinutes(until), end > start else { throw invalid }
        }
    }
}

public struct FamilyPlayTime: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var days: [FamilyWeekday: FamilyDayPlan]
    /// The child's clock, for days and windows (an IANA zone).
    public var timeZone: String
    public var whenLimitReached: FamilyLimitAction
    /// Minutes between the big notice and the game closing, to save.
    public var graceMinutes: Int
    /// Tell the parents when the limit is reached.
    public var notifyParents: Bool

    public init(enabled: Bool, days: [FamilyWeekday: FamilyDayPlan], timeZone: String, whenLimitReached: FamilyLimitAction, graceMinutes: Int, notifyParents: Bool) {
        self.enabled = enabled
        self.days = days
        self.timeZone = timeZone
        self.whenLimitReached = whenLimitReached
        self.graceMinutes = graceMinutes
        self.notifyParents = notifyParents
    }

    public static func careful(timeZone: String = "UTC") -> FamilyPlayTime {
        FamilyPlayTime(enabled: false, days: Dictionary(uniqueKeysWithValues: FamilyWeekday.allCases.map { ($0, .anyTime) }), timeZone: timeZone,
                       whenLimitReached: .close, graceMinutes: 3, notifyParents: true)
    }

    /// The plan for a day; any time when it is missing.
    public func plan(_ day: FamilyWeekday) -> FamilyDayPlan { days[day] ?? .anyTime }

    enum CodingKeys: String, CodingKey { case enabled, days, timeZone, whenLimitReached, graceMinutes, notifyParents }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value = FamilyPlayTime.careful()
        if let enabled = try? container.decode(Bool.self, forKey: .enabled) { value.enabled = enabled }
        if let zone = try? container.decode(String.self, forKey: .timeZone), zone.count <= 64, TimeZone(identifier: zone) != nil { value.timeZone = zone }
        if let action = (try? container.decode(String.self, forKey: .whenLimitReached)).flatMap(FamilyLimitAction.init(rawValue:)) { value.whenLimitReached = action }
        if let grace = try? container.decode(Int.self, forKey: .graceMinutes), (0 ... 30).contains(grace) { value.graceMinutes = grace }
        if let notify = try? container.decode(Bool.self, forKey: .notifyParents) { value.notifyParents = notify }
        if let days = try? container.nestedContainer(keyedBy: FamilyAnyKey.self, forKey: .days) {
            for day in FamilyWeekday.allCases {
                value.days[day] = (try? days.decode(FamilyDayPlan.self, forKey: FamilyAnyKey(day.rawValue))) ?? .anyTime
            }
        }
        self = value
    }
}

public struct FamilyRestrictions: Decodable, Equatable, Sendable {
    public var friendRequests: FamilyFriendRule
    public var messages: FamilyMessageRule
    public var voiceChat: Bool
    /// Share play: hosting and watching.
    public var sharePlay: Bool
    /// Public parties, the looking-for-group board ("Find players") and public share plays.
    public var publicMatchmaking: Bool
    /// "friends" or "nobody": the most any part of the profile may show.
    public var profileVisibility: String
    /// Shown in and browsing discovery.
    public var discovery: Bool
    public var communities: Bool
    /// Sharing screenshots and clips.
    public var mediaSharing: Bool
    /// The highest age rating the child may play; nil: any.
    public var ageLimit: Int?
    /// A game whose rating is unknown.
    public var unknownAge: FamilyUnknownAge
    /// Which region's rating counts ("TR", "US"); "default" is the game's own default.
    public var ageRegion: String
    /// Games a parent allowed whatever their rating.
    public var allowedTitles: [String]
    /// People a parent approved for friend requests and messages.
    public var approvedContacts: [String]
    public var playTime: FamilyPlayTime

    /// A new child's limits, the server's `defaultRestrictions`: careful, the parent opens up.
    public static func careful(timeZone: String = "UTC") -> FamilyRestrictions {
        FamilyRestrictions(friendRequests: .approved, messages: .friends, voiceChat: false, sharePlay: false, publicMatchmaking: false, profileVisibility: "friends",
                           discovery: false, communities: false, mediaSharing: false, ageLimit: nil, unknownAge: .allow, ageRegion: "default",
                           allowedTitles: [], approvedContacts: [], playTime: .careful(timeZone: timeZone))
    }

    public init(friendRequests: FamilyFriendRule, messages: FamilyMessageRule, voiceChat: Bool, sharePlay: Bool, publicMatchmaking: Bool, profileVisibility: String,
                discovery: Bool, communities: Bool, mediaSharing: Bool, ageLimit: Int?, unknownAge: FamilyUnknownAge, ageRegion: String,
                allowedTitles: [String], approvedContacts: [String], playTime: FamilyPlayTime) {
        self.friendRequests = friendRequests
        self.messages = messages
        self.voiceChat = voiceChat
        self.sharePlay = sharePlay
        self.publicMatchmaking = publicMatchmaking
        self.profileVisibility = profileVisibility
        self.discovery = discovery
        self.communities = communities
        self.mediaSharing = mediaSharing
        self.ageLimit = ageLimit
        self.unknownAge = unknownAge
        self.ageRegion = ageRegion
        self.allowedTitles = allowedTitles
        self.approvedContacts = approvedContacts
        self.playTime = playTime
    }

    enum CodingKeys: String, CodingKey {
        case friendRequests, messages, voiceChat, sharePlay, publicMatchmaking, profileVisibility, discovery, communities, mediaSharing
        case ageLimit, unknownAge, ageRegion, allowedTitles, approvedContacts, playTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value = FamilyRestrictions.careful()
        func string(_ key: CodingKeys) -> String? { try? container.decode(String.self, forKey: key) }
        func flag(_ key: CodingKeys) -> Bool? { try? container.decode(Bool.self, forKey: key) }
        if let rule = string(.friendRequests).flatMap(FamilyFriendRule.init(rawValue:)) { value.friendRequests = rule }
        if let rule = string(.messages).flatMap(FamilyMessageRule.init(rawValue:)) { value.messages = rule }
        if let on = flag(.voiceChat) { value.voiceChat = on }
        if let on = flag(.sharePlay) { value.sharePlay = on }
        if let on = flag(.publicMatchmaking) { value.publicMatchmaking = on }
        if let visibility = string(.profileVisibility), ["friends", "nobody"].contains(visibility) { value.profileVisibility = visibility }
        if let on = flag(.discovery) { value.discovery = on }
        if let on = flag(.communities) { value.communities = on }
        if let on = flag(.mediaSharing) { value.mediaSharing = on }
        // null is a value here (no limit); only a number out of range or another type falls back.
        if container.contains(.ageLimit) {
            if (try? container.decodeNil(forKey: .ageLimit)) == true {
                value.ageLimit = nil
            } else if let limit = try? container.decode(Int.self, forKey: .ageLimit), (0 ... 99).contains(limit) {
                value.ageLimit = limit
            }
        }
        if let rule = string(.unknownAge).flatMap(FamilyUnknownAge.init(rawValue:)) { value.unknownAge = rule }
        if let region = string(.ageRegion), FamilyPolicy.isRegion(region) { value.ageRegion = region }
        if let titles = try? container.decode([String].self, forKey: .allowedTitles), titles.count <= 500, titles.allSatisfy(FamilyPolicy.isTitleID) { value.allowedTitles = titles }
        if let contacts = try? container.decode([String].self, forKey: .approvedContacts), contacts.count <= 200, contacts.allSatisfy({ UUID(uuidString: $0) != nil }) {
            value.approvedContacts = contacts
        }
        if let time = try? container.decode(FamilyPlayTime.self, forKey: .playTime) { value.playTime = time }
        self = value
    }
}

/// Today on the child's clock, as the server counted it: play time from synced sessions (other
/// computers included) and the extra time granted today.
public struct FamilyAllowanceDay: Decodable, Equatable, Sendable {
    public var date: String
    public var bonusMinutes: Int
    public var playedSeconds: Int

    public init(date: String, bonusMinutes: Int, playedSeconds: Int) {
        self.date = date
        self.bonusMinutes = bonusMinutes
        self.playedSeconds = playedSeconds
    }

    enum CodingKeys: String, CodingKey { case date, bonusMinutes, playedSeconds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        bonusMinutes = max(0, (try? container.decode(Int.self, forKey: .bonusMinutes)) ?? 0)
        // Seconds may come with a fraction.
        playedSeconds = max(0, Int((try? container.decode(Double.self, forKey: .playedSeconds)) ?? 0))
    }
}

/// What GET me/family/restrictions answers (and signs): whether any limit applies, and which.
public struct FamilyStatus: Decodable, Equatable, Sendable {
    public var userId: String
    /// A child in a family: limits apply.
    public var restricted: Bool
    public var familyId: String?
    /// "manager", "parent", "adult" or "child".
    public var role: String?
    public var restrictions: FamilyRestrictions?
    public var today: FamilyAllowanceDay?
    public var issuedAt: Date

    public init(userId: String, restricted: Bool, familyId: String?, role: String?, restrictions: FamilyRestrictions?, today: FamilyAllowanceDay?, issuedAt: Date) {
        self.userId = userId
        self.restricted = restricted
        self.familyId = familyId
        self.role = role
        self.restrictions = restrictions
        self.today = today
        self.issuedAt = issuedAt
    }

    /// The limits that apply: none when not restricted; the careful ones when restricted but
    /// the limits did not come.
    public var effectiveRestrictions: FamilyRestrictions? {
        restricted ? (restrictions ?? .careful()) : nil
    }

    enum CodingKeys: String, CodingKey { case userId, restricted, familyId, role, restrictions, today, issuedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        issuedAt = try container.decode(Date.self, forKey: .issuedAt)
        familyId = try? container.decode(String.self, forKey: .familyId)
        role = try? container.decode(String.self, forKey: .role)
        restrictions = try? container.decode(FamilyRestrictions.self, forKey: .restrictions)
        today = try? container.decode(FamilyAllowanceDay.self, forKey: .today)
        // Restricted unless it says otherwise and nothing says it is a child.
        restricted = (try? container.decode(Bool.self, forKey: .restricted)) ?? (restrictions != nil || role == "child")
    }
}

/// Any key, for the days of a week read one by one.
struct FamilyAnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
