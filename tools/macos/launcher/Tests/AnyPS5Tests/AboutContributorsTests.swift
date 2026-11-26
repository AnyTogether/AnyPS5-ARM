@testable import AnyPS5
import AnyPS5Core
import XCTest

/// Settings › About's credits: the owner first, also with GitHub out of reach, then up to twelve
/// contributors, each face reached with the keys or the pad and opening that person's profile,
/// and See all on GitHub. AnyPS5 Desktop's about_contributors_test.dart.
@MainActor
final class AboutContributorsTests: XCTestCase {
    var opened: [URL] = []

    override func tearDown() {
        InputModeState.shared.preview(.keyboard)
        T.language = .english
    }

    func person(_ login: String, _ contributions: Int) -> GithubContributors.Person {
        GithubContributors.Person(login: login, avatar: "https://avatars.githubusercontent.com/\(login)",
                                  page: URL(string: "https://github.com/\(login)")!, contributions: contributions)
    }

    var team: [GithubContributors.Person] {
        [person("B-Howell", 119), person("UtkuHalis", 856), person("Lenny4250gh", 72), person("QguAr71", 1)]
    }

    /// The launcher in Settings › About, its contributors from `people` (nil: no source at all).
    func about(_ people: [GithubContributors.Person]?) async throws -> AppModel {
        let model = try LauncherFixture.model()
        model.openLink = { [weak self] in self?.opened.append($0) }
        if let people { model.contributorsSource = { people } }
        model.open(.settings)
        model.panelCategory = try XCTUnwrap(model.panelCategories().firstIndex { $0.id == "about" })
        for _ in 0..<200 where people != nil && model.contributors == nil { try await Task.sleep(for: .milliseconds(10)) }
        return model
    }

    func rows(_ model: AppModel) -> [PanelRow] { model.panelCategories()[model.panelCategory].rows }

    func gridIndex(_ model: AppModel) throws -> Int { try XCTUnwrap(rows(model).firstIndex { $0.id == "contributorsGrid" }, "no credits") }

    struct NotCredits: Error {}

    func credits(_ model: AppModel) throws -> PanelCredits {
        let index = try gridIndex(model)
        guard case .credits(let credits) = rows(model)[index].kind else { throw NotCredits() }
        return credits
    }

    /// The focus on the credits, as ↓ from the rows above brings it there.
    func focusCredits(_ model: AppModel) throws {
        model.panelInRows = true
        let index = try gridIndex(model)
        model.focusRow(index, in: rows(model))
    }

    func testWithoutGitHubTheOwnerIsThereAloneFirstAndOpensHisProfile() async throws {
        let model = try await about(nil)
        let ids = rows(model).map(\.id)
        XCTAssertFalse(ids.contains("author"), "the credits take Made by's place")
        let grid = try gridIndex(model)
        XCTAssertEqual(ids[grid + 1], "contributorsAll")
        XCTAssertEqual(ids[grid + 2], "github")
        let credits = try credits(model)
        XCTAssertEqual(credits.owner.name, "Utku Halis")
        XCTAssertEqual(credits.owner.page, URL(string: "https://github.com/utkuhalis"))
        XCTAssertNil(credits.owner.avatar, "his initial until GitHub answers")
        XCTAssertEqual(credits.people, [])
        XCTAssertTrue(rows(model)[grid].focusable, "the keys and the pad reach it")
        try focusCredits(model)
        XCTAssertTrue(model.panelCommand(.select))
        XCTAssertEqual(opened.last, URL(string: "https://github.com/utkuhalis"))
    }

    func testGitHubAnsweringNoOneLeavesTheOwnerAloneToo() async throws {
        let model = try await about([])
        XCTAssertEqual(try credits(model).owner.name, "Utku Halis")
        XCTAssertEqual(try credits(model).people, [])
    }

    func testTheOwnerIsTakenOutOfTheListAndShownFirstWithGitHubsPicture() async throws {
        let model = try await about(team)
        let credits = try credits(model)
        XCTAssertEqual(credits.owner.name, "Utku Halis", "his name, not his login")
        XCTAssertEqual(credits.owner.avatar, "https://avatars.githubusercontent.com/UtkuHalis")
        XCTAssertEqual(credits.owner.contributions, 856)
        XCTAssertEqual(credits.people.map(\.name), ["B-Howell", "Lenny4250gh", "QguAr71"], "GitHub's order")
        XCTAssertEqual(credits.faces.first, credits.owner)
    }

    func testAtMostTwelveOthersAndSeeAllOnGitHubHasTheRest() async throws {
        let model = try await about((0..<20).map { person("person\($0)", 100 - $0) })
        XCTAssertEqual(try credits(model).people.map(\.name), (0..<12).map { "person\($0)" })
        let all = try XCTUnwrap(rows(model).first { $0.id == "contributorsAll" })
        XCTAssertEqual(all.title, "See all on GitHub")
        XCTAssertEqual(all.detail, "github.com/AnyTogether/AnyPS5-Desktop/graphs/contributors")
        model.activate(all)
        XCTAssertEqual(opened.last, URL(string: "https://github.com/AnyTogether/AnyPS5-Desktop/graphs/contributors"))
    }

    func testCommitsAreCountedInTheLanguageShownOneAndMany() {
        _ = try? LauncherFixture.model()
        XCTAssertEqual(AppModel.commits(1), "1 commit")
        XCTAssertEqual(AppModel.commits(1180), "1,180 commits")
        T.language = Language(code: "de")
        XCTAssertEqual(AppModel.commits(1180), "1.180 Commits")
        XCTAssertEqual(T.text(.contributors), "Mitwirkende")
    }

    func testTheKeysGoFromFaceToFaceAndReturnOpensThatProfile() async throws {
        let model = try await about(team)
        InputModeState.shared.preview(.keyboard)
        try focusCredits(model)
        XCTAssertTrue(model.panelCommand(.right))
        XCTAssertEqual(try credits(model).selected, 1)
        XCTAssertTrue(model.panelCommand(.right))
        XCTAssertEqual(try credits(model).selected, 2)
        XCTAssertTrue(model.panelCommand(.select))
        XCTAssertEqual(opened.last, URL(string: "https://github.com/Lenny4250gh"))
        XCTAssertTrue(model.panelCommand(.left))
        XCTAssertTrue(model.panelCommand(.left))
        XCTAssertEqual(try credits(model).selected, 0)
        XCTAssertTrue(model.panelCommand(.select))
        XCTAssertEqual(opened.last, URL(string: "https://github.com/UtkuHalis"))
        XCTAssertEqual(model.panelRow, try gridIndex(model), "the focus stays on the credits")
        XCTAssertTrue(model.panelCommand(.down))
        XCTAssertEqual(rows(model)[model.panelRow].id, "contributorsAll", "↓ goes on to See all")
    }

    func testThePadStopsAtTheLastFaceAndLeftOnTheOwnerLeavesTheRows() async throws {
        let model = try await about(team)
        InputModeState.shared.preview(.pad)
        try focusCredits(model)
        for _ in 0..<4 { XCTAssertTrue(model.panelCommand(.right)) }
        XCTAssertEqual(try credits(model).selected, 3, "stops at the last face")
        XCTAssertTrue(model.panelInRows)
        XCTAssertTrue(model.panelCommand(.select))
        XCTAssertEqual(opened.last, URL(string: "https://github.com/QguAr71"))
        for _ in 0..<3 { XCTAssertTrue(model.panelCommand(.left)) }
        XCTAssertEqual(try credits(model).selected, 0)
        XCTAssertTrue(model.panelInRows)
        XCTAssertTrue(model.panelCommand(.left))
        XCTAssertFalse(model.panelInRows, "as from any other row")
    }

    func testAClickOnAFaceFocusesTheCreditsAndOpensThatProfile() async throws {
        let model = try await about(team)
        try credits(model).click(2)
        XCTAssertEqual(opened.last, URL(string: "https://github.com/Lenny4250gh"))
        XCTAssertEqual(model.panelRow, try gridIndex(model))
        XCTAssertTrue(model.panelInRows)
        XCTAssertEqual(try credits(model).selected, 2)
    }
}
