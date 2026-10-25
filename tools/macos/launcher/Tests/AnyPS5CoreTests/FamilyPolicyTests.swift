import XCTest
@testable import AnyPS5Core

/// The family policy as AnyTogether's shared code has it (family.ts): the child's clock, age
/// ratings, today's allowance, and the play-time warnings while a game runs.
final class FamilyPolicyTests: XCTestCase {
    /// Monday 26 October 2026, 12:00 in Istanbul (09:00 UTC).
    static let noon = Date(timeIntervalSince1970: 1_793_005_200)

    static func playTime(enabled: Bool = true, _ days: [FamilyWeekday: FamilyDayPlan] = [:], zone: String = "Europe/Istanbul", action: FamilyLimitAction = .close, grace: Int = 3) -> FamilyPlayTime {
        var all: [FamilyWeekday: FamilyDayPlan] = [:]
        for day in FamilyWeekday.allCases { all[day] = days[day] ?? .anyTime }
        return FamilyPlayTime(enabled: enabled, days: all, timeZone: zone, whenLimitReached: action, graceMinutes: grace, notifyParents: true)
    }

    // MARK: Clock

    func testTheClockIsTheChilds() {
        let istanbul = FamilyPolicy.clock(Self.noon, timeZone: "Europe/Istanbul")
        XCTAssertEqual(istanbul, FamilyClock(date: "2026-10-26", weekday: .mon, minutes: 720, seconds: 43_200))
        let angeles = FamilyPolicy.clock(Self.noon, timeZone: "America/Los_Angeles")
        XCTAssertEqual(angeles.date, "2026-10-26")
        XCTAssertEqual(angeles.minutes, 2 * 60, "02:00 on summer time")
        // 21:30 UTC on Sunday is already Monday in Istanbul.
        let late = Date(timeIntervalSince1970: 1_793_005_200 - 11.5 * 3600)
        XCTAssertEqual(FamilyPolicy.clock(late, timeZone: "Europe/Istanbul").weekday, .mon)
        XCTAssertEqual(FamilyPolicy.clock(late, timeZone: "UTC").weekday, .sun)
        XCTAssertEqual(FamilyPolicy.clock(late, timeZone: "Not/AZone").weekday, .sun, "an unknown zone reads as UTC")
    }

    // MARK: Age ratings

    func testTheRegionsRatingElseTheDefault() {
        let levels = ["default": 16, "US": 13, "DE": 12]
        XCTAssertEqual(FamilyPolicy.ageLevel(levels, region: "US"), 13)
        XCTAssertEqual(FamilyPolicy.ageLevel(levels, region: "TR"), 16)
        XCTAssertEqual(FamilyPolicy.ageLevel(levels, region: "default"), 16)
        XCTAssertNil(FamilyPolicy.ageLevel(["US": 13], region: "TR"))
        XCTAssertNil(FamilyPolicy.ageLevel(nil, region: "TR"))
    }

    func testWhetherAGameMayBePlayed() {
        var rules = FamilyRestrictions.careful()
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: ["default": 18]), .allowed, "no age limit")
        rules.ageLimit = 12
        rules.ageRegion = "DE"
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: ["default": 16, "DE": 12]), .allowed)
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: ["default": 16]), .age)
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: nil), .allowed, "unknown ratings allowed")
        rules.unknownAge = .block
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: nil), .unknown)
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: [:]), .unknown)
        rules.allowedTitles = ["PPSA01234"]
        XCTAssertEqual(FamilyPolicy.titleVerdict(rules, titleId: "PPSA01234", levels: ["default": 18]), .allowed, "a parent said yes")
    }

    // MARK: Allowance

    func testNoLimitsWhenPlayTimeIsOff() {
        let allowance = FamilyPolicy.allowance(Self.playTime(enabled: false, [.mon: FamilyDayPlan(limitMinutes: 0, from: nil, until: nil)]), now: Self.noon, playedSeconds: 9999, bonusMinutes: 0)
        XCTAssertTrue(allowance.allowed)
        XCTAssertNil(allowance.limitMinutes)
        XCTAssertNil(allowance.remainingSeconds)
        XCTAssertEqual(allowance.date, "2026-10-26")
    }

    func testTheDaysLimitWithExtraTime() {
        let time = Self.playTime([.mon: FamilyDayPlan(limitMinutes: 60, from: nil, until: nil)])
        let some = FamilyPolicy.allowance(time, now: Self.noon, playedSeconds: 1800, bonusMinutes: 15)
        XCTAssertEqual(some.limitMinutes, 75)
        XCTAssertEqual(some.remainingSeconds, 75 * 60 - 1800)
        XCTAssertTrue(some.allowed)
        let used = FamilyPolicy.allowance(time, now: Self.noon, playedSeconds: 3700, bonusMinutes: 0)
        XCTAssertEqual(used.remainingSeconds, 0)
        XCTAssertFalse(used.allowed)
        XCTAssertEqual(used.reason, .limit)
        let tuesday = FamilyPolicy.allowance(time, now: Self.noon.addingTimeInterval(86_400), playedSeconds: 0, bonusMinutes: 0)
        XCTAssertNil(tuesday.remainingSeconds, "Tuesday has no limit")
    }

    func testTheWindowOfTheDay() {
        let time = Self.playTime([.mon: FamilyDayPlan(limitMinutes: nil, from: "13:00", until: "18:00")])
        let before = FamilyPolicy.allowance(time, now: Self.noon, playedSeconds: 0, bonusMinutes: 0)
        XCTAssertFalse(before.allowed)
        XCTAssertEqual(before.reason, .window)
        XCTAssertEqual(before.remainingSeconds, 0)
        let inside = FamilyPolicy.allowance(time, now: Self.noon.addingTimeInterval(2 * 3600), playedSeconds: 0, bonusMinutes: 0)
        XCTAssertTrue(inside.allowed)
        XCTAssertEqual(inside.remainingSeconds, 4 * 3600, "until 18:00")
        let atTheEnd = FamilyPolicy.allowance(time, now: Self.noon.addingTimeInterval(6 * 3600), playedSeconds: 0, bonusMinutes: 0)
        XCTAssertFalse(atTheEnd.allowed, "until is not inside")
    }

    func testTheLimitAndTheWindowTogether() {
        let time = Self.playTime([.mon: FamilyDayPlan(limitMinutes: 30, from: "11:00", until: "12:10")])
        let soon = FamilyPolicy.allowance(time, now: Self.noon, playedSeconds: 0, bonusMinutes: 0)
        XCTAssertEqual(soon.remainingSeconds, 600, "the window ends first")
        let spent = FamilyPolicy.allowance(time, now: Self.noon, playedSeconds: 1800, bonusMinutes: 0)
        XCTAssertEqual(spent.reason, .limit)
        let outside = FamilyPolicy.allowance(time, now: Self.noon.addingTimeInterval(3600), playedSeconds: 1800, bonusMinutes: 0)
        XCTAssertEqual(outside.reason, .window, "the window is told first")
    }

    // MARK: Played today

    static func status(issuedAt: Date, date: String = "2026-10-26", played: Int = 600, bonus: Int = 0) -> FamilyStatus {
        FamilyStatus(userId: "u1", restricted: true, familyId: "f1", role: "child", restrictions: .careful(),
                     today: FamilyAllowanceDay(date: date, bonusMinutes: bonus, playedSeconds: played), issuedAt: issuedAt)
    }

    func testPlayedTodayAddsWhatTheServerDoesNotKnowYet() {
        let issued = Self.noon.addingTimeInterval(-3600)
        let records = [
            // Ended before the status: the server counted it.
            FamilyPlayRecord(id: "a", titleId: "PPSA01234", startedAt: issued.addingTimeInterval(-1200), endedAt: issued.addingTimeInterval(-600), queued: true),
            // Ended after it: not in it yet.
            FamilyPlayRecord(id: "b", titleId: "PPSA01234", startedAt: issued.addingTimeInterval(600), endedAt: issued.addingTimeInterval(900), queued: true),
            // Ended before it, but still waiting in the outbox.
            FamilyPlayRecord(id: "c", titleId: "PPSA01234", startedAt: issued.addingTimeInterval(-500), endedAt: issued.addingTimeInterval(-400), queued: true),
            // Played signed out: never goes up.
            FamilyPlayRecord(id: "d", titleId: "PPSA01234", startedAt: issued.addingTimeInterval(-300), endedAt: issued.addingTimeInterval(-250), queued: false),
        ]
        let played = FamilyPolicy.playedToday(status: Self.status(issuedAt: issued), records: records, pending: ["c"], running: nil, now: Self.noon, timeZone: "Europe/Istanbul")
        XCTAssertEqual(played, 600 + 300 + 100 + 50)
        let running = FamilyPolicy.playedToday(status: Self.status(issuedAt: issued), records: [], pending: [], running: Self.noon.addingTimeInterval(-120), now: Self.noon, timeZone: "Europe/Istanbul")
        XCTAssertEqual(running, 720, "the game running now")
    }

    func testAnotherDayStartsFromNothing() {
        let issued = Self.noon.addingTimeInterval(-3600)
        // The status was for Monday; on Tuesday its seconds and extra time are yesterday's.
        let tuesday = Self.noon.addingTimeInterval(86_400)
        XCTAssertEqual(FamilyPolicy.playedToday(status: Self.status(issuedAt: issued, played: 3000), records: [], pending: [], running: nil, now: tuesday, timeZone: "Europe/Istanbul"), 0)
        XCTAssertEqual(FamilyPolicy.bonusToday(status: Self.status(issuedAt: issued, bonus: 30), now: tuesday, timeZone: "Europe/Istanbul"), 0)
        XCTAssertEqual(FamilyPolicy.bonusToday(status: Self.status(issuedAt: issued, bonus: 30), now: Self.noon, timeZone: "Europe/Istanbul"), 30)
        // A session over midnight counts only its part after it.
        let midnight = Self.noon.addingTimeInterval(12 * 3600)
        let late = FamilyPlayRecord(id: "e", titleId: "PPSA01234", startedAt: midnight.addingTimeInterval(-1800), endedAt: midnight.addingTimeInterval(600), queued: false)
        XCTAssertEqual(FamilyPolicy.playedToday(status: Self.status(issuedAt: issued), records: [late], pending: [], running: nil, now: midnight.addingTimeInterval(3600), timeZone: "Europe/Istanbul"), 600)
        let running = FamilyPolicy.playedToday(status: Self.status(issuedAt: issued, played: 0), records: [], pending: [], running: midnight.addingTimeInterval(-60), now: midnight.addingTimeInterval(60), timeZone: "Europe/Istanbul")
        XCTAssertEqual(running, 60)
    }

    // MARK: While a game runs

    func testWarningsThenTheNoticeThenTheGameCloses() {
        var timer = FamilyPlayTimer(action: .close, graceMinutes: 2)
        let start = Self.noon
        XCTAssertEqual(timer.tick(remaining: 3600, allowed: true, now: start), [])
        XCTAssertEqual(timer.tick(remaining: 600, allowed: true, now: start), [.warn(minutes: 10)])
        XCTAssertEqual(timer.tick(remaining: 590, allowed: true, now: start), [], "once")
        XCTAssertEqual(timer.tick(remaining: 60, allowed: true, now: start), [.warn(minutes: 1)])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start), [.limitReached(closesAt: start.addingTimeInterval(120))])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start.addingTimeInterval(60)), [])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start.addingTimeInterval(120)), [.quit], "a gentle quit first, to save")
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start.addingTimeInterval(130)), [])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start.addingTimeInterval(120 + FamilyPlayTimer.forceAfter)), [.forceQuit])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: start.addingTimeInterval(400)), [])
    }

    func testStartingWithLittleLeftSaysHowLittle() {
        var timer = FamilyPlayTimer(action: .close, graceMinutes: 3)
        XCTAssertEqual(timer.tick(remaining: 290, allowed: true, now: Self.noon), [.warn(minutes: 5)])
        XCTAssertEqual(timer.tick(remaining: 45, allowed: true, now: Self.noon), [.warn(minutes: 1)])
        var short = FamilyPlayTimer(action: .close, graceMinutes: 3)
        XCTAssertEqual(short.tick(remaining: 50, allowed: true, now: Self.noon), [.warn(minutes: 1)], "only the last warning")
    }

    func testNotifyOnlyTells() {
        var timer = FamilyPlayTimer(action: .notify, graceMinutes: 3)
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: Self.noon), [.limitReached(closesAt: nil)])
        XCTAssertEqual(timer.tick(remaining: 0, allowed: false, now: Self.noon.addingTimeInterval(3600)), [], "never closes")
    }

    func testExtraTimeOrANewDayLiftsTheNotice() {
        var timer = FamilyPlayTimer(action: .close, graceMinutes: 3)
        _ = timer.tick(remaining: 0, allowed: false, now: Self.noon)
        XCTAssertEqual(timer.tick(remaining: 1800, allowed: true, now: Self.noon.addingTimeInterval(30)), [.resumed])
        XCTAssertEqual(timer.tick(remaining: 1800, allowed: true, now: Self.noon.addingTimeInterval(400)), [], "the close was called off")
        XCTAssertEqual(timer.tick(remaining: 600, allowed: true, now: Self.noon.addingTimeInterval(500)), [.warn(minutes: 10)], "warned again for the new time")
        XCTAssertEqual(timer.tick(remaining: nil, allowed: true, now: Self.noon.addingTimeInterval(600)), [], "no limit at all")
    }
}
