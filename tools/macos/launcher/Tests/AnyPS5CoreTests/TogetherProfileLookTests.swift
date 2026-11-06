import XCTest
@testable import AnyPS5Core

/// A profile's look (cover, accent, a Theme Hub theme it wears) and its showcase of up to six pins,
/// against the shapes AnyTogether sends, and an older server's without them.
final class TogetherProfileLookTests: TogetherSignedInCase {
    static let themeID = "01928c3e-7a4b-7c3d-9e2f-0a1b2c3d4e5f"

    static let theme: [String: Any] = [
        "id": themeID, "name": "Neon Nights", "colors": ["deep": "#0a0014", "middle": "#4a0e6b", "bright": "#ff5edb", "accent": "#ff4fd8"],
        "preview": "https://anytogether.test/api/v1/themes/\(themeID)/preview.webp?v=2", "thumb": "https://anytogether.test/api/v1/themes/\(themeID)/thumb.webp?v=2",
        "maker": ["handle": "ada", "displayName": "Ada"],
    ]

    static func profile(cover: Any? = NSNull(), accent: Any? = NSNull(), theme: Any? = NSNull()) -> [String: Any] {
        var profile: [String: Any] = ["userId": "f1", "handle": "ayse", "displayName": "Ayşe", "avatar": NSNull(), "bio": NSNull(), "country": "TR", "friendship": "friends"]
        if let cover { profile["cover"] = cover }
        if let accent { profile["accent"] = accent }
        if let theme { profile["theme"] = theme }
        return profile
    }

    func decode(_ json: [String: Any]) throws -> TogetherProfile {
        try JSONDecoder.together.decode(TogetherProfile.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: Look

    /// A theme worn with no cover or accent of its own: its still behind the header, its accent,
    /// its deep and middle tones as the tint, and its name.
    func testAProfileWearingATheme() throws {
        let look = try decode(Self.profile(theme: Self.theme)).look
        XCTAssertEqual(look.theme?.id, Self.themeID)
        XCTAssertEqual(look.theme?.name, "Neon Nights")
        XCTAssertEqual(look.theme?.maker?.handle, "ada")
        XCTAssertEqual(look.picture, "https://anytogether.test/api/v1/themes/\(Self.themeID)/preview.webp?v=2")
        XCTAssertEqual(look.accentHex, "#ff4fd8")
        XCTAssertEqual(look.tint?.deep, "#0a0014")
        XCTAssertEqual(look.tint?.middle, "#4a0e6b")
        XCTAssertFalse(look.isPlain)
    }

    /// A cover and an accent picked on top of the theme win; the tint and the name stay.
    func testACoverAndAnAccentWinOverTheTheme() throws {
        let cover: [String: Any] = ["kind": "preset", "id": "sunset-grid", "url": "https://anytogether.test/api/v1/covers/sunset-grid.webp"]
        let look = try decode(Self.profile(cover: cover, accent: "gold", theme: Self.theme)).look
        XCTAssertEqual(look.cover?.kind, "preset")
        XCTAssertEqual(look.picture, "https://anytogether.test/api/v1/covers/sunset-grid.webp")
        XCTAssertEqual(look.accent, "gold")
        XCTAssertEqual(look.accentHex, "#ffcc5c")
        XCTAssertEqual(look.tint?.deep, "#0a0014")
    }

    /// The six accents AnyTogether offers, by name.
    func testTheAccents() {
        XCTAssertEqual(TogetherProfileLook.accents, ["blue": "#4f94ff", "mint": "#5cebbd", "coral": "#ff8066", "violet": "#a885ff", "gold": "#ffcc5c", "white": "#f0f0f0"])
        XCTAssertNil(TogetherProfileLook(cover: nil, accent: "pink", theme: nil).accentHex)
        XCTAssertEqual(TogetherProfileLook(cover: nil, accent: "mint", theme: nil).accentHex, "#5cebbd")
    }

    /// An older server sends none of them, and a shape this launcher does not expect is left out:
    /// the profile itself still reads.
    func testAnOlderServerOrABrokenLookLeavesTheProfileWhole() throws {
        let old = try decode(Self.profile(cover: nil, accent: nil, theme: nil))
        XCTAssertEqual(old.handle, "ayse")
        XCTAssertTrue(old.look.isPlain)
        XCTAssertNil(old.look.picture)
        XCTAssertNil(old.look.accentHex)
        XCTAssertNil(old.look.tint)
        let broken = try decode(Self.profile(cover: "sunset", accent: 7, theme: ["id": Self.themeID, "name": "No colours"]))
        XCTAssertEqual(broken.displayName, "Ayşe")
        XCTAssertTrue(broken.look.isPlain)
    }

    func testTheOwnProfileCarriesItsLook() async throws {
        var own = TogetherLevelTests.own()
        var profile = own["profile"] as! [String: Any]
        profile["accent"] = "violet"
        profile["theme"] = Self.theme
        own["profile"] = profile
        FakeTogether.handler = { _, _ in (200, own) }
        let mine = try await client.myProfile()
        XCTAssertEqual(mine.look.accent, "violet")
        XCTAssertEqual(mine.look.theme?.id, Self.themeID)
        // Without them (an older server): plain.
        FakeTogether.handler = { _, _ in (200, TogetherLevelTests.own()) }
        let plain = try await client.myProfile()
        XCTAssertTrue(plain.look.isPlain)
    }

    /// PATCH /me/look with the theme's ID puts it on; null takes it off. What the server keeps comes back.
    func testWearingAThemeAndTakingItOff() async throws {
        FakeTogether.handler = { _, _ in (200, ["cover": NSNull(), "accent": NSNull(), "theme": Self.theme]) }
        let worn = try await client.setProfileTheme(Self.themeID)
        XCTAssertEqual(last(), "PATCH /api/v1/me/look")
        XCTAssertEqual(body()?["theme"] as? String, Self.themeID)
        XCTAssertEqual(body()?.count, 1)
        XCTAssertEqual(worn.theme?.name, "Neon Nights")
        FakeTogether.handler = { _, _ in (200, ["cover": NSNull(), "accent": NSNull(), "theme": NSNull()]) }
        let off = try await client.setProfileTheme(nil)
        XCTAssertTrue(body()?["theme"] is NSNull)
        XCTAssertNil(off.theme)
    }

    /// A theme that is not on the Hub (or an older server) is a plain failure.
    func testAThemeNotOnTheHubIsRefused() async throws {
        FakeTogether.handler = { _, _ in (400, ["code": "bad_request", "status": 400, "title": "theme: no such theme in the Theme Hub"]) }
        do {
            _ = try await client.setProfileTheme(Self.themeID)
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 400)
        }
    }

    /// The themes to choose from: the Hub's most liked first.
    func testPopularThemes() async throws {
        FakeTogether.handler = { _, _ in (200, ["themes": [TogetherThemesTests.detail()], "next": "24"]) }
        let themes = try await client.popularThemes()
        XCTAssertEqual(last(), "GET /api/v1/themes?sort=popular&limit=24")
        XCTAssertEqual(themes.map(\.id), [TogetherThemesTests.id])
        XCTAssertEqual(themes.first?.colors.accent, "#FF4FD8")
    }

    // MARK: Showcase

    static func trophy(_ id: Int, title: String = "PPSA01234") -> TogetherEarnedTrophy {
        TogetherEarnedTrophy(titleId: title, gameNames: ["en": "Stray"], trophyId: id, grade: "gold", hidden: false, texts: ["en": .init(name: "T\(id)")],
                             earnedAt: Date(timeIntervalSince1970: 1_800_000_000), rarity: nil, rarityLabel: nil)
    }

    static func game(_ title: String) -> TogetherShowcaseGame {
        TogetherShowcaseGame(titleId: title, names: ["en": title], iconUrl: nil, secondsPlayed: 60, trophiesEarned: 1, trophiesTotal: 10, progress: 10)
    }

    /// Six pins in all, trophies first: a showcase saved before the shared limit may hold more.
    func testAShowcaseShowsAtMostSixTrophiesFirst() {
        let mixed = TogetherShowcase(trophies: (0..<4).map { Self.trophy($0) }, games: ["A", "B", "C", "D"].map(Self.game)).shown
        XCTAssertEqual(mixed.trophies?.map(\.trophyId), [0, 1, 2, 3])
        XCTAssertEqual(mixed.games?.map(\.titleId), ["A", "B"])
        let trophies = TogetherShowcase(trophies: (0..<8).map { Self.trophy($0) }, games: [Self.game("A")]).shown
        XCTAssertEqual(trophies.trophies?.count, 6)
        XCTAssertEqual(trophies.games?.count, 0)
        // A part private to the reader stays private; the other part gets all six.
        let hidden = TogetherShowcase(trophies: nil, games: (0..<8).map { Self.game("G\($0)") }).shown
        XCTAssertNil(hidden.trophies)
        XCTAssertEqual(hidden.games?.count, 6)
        XCTAssertEqual(TogetherShowcase.limit, 6)
    }

    /// The editor: one count for both, nothing more once six are pinned, unpinning frees a place.
    func testPinsStopAtSix() {
        var pins = TogetherShowcasePins()
        XCTAssertEqual(pins.count, 0)
        for id in 0..<4 { XCTAssertTrue(pins.toggle(trophy: Self.trophy(id))) }
        XCTAssertTrue(pins.toggle(game: "A"))
        XCTAssertTrue(pins.toggle(game: "B"))
        XCTAssertEqual(pins.count, 6)
        XCTAssertTrue(pins.isFull)
        XCTAssertFalse(pins.toggle(game: "C"))
        XCTAssertFalse(pins.toggle(trophy: Self.trophy(9)))
        XCTAssertFalse(pins.contains(game: "C"))
        XCTAssertEqual(pins.count, 6)
        // Unpinning is always allowed, and frees a place.
        XCTAssertTrue(pins.toggle(trophy: Self.trophy(1)))
        XCTAssertFalse(pins.contains(trophy: Self.trophy(1)))
        XCTAssertFalse(pins.isFull)
        XCTAssertTrue(pins.toggle(game: "C"))
        XCTAssertEqual(pins.games, ["A", "B", "C"])
        XCTAssertEqual(pins.trophies.map(\.trophyId), [0, 2, 3])
        // The same trophy number in another game is another trophy.
        XCTAssertFalse(pins.contains(trophy: Self.trophy(0, title: "PPSA09999")))
    }

    /// The editor starts from what is pinned now, kept to six (trophies first).
    func testPinsStartFromTheShowcase() {
        let pins = TogetherShowcasePins(TogetherShowcase(trophies: (0..<5).map { Self.trophy($0) }, games: ["A", "B", "C"].map(Self.game)))
        XCTAssertEqual(pins.trophies.map(\.trophyId), [0, 1, 2, 3, 4])
        XCTAssertEqual(pins.games, ["A"])
        XCTAssertTrue(pins.isFull)
        let none = TogetherShowcasePins(TogetherShowcase(trophies: nil, games: nil))
        XCTAssertEqual(none.count, 0)
    }

    /// PUT /me/showcase sends both lists (one left out would keep the stored one, and count).
    func testSavingTheShowcaseSendsBothLists() async throws {
        FakeTogether.handler = { _, _ in
            (200, ["trophies": [["titleId": "PPSA01234", "gameNames": ["en": "Stray"], "trophyId": 7, "grade": "gold", "hidden": false, "texts": ["en": ["name": "Bound"]],
                                 "earnedAt": "2026-10-23T21:00:00.000Z", "rarity": NSNull(), "rarityLabel": NSNull()]],
                   "games": []])
        }
        var pins = TogetherShowcasePins()
        pins.toggle(trophy: Self.trophy(7))
        let saved = try await client.setShowcase(pins)
        XCTAssertEqual(last(), "PUT /api/v1/me/showcase")
        let sent = try XCTUnwrap(body())
        XCTAssertEqual((sent["trophies"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((sent["trophies"] as? [[String: Any]])?.first?["titleId"] as? String, "PPSA01234")
        XCTAssertEqual((sent["trophies"] as? [[String: Any]])?.first?["trophyId"] as? Int, 7)
        XCTAssertEqual(sent["games"] as? [String], [])
        XCTAssertEqual(saved.trophies?.first?.name(in: "en"), "Bound")
        XCTAssertEqual(saved.games?.count, 0)
        // Nothing pinned: both lists empty, both sent.
        _ = try await client.setShowcase(TogetherShowcasePins())
        XCTAssertEqual((body()?["trophies"] as? [Any])?.count, 0)
        XCTAssertEqual((body()?["games"] as? [Any])?.count, 0)
    }

    /// More than six (a server that counts what is stored) is a plain failure.
    func testTooManyPinsRefused() async throws {
        FakeTogether.handler = { _, _ in (400, ["code": "bad_request", "status": 400, "title": "showcase: up to six pins, trophies and games together"]) }
        do {
            _ = try await client.setShowcase(TogetherShowcasePins())
            XCTFail("no error")
        } catch let problem as TogetherProblem {
            XCTAssertEqual(problem.status, 400)
        }
    }

    // MARK: Hub

    /// Only the server's Hub lists themes by the ID a profile can wear; the GitHub folder's do not.
    func testTheHubSaysWhereAThemeCameFrom() async throws {
        FakeTogether.handler = { request, _ in request.url!.host == "anytogether.test" ? (200, TogetherThemesTests.index(["Neon"])) : (200, TogetherThemesTests.index(["Old"])) }
        let server = ThemeHub.base(onServer: client.base)
        let github = URL(string: "https://raw.example.test/hub/")!
        let fromServer = try await ThemeHub.themes(from: [server, github], session: client.session)
        XCTAssertEqual(fromServer.first?.source, server)
        FakeTogether.handler = { request, _ in request.url!.host == "anytogether.test" ? (200, ["themes": []]) : (200, TogetherThemesTests.index(["Old"])) }
        let fromGitHub = try await ThemeHub.themes(from: [server, github], session: client.session)
        XCTAssertEqual(fromGitHub.first?.source, github)
    }
}
