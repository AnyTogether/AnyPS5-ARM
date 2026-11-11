@testable import AnyPS5
import AnyPS5Core
import AppKit
import XCTest

/// A tester's feedback of 11 November 2026 on AnyPS5 Desktop (Slick Daddy), on the Mac: Update
/// from Git says how to get what it misses, Home's profile picture opens the other profiles, the
/// country is picked from a list by name, a server's refusal is said in the launcher's language,
/// and a paired device wears a sign of what it is.
@MainActor
final class SlickFeedbackTests: XCTestCase {
    private var saved = Language.english

    override func setUp() async throws {
        saved = T.language
    }

    override func tearDown() async throws {
        T.language = saved
    }

    // MARK: Update from Git

    func testMissingToolsGetACommandToCopyAnInstallAndCheckAgain() throws {
        let model = try LauncherFixture.model()
        T.language = .english
        let missing = DevTools()
        XCTAssertEqual(model.engineToolFixRows(missing).map(\.id), ["engineGitFixCopy-xcode", "engineGitFixLink-homebrew", "engineGitFixCopy-brew", "engineGitRecheck"],
                       "no Homebrew: its site, the commands to copy, nothing to run")
        model.engineGit.homebrew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let rows = model.engineToolFixRows(missing)
        XCTAssertEqual(rows.map(\.id), ["engineGitFixCopy-xcode", "engineGitFixCopy-brew", "engineGitFixRun-brew", "engineGitRecheck"])
        XCTAssertEqual(rows[0].detail, "xcode-select --install")
        XCTAssertEqual(rows[1].detail, "brew install cmake ninja")
        XCTAssertEqual(rows[1].title, "Copy the install command for CMake and Ninja")
        XCTAssertEqual(rows[2].title, "Install CMake and Ninja now")
        XCTAssertEqual(rows[3].title, "Check again")
        // Copy puts the command on the pasteboard and says so.
        guard case .action(_, let copy) = rows[1].kind else { return XCTFail("the command's row copies it") }
        copy()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "brew install cmake ninja")
        XCTAssertEqual(model.toast?.text, "Command copied. Paste it into a terminal.")
    }

    func testCheckAgainSaysWhatIsThereNowAndClearsAStoppedUpdate() throws {
        let model = try LauncherFixture.model()
        T.language = .turkish
        model.engineGit.failure = GitUpdateFailure(.missingTools(["Ninja"]))
        let developer = URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
        model.engineToolsFound(DevTools(developer: developer, git: URL(fileURLWithPath: "/g"), cmake: URL(fileURLWithPath: "/c")), homebrew: nil, announce: true)
        XCTAssertEqual(model.toast?.text, "Hâlâ eksik: Ninja")
        XCTAssertNotNil(model.engineGit.failure)
        model.engineToolsFound(DevTools(developer: developer, git: URL(fileURLWithPath: "/g"), cmake: URL(fileURLWithPath: "/c"), ninja: URL(fileURLWithPath: "/n")), homebrew: nil, announce: true)
        XCTAssertEqual(model.toast?.text, "Git'ten güncellemenin gerektirdiği her şey kurulu")
        XCTAssertNil(model.engineGit.failure, "the tool it stopped for is there now")
        XCTAssertEqual(model.engineGit.tools?.missing, [])
    }

    func testAnInstallThatFailedSaysToRunTheCommandInATerminal() throws {
        let model = try LauncherFixture.model()
        T.language = .english
        model.engineGit.installing = ["CMake", "Ninja"]
        model.engineToolsInstalled("CMake and Ninja", worked: false, stopped: false)
        XCTAssertNil(model.engineGit.installing)
        XCTAssertEqual(model.toast?.text, "Couldn't install CMake and Ninja. Copy the command and run it in a terminal.")
    }

    // MARK: Home's profile picture

    private func withProfiles() throws -> (AppModel, [LauncherProfile]) {
        let model = try LauncherFixture.model()
        let mira = model.profiles.add(name: "Mira", mode: .offline)
        let sol = model.profiles.add(name: "Sol", mode: .offline)
        model.profilesChanged()
        return (model, [mira, sol])
    }

    func testTheKeysReachThePictureAndItsListOfTheOtherProfiles() throws {
        let (model, others) = try withProfiles()
        XCTAssertEqual(model.switcherProfiles.map(\.id), others.map(\.id), "everyone but the profile playing")
        XCTAssertFalse(model.profileSwitcherShown)
        model.focus = .top(5)
        XCTAssertTrue(model.handle(.right))
        XCTAssertEqual(model.focus, .switcher(0), "past the last button: the picture")
        XCTAssertTrue(model.profileSwitcherShown, "its list opens with the focus")
        XCTAssertTrue(model.handle(.down))
        XCTAssertEqual(model.focus, .switcher(1))
        _ = model.handle(.down)
        _ = model.handle(.down)
        XCTAssertEqual(model.focus, .switcher(3), "Add Profile, the last row")
        _ = model.handle(.down)
        XCTAssertEqual(model.focus, .switcher(3))
        _ = model.handle(.up)
        _ = model.handle(.up)
        _ = model.handle(.up)
        XCTAssertEqual(model.focus, .switcher(0))
        _ = model.handle(.left)
        XCTAssertEqual(model.focus, .top(5))
        XCTAssertFalse(model.profileSwitcherShown)
    }

    func testBackAndEscCloseTheList() throws {
        let (model, _) = try withProfiles()
        model.focus = .switcher(1)
        XCTAssertTrue(model.handle(.back))
        XCTAssertEqual(model.focus, .tiles)
        XCTAssertFalse(model.profileSwitcherShown)
        // Opened by the pointer: Esc closes it before it asks to quit.
        model.hoverProfileSwitcher("picture", true)
        XCTAssertTrue(model.profileSwitcherShown)
        XCTAssertFalse(model.profileSwitcherHeld, "the pointer leaving closes it, no click needed")
        XCTAssertTrue(model.escape())
        XCTAssertFalse(model.profileSwitcherShown)
        XCTAssertNil(model.overlay, "not Quit AnyPS5?")
        // Opened by a click: held until a click elsewhere, which closes it.
        model.toggleProfileSwitcher()
        XCTAssertTrue(model.profileSwitcherHeld)
        model.closeProfileSwitcher()
        XCTAssertFalse(model.profileSwitcherShown)
        // A screen opened over it: it does not come back when that closes.
        model.toggleProfileSwitcher()
        model.open(.library)
        model.closeOverlay()
        XCTAssertFalse(model.profileSwitcherShown)
    }

    func testChoosingAProfileSwitchesToItAndTheLastRowAddsOne() throws {
        let (model, others) = try withProfiles()
        model.focus = .switcher(2)
        XCTAssertTrue(model.handle(.select))
        XCTAssertEqual(model.currentProfile?.id, others[1].id, "Sol plays now")
        XCTAssertEqual(model.focus, .tiles)
        XCTAssertFalse(model.profileSwitcherShown)
        XCTAssertFalse(model.switcherProfiles.contains { $0.id == others[1].id })
        model.focus = .switcher(model.switcherProfiles.count + 1)
        _ = model.handle(.select)
        XCTAssertEqual(model.overlay, .addProfile)
    }

    // MARK: Country

    func testTheCountryIsPickedFromAListByItsNameAndKeptAsItsCode() throws {
        let model = try LauncherFixture.model()
        T.language = .turkish
        var rows = model.countryRows()
        XCTAssertEqual(rows.map(\.id), ["together-country"])
        XCTAssertEqual(rows[0].detail, "Ülkeni listeden seç")
        guard case .action = rows[0].kind else { return XCTFail("no field to type a code in") }
        model.toggleCountryPicker()
        rows = model.countryRows()
        XCTAssertEqual(rows.count, 1 + 1 + 1 + 249, "the row, the search, None and every country")
        XCTAssertEqual(rows[1].id, "together-country-search")
        XCTAssertEqual(rows[2].title, "Yok")
        XCTAssertTrue(rows.contains { $0.id == "together-country-DE" && $0.title == "🇩🇪 Almanya" })
        model.searchCountries("alm")
        rows = model.countryRows()
        XCTAssertEqual(rows.map(\.id), ["together-country", "together-country-search", "together-country-DE"])
        model.searchCountries("qqqq")
        XCTAssertEqual(model.countryRows().last?.title, "“qqqq” ile eşleşen ülke yok")
        model.searchCountries("alm")
        guard case .action(_, let choose) = model.countryRows()[2].kind else { return XCTFail() }
        choose()
        XCTAssertEqual(model.profileDraft.country, "DE", "the two letters the server takes")
        rows = model.countryRows()
        XCTAssertEqual(rows.map(\.id), ["together-country"], "the list closed")
        XCTAssertEqual(rows[0].detail, "🇩🇪 Almanya")
        // None clears it.
        model.toggleCountryPicker()
        guard case .action(_, let none) = model.countryRows()[2].kind else { return XCTFail() }
        none()
        XCTAssertEqual(model.profileDraft.country, "")
        // In English the same code reads in English.
        T.language = .english
        model.profileDraft.country = "DE"
        XCTAssertEqual(model.countryRows()[0].detail, "🇩🇪 Germany")
    }

    // MARK: A refusal in the launcher's language

    private func problem(_ code: String, title: String = "country: a country code like TR or DE") throws -> TogetherProblem {
        try JSONDecoder().decode(TogetherProblem.self, from: Data(#"{"status":400,"code":"\#(code)","title":"\#(title)"}"#.utf8))
    }

    func testAServersRefusalIsNeverShownInItsEnglishInAnotherLanguage() throws {
        let model = try LauncherFixture.model()
        T.language = .turkish
        XCTAssertEqual(model.togetherMessage(try problem("bad_request")), "Bu kabul edilmedi. Girdiğini denetleyip yeniden dene.")
        XCTAssertEqual(model.togetherMessage(try problem("session_revoked")), "Oturumun sona erdi. Yeniden giriş yap.")
        XCTAssertEqual(model.togetherMessage(try problem("not_found")), "Bu artık yok.")
        XCTAssertEqual(model.togetherMessage(try problem("internal")), "AnyTogether'da bir sorun oldu. Biraz sonra yeniden dene.")
        XCTAssertEqual(model.togetherMessage(try problem("something_new", title: "A sentence in English")), "AnyTogether bunu yapamadı (something_new).")
        for code in ["bad_request", "unauthorized", "refresh_reused", "forbidden", "conflict", "full", "payload_too_large", "edit_limit"] {
            XCTAssertFalse(model.togetherMessage(try problem(code)).contains("country code"), code)
        }
        // The codes with words of their own keep them.
        XCTAssertEqual(model.togetherMessage(try problem("handle_taken")), T.text(.togetherHandleTaken))
        T.language = .english
        XCTAssertEqual(model.togetherMessage(try problem("bad_request")), "That wasn't accepted. Check what you entered and try again.")
        XCTAssertEqual(model.togetherMessage(try problem("something_new", title: "A sentence in English")), "A sentence in English", "English is the server's own language")
    }

    // MARK: Phones

    func testAPairedDeviceWearsItsKindAndABrowserPadIsNamedInTheLanguage() throws {
        _ = try LauncherFixture.model()
        T.language = .english
        XCTAssertEqual(AppModel.phoneTitle("Android · Web"), "Android browser")
        XCTAssertEqual(AppModel.phoneTitle("Phone · Web"), "Phone browser")
        XCTAssertEqual(AppModel.phoneTitle("Utku's iPhone"), "Utku's iPhone", "the phone app's own name stays")
        T.language = .turkish
        XCTAssertEqual(AppModel.phoneTitle("Android · Web"), "Android tarayıcısı")
        XCTAssertEqual(AppModel.phoneTitle("iPhone · Web"), "iPhone tarayıcısı")
        XCTAssertEqual(AppModel.phoneTitle("Phone · Web"), "Telefon tarayıcısı")
        XCTAssertFalse(AppModel.phoneTitle("Android · Web").contains("·"))
        XCTAssertEqual(AppModel.phoneSymbol("Android · Web"), AndroidGlyph.symbol)
        XCTAssertEqual(AppModel.phoneSymbol("iPhone · Web"), "iphone")
        XCTAssertEqual(AppModel.phoneSymbol("Utku's iPad"), "ipad")
        XCTAssertEqual(AppModel.phoneSymbol("Phone · Web"), "globe")
        XCTAssertEqual(AppModel.phoneSymbol("Pixel 8"), "smartphone")
        // The robot's head is drawn inside the box it is given.
        let box = CGRect(x: 0, y: 0, width: 20, height: 14)
        let drawn = AndroidGlyph().path(in: box).boundingRect
        XCTAssertFalse(drawn.isEmpty)
        XCTAssertTrue(box.insetBy(dx: -0.5, dy: -0.5).contains(drawn), "\(drawn)")
    }
}
