import Foundation

/// The date, weekday and time of day on the child's clock.
public struct FamilyClock: Equatable, Sendable {
    public let date: String
    public let weekday: FamilyWeekday
    public let minutes: Int
    public let seconds: Int

    public init(date: String, weekday: FamilyWeekday, minutes: Int, seconds: Int) {
        self.date = date
        self.weekday = weekday
        self.minutes = minutes
        self.seconds = seconds
    }
}

/// Whether the child may play a game: allowed, too old a rating, or an unknown rating blocked.
public enum FamilyVerdict: Equatable, Sendable {
    case allowed, age, unknown
}

/// How much the child may still play today: the server's `Allowance`.
public struct FamilyAllowance: Equatable, Sendable {
    public enum Reason: String, Sendable { case limit, window }

    public var date: String
    public var weekday: FamilyWeekday
    /// Today's limit with today's extra time; nil: no limit.
    public var limitMinutes: Int?
    public var bonusMinutes: Int
    public var playedSeconds: Int
    public var from: String?
    public var until: String?
    /// Seconds left before the limit or the window's end, whichever comes first; nil: no end.
    public var remainingSeconds: Int?
    public var allowed: Bool
    public var reason: Reason?
}

/// A game played on this Mac, kept until the server has it in a status: `queued` when it went
/// into AnyTogether's outbox (signed in), so a later status counts it.
public struct FamilyPlayRecord: Codable, Equatable, Sendable {
    public let id: String
    public let titleId: String
    public let startedAt: Date
    public let endedAt: Date
    public let queued: Bool

    public init(id: String, titleId: String, startedAt: Date, endedAt: Date, queued: Bool) {
        self.id = id
        self.titleId = titleId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.queued = queued
    }
}

/// Why a game may not start now.
public enum FamilyBlock: Equatable, Sendable {
    /// Rated above the child's limit (the rating that counts, when known).
    case age(Int?)
    /// No rating, and unknown ratings are blocked.
    case unknownAge
    /// Today's play time is used up.
    case limit
    /// Outside today's hours.
    case window(from: String?, until: String?)
    /// The kept status was changed or lost: nothing plays until the server is reached.
    case locked
}

/// The rules AnyTogether's shared code has (family.ts), the same line by line, so the launcher
/// and the server never disagree about what a child may do.
public enum FamilyPolicy {
    /// "07:30" as minutes of the day; nil when it is not a time like that.
    public static func clockMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard value.count == 5, parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hours = Int(parts[0]), let minutes = Int(parts[1]), (0 ... 23).contains(hours), (0 ... 59).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }

    /// "TR", "US" or "default".
    static func isRegion(_ value: String) -> Bool {
        value == "default" || (value.count == 2 && value.unicodeScalars.allSatisfy { ("A" ... "Z").contains($0) })
    }

    /// "PPSA01234": four capital letters and five digits.
    static func isTitleID(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        return scalars.count == 9 && scalars[..<4].allSatisfy { ("A" ... "Z").contains($0) } && scalars[4...].allSatisfy { ("0" ... "9").contains($0) }
    }

    static func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(identifier: "UTC")!
    }

    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone(identifier)
        return calendar
    }

    /// The date, weekday and minute of the day on a clock (`localClock`).
    public static func clock(_ now: Date, timeZone: String) -> FamilyClock {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        // Calendar weekdays start on Sunday (1).
        let weekdays: [FamilyWeekday] = [.sun, .mon, .tue, .wed, .thu, .fri, .sat]
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0, second = parts.second ?? 0
        return FamilyClock(date: String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1),
                           weekday: weekdays[((parts.weekday ?? 2) - 1) % 7],
                           minutes: hour * 60 + minute, seconds: hour * 3600 + minute * 60 + second)
    }

    /// The rating that counts for a region: the region's own, else the game's default; nil when
    /// the game has none (`ageLevelFor`).
    public static func ageLevel(_ levels: [String: Int]?, region: String) -> Int? {
        guard let levels else { return nil }
        if region != "default", let own = levels[region] { return own }
        return levels["default"]
    }

    /// `titleVerdict`.
    public static func titleVerdict(_ rules: FamilyRestrictions, titleId: String, levels: [String: Int]?) -> FamilyVerdict {
        if rules.allowedTitles.contains(titleId) || rules.ageLimit == nil { return .allowed }
        guard let level = ageLevel(levels, region: rules.ageRegion) else { return rules.unknownAge == .allow ? .allowed : .unknown }
        return level <= rules.ageLimit! ? .allowed : .age
    }

    /// How much the child may still play today (`allowance`).
    public static func allowance(_ playTime: FamilyPlayTime, now: Date, playedSeconds: Int, bonusMinutes: Int) -> FamilyAllowance {
        let clock = clock(now, timeZone: playTime.timeZone)
        let day = playTime.plan(clock.weekday)
        var result = FamilyAllowance(date: clock.date, weekday: clock.weekday, limitMinutes: nil, bonusMinutes: bonusMinutes, playedSeconds: playedSeconds,
                                     from: nil, until: nil, remainingSeconds: nil, allowed: true, reason: nil)
        guard playTime.enabled else { return result }
        let limitMinutes = day.limitMinutes.map { $0 + bonusMinutes }
        let left = limitMinutes.map { max(0, $0 * 60 - playedSeconds) }
        var windowLeft: Int?
        var inWindow = true
        if let from = day.from.flatMap(clockMinutes), let until = day.until.flatMap(clockMinutes) {
            inWindow = clock.seconds >= from * 60 && clock.seconds < until * 60
            windowLeft = inWindow ? until * 60 - clock.seconds : 0
        }
        let remaining: Int? = {
            guard let left else { return windowLeft }
            guard let windowLeft else { return left }
            return min(left, windowLeft)
        }()
        let reason: FamilyAllowance.Reason? = !inWindow ? .window : (left.map { $0 <= 0 } ?? false) ? .limit : nil
        result.limitMinutes = limitMinutes
        result.from = day.from
        result.until = day.until
        result.remainingSeconds = remaining
        result.allowed = reason == nil
        result.reason = reason
        return result
    }

    // MARK: Played today, on this Mac too

    /// Today on the child's clock, from its midnight to the next.
    static func today(_ now: Date, timeZone: String) -> DateInterval {
        let calendar = calendar(timeZone)
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    static func seconds(from start: Date, to end: Date, within day: DateInterval) -> Int {
        let from = max(start, day.start), until = min(end, day.end)
        return until > from ? Int(until.timeIntervalSince(from)) : 0
    }

    /// The seconds played today: the server's count when the status is for today, the games
    /// played on this Mac it does not have yet (ended after it was issued, still waiting in the
    /// outbox, or played signed out), and the game running now.
    public static func playedToday(status: FamilyStatus, records: [FamilyPlayRecord], pending: Set<String>, running: Date?, now: Date, timeZone: String) -> Int {
        let date = clock(now, timeZone: timeZone).date
        let day = today(now, timeZone: timeZone)
        var total = status.today.map { $0.date == date ? $0.playedSeconds : 0 } ?? 0
        for record in records where !record.queued || pending.contains(record.id) || record.endedAt > status.issuedAt {
            total += seconds(from: record.startedAt, to: record.endedAt, within: day)
        }
        if let running { total += seconds(from: running, to: now, within: day) }
        return total
    }

    /// Today's extra time: the status's, when it is for today.
    public static func bonusToday(status: FamilyStatus, now: Date, timeZone: String) -> Int {
        guard let today = status.today, today.date == clock(now, timeZone: timeZone).date else { return 0 }
        return today.bonusMinutes
    }
}

/// The warnings and the closing while a game runs, from the allowance read every tick: 10 and 1
/// minutes before the end (or how little is left at the start), then the notice; with "close"
/// a gentle quit after the grace period and a forced one only if the game does not go. Extra
/// time or a new day calls it all off.
public struct FamilyPlayTimer: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// About this many minutes left.
        case warn(minutes: Int)
        /// Time is up: the big notice; the game closes at `closesAt` (nil: it does not).
        case limitReached(closesAt: Date?)
        /// Ask the game to quit, so it can save.
        case quit
        /// It did not: stop it.
        case forceQuit
        /// More time came (or a new day): the notice goes, nothing closes.
        case resumed
    }

    /// Seconds between the gentle quit and the forced one.
    public static let forceAfter: TimeInterval = 20

    public let action: FamilyLimitAction
    public let graceMinutes: Int
    private var warnedTen = false
    private var warnedOne = false
    private var reached = false
    private var closesAt: Date?
    private var quitAt: Date?
    private var forced = false

    public init(action: FamilyLimitAction, graceMinutes: Int) {
        self.action = action
        self.graceMinutes = graceMinutes
    }

    public var limitReached: Bool { reached }

    public mutating func tick(remaining: Int?, allowed: Bool, now: Date) -> [Event] {
        var events: [Event] = []
        let over = !allowed || remaining == 0
        if !over {
            if reached {
                reached = false
                closesAt = nil
                quitAt = nil
                forced = false
                events.append(.resumed)
            }
            guard let remaining else {
                warnedTen = false
                warnedOne = false
                return events
            }
            if remaining > 600 { warnedTen = false }
            if remaining > 60 { warnedOne = false }
            if remaining <= 60 {
                if !warnedOne {
                    warnedOne = true
                    warnedTen = true
                    events.append(.warn(minutes: 1))
                }
            } else if remaining <= 600, !warnedTen {
                warnedTen = true
                events.append(.warn(minutes: Int((Double(remaining) / 60).rounded(.up))))
            }
            return events
        }
        if !reached {
            reached = true
            closesAt = action == .close ? now.addingTimeInterval(TimeInterval(graceMinutes * 60)) : nil
            return [.limitReached(closesAt: closesAt)]
        }
        if let closesAt, quitAt == nil, now >= closesAt {
            quitAt = now
            return [.quit]
        }
        if let quitAt, !forced, now >= quitAt.addingTimeInterval(FamilyPlayTimer.forceAfter) {
            forced = true
            return [.forceQuit]
        }
        return []
    }
}
