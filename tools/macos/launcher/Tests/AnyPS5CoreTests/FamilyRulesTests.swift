import XCTest
@testable import AnyPS5Core

/// The family limits as AnyTogether sends them: read the way the server's `restrictionsOf` reads
/// them, so anything unknown or wrong falls back to the careful default.
final class FamilyRulesTests: XCTestCase {
    static func day(_ limit: Any = NSNull(), from: Any = NSNull(), until: Any = NSNull()) -> [String: Any] {
        ["limitMinutes": limit, "from": from, "until": until]
    }

    static func restrictions(_ change: (inout [String: Any]) -> Void = { _ in }) -> [String: Any] {
        var days: [String: Any] = [:]
        for name in ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] { days[name] = day() }
        var value: [String: Any] = [
            "friendRequests": "approved", "messages": "friends", "voiceChat": false, "sharePlay": false, "publicMatchmaking": false,
            "profileVisibility": "friends", "discovery": false, "communities": false, "mediaSharing": false,
            "ageLimit": NSNull(), "unknownAge": "allow", "ageRegion": "default", "allowedTitles": [String](), "approvedContacts": [String](),
            "playTime": ["enabled": false, "days": days, "timeZone": "Europe/Istanbul", "whenLimitReached": "close", "graceMinutes": 3, "notifyParents": true] as [String: Any],
        ]
        change(&value)
        return value
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder.together.decode(type, from: JSONSerialization.data(withJSONObject: json))
    }

    func testEverythingAsSentIsRead() throws {
        let rules = try Self.decode(FamilyRestrictions.self, Self.restrictions {
            $0["friendRequests"] = "friends_of_friends"
            $0["messages"] = "nobody"
            $0["voiceChat"] = true
            $0["ageLimit"] = 12
            $0["unknownAge"] = "block"
            $0["ageRegion"] = "TR"
            $0["allowedTitles"] = ["PPSA01234"]
            var time = $0["playTime"] as! [String: Any]
            var days = time["days"] as! [String: Any]
            days["sat"] = Self.day(120, from: "10:00", until: "20:30")
            time["days"] = days
            time["enabled"] = true
            time["whenLimitReached"] = "notify"
            time["graceMinutes"] = 5
            $0["playTime"] = time
        })
        XCTAssertEqual(rules.friendRequests, .friendsOfFriends)
        XCTAssertEqual(rules.messages, .nobody)
        XCTAssertTrue(rules.voiceChat)
        XCTAssertFalse(rules.sharePlay)
        XCTAssertEqual(rules.ageLimit, 12)
        XCTAssertEqual(rules.unknownAge, .block)
        XCTAssertEqual(rules.ageRegion, "TR")
        XCTAssertEqual(rules.allowedTitles, ["PPSA01234"])
        XCTAssertTrue(rules.playTime.enabled)
        XCTAssertEqual(rules.playTime.timeZone, "Europe/Istanbul")
        XCTAssertEqual(rules.playTime.whenLimitReached, .notify)
        XCTAssertEqual(rules.playTime.graceMinutes, 5)
        XCTAssertEqual(rules.playTime.days[.sat], FamilyDayPlan(limitMinutes: 120, from: "10:00", until: "20:30"))
        XCTAssertEqual(rules.playTime.days[.mon], .anyTime)
    }

    func testWhatIsMissingOrWrongFallsBackToTheDefault() throws {
        let rules = try Self.decode(FamilyRestrictions.self, [
            "friendRequests": "strangers", "voiceChat": "yes", "ageLimit": 150, "ageRegion": "tr", "allowedTitles": ["nope"],
            "playTime": ["enabled": true, "graceMinutes": 99, "timeZone": "Mars/Base", "whenLimitReached": "explode",
                         "days": ["mon": Self.day(60, from: "10:00"), "tue": Self.day(30, from: "18:00", until: "09:00"), "wed": Self.day(2000), "thu": ["from": NSNull(), "until": NSNull()], "fri": Self.day(45)]] as [String: Any],
        ] as [String: Any])
        let fallback = FamilyRestrictions.careful()
        XCTAssertEqual(rules.friendRequests, fallback.friendRequests)
        XCTAssertEqual(rules.voiceChat, false)
        XCTAssertNil(rules.ageLimit, "out of range")
        XCTAssertEqual(rules.ageRegion, "default", "regions are upper case")
        XCTAssertEqual(rules.allowedTitles, [], "not a title ID: the whole list falls back, like the server")
        XCTAssertTrue(rules.playTime.enabled, "the valid ones inside playTime are kept")
        XCTAssertEqual(rules.playTime.graceMinutes, 3)
        XCTAssertEqual(rules.playTime.timeZone, "UTC")
        XCTAssertEqual(rules.playTime.whenLimitReached, .close)
        XCTAssertEqual(rules.playTime.days[.mon], .anyTime, "from without until")
        XCTAssertEqual(rules.playTime.days[.tue], .anyTime, "until before from")
        XCTAssertEqual(rules.playTime.days[.wed], .anyTime, "more than a day")
        XCTAssertEqual(rules.playTime.days[.thu], .anyTime, "limitMinutes has to be there, null or a number")
        XCTAssertEqual(rules.playTime.days[.fri], FamilyDayPlan(limitMinutes: 45, from: nil, until: nil))
        XCTAssertEqual(rules.playTime.days[.sun], .anyTime, "missing")
    }

    func testTheCarefulDefaultIsTheServers() {
        let rules = FamilyRestrictions.careful()
        XCTAssertEqual(rules.friendRequests, .approved)
        XCTAssertEqual(rules.messages, .friends)
        XCTAssertFalse(rules.voiceChat || rules.sharePlay || rules.publicMatchmaking || rules.discovery || rules.communities || rules.mediaSharing)
        XCTAssertEqual(rules.unknownAge, .allow)
        XCTAssertFalse(rules.playTime.enabled)
        XCTAssertEqual(rules.playTime.graceMinutes, 3)
        XCTAssertTrue(rules.playTime.notifyParents)
        XCTAssertEqual(rules.playTime.days.count, 7)
    }

    func testAStatusForAChildAndForAnyoneElse() throws {
        let child = try Self.decode(FamilyStatus.self, [
            "userId": "u1", "restricted": true, "familyId": "f1", "role": "child", "restrictions": Self.restrictions(),
            "today": ["date": "2026-10-26", "weekday": "mon", "limitMinutes": 60, "bonusMinutes": 15, "playedSeconds": 1200, "from": NSNull(), "until": NSNull(),
                      "remainingSeconds": 3300, "allowed": true, "reason": NSNull()] as [String: Any],
            "issuedAt": "2026-10-26T09:00:00.000Z", "signed": "x.y.z",
        ] as [String: Any])
        XCTAssertTrue(child.restricted)
        XCTAssertEqual(child.role, "child")
        XCTAssertNotNil(child.restrictions)
        XCTAssertEqual(child.today?.date, "2026-10-26")
        XCTAssertEqual(child.today?.bonusMinutes, 15)
        XCTAssertEqual(child.today?.playedSeconds, 1200)
        XCTAssertEqual(child.issuedAt, Date(timeIntervalSince1970: 1_793_005_200))

        let adult = try Self.decode(FamilyStatus.self, [
            "userId": "u2", "restricted": false, "familyId": NSNull(), "role": NSNull(), "restrictions": NSNull(), "today": NSNull(), "issuedAt": "2026-10-26T09:00:00Z",
        ] as [String: Any])
        XCTAssertFalse(adult.restricted)
        XCTAssertNil(adult.restrictions)
        XCTAssertNil(adult.effectiveRestrictions)
    }

    func testARestrictedStatusWithoutItsLimitsGetsTheCarefulOnes() throws {
        let status = try Self.decode(FamilyStatus.self, ["userId": "u1", "restricted": true, "restrictions": NSNull(), "issuedAt": "2026-10-26T09:00:00Z"] as [String: Any])
        XCTAssertEqual(status.effectiveRestrictions, FamilyRestrictions.careful())
    }

    func testAGamesAgeRatingsAreReadFromItsParameters() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("family-game-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sce_sys"), withIntermediateDirectories: true)
        try Data([0x7F, 0x45, 0x4C, 0x46]).write(to: folder.appendingPathComponent("eboot.bin"))
        let parameters: [String: Any] = ["titleId": "PPSA01234", "ageLevel": ["default": 16, "US": 13, "DE": "12"], "localizedParameters": ["defaultLanguage": "en-US", "en-US": ["titleName": "Silksong"]]]
        try JSONSerialization.data(withJSONObject: parameters).write(to: folder.appendingPathComponent("sce_sys/param.json"))
        XCTAssertEqual(GameLibrary.inspect(folder)?.ageLevels, ["default": 16, "US": 13], "numbers only")
        try JSONSerialization.data(withJSONObject: ["titleId": "PPSA01234"]).write(to: folder.appendingPathComponent("sce_sys/param.json"))
        XCTAssertNil(GameLibrary.inspect(folder)?.ageLevels)
    }
}
