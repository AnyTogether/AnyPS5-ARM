import XCTest
@testable import AnyPS5Core

/// A tester's feedback of 11 November 2026 on AnyPS5 Desktop (Slick Daddy), the parts under the
/// Mac launcher's screens: what a paired device is, the countries a profile can name, and how to
/// get the tools Update from Git misses.
final class SlickFeedbackCoreTests: XCTestCase {
    func testAPairedDevicesKindIsReadFromItsName() {
        XCTAssertEqual(PhoneLabel("Android · Web").kind, .android)
        XCTAssertTrue(PhoneLabel("Android · Web").isBrowser)
        XCTAssertEqual(PhoneLabel("Android · Web").browserDevice, "Android")
        XCTAssertEqual(PhoneLabel("iPhone · Web").kind, .iPhone)
        XCTAssertEqual(PhoneLabel("iPad · Web").kind, .iPad)
        XCTAssertEqual(PhoneLabel("iPad · Web").browserDevice, "iPad")
        XCTAssertEqual(PhoneLabel("Phone · Web").kind, .browser, "a browser on a device its User-Agent did not name")
        XCTAssertNil(PhoneLabel("Phone · Web").browserDevice)
        XCTAssertEqual(PhoneLabel("Utku's iPhone").kind, .iPhone)
        XCTAssertFalse(PhoneLabel("Utku's iPhone").isBrowser)
        XCTAssertEqual(PhoneLabel("iPod touch").kind, .iPhone)
        XCTAssertEqual(PhoneLabel("Pixel 8").kind, .phone, "the name says nothing about its system: no guess")
        XCTAssertEqual(PhoneLabel("My Android").kind, .android)
        // What BrowserPadAccess names a browser pad is what the label takes apart.
        XCTAssertTrue(BrowserPadAccess.deviceName(userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8)").hasSuffix(PhoneLabel.browserSuffix))
    }

    func testTheCountriesAreTheServersAndNamedInTheLanguage() throws {
        XCTAssertEqual(Countries.codes.count, 249)
        XCTAssertEqual(Set(Countries.codes).count, 249)
        XCTAssertTrue(Countries.codes.allSatisfy { $0.count == 2 && $0 == $0.uppercased() })
        XCTAssertTrue(Countries.isKnown("tr"))
        XCTAssertFalse(Countries.isKnown("TRfgggg"), "what the old text field took")
        XCTAssertFalse(Countries.isKnown("XK"), "not one the server takes")
        let turkish = Locale(identifier: "tr_TR"), english = Locale(identifier: "en_US")
        XCTAssertEqual(Countries.name("DE", in: turkish), "Almanya")
        XCTAssertEqual(Countries.name("DE", in: english), "Germany")
        XCTAssertEqual(Countries.name("tr", in: turkish), "Türkiye")
        XCTAssertEqual(Countries.flag("TR"), "🇹🇷")
        XCTAssertEqual(Countries.flag("x"), "")
        let all = Countries.all(in: turkish)
        XCTAssertEqual(all.count, 249)
        // In Turkish's own order: Ç after C, İ after I.
        let names = all.map(\.name)
        let germany = try XCTUnwrap(names.firstIndex(of: "Almanya")), denmark = try XCTUnwrap(names.firstIndex(of: "Danimarka"))
        let cedilla = try XCTUnwrap(names.firstIndex { $0.hasPrefix("Ç") }, "a country whose Turkish name begins with Ç")
        XCTAssertLessThan(germany, cedilla)
        XCTAssertLessThan(cedilla, denmark)
    }

    func testASearchFindsACountryByNameWithoutAccentsOrCapitalsAndByCode() {
        let turkish = Countries.all(in: Locale(identifier: "tr_TR"))
        XCTAssertEqual(Countries.search("", in: turkish).count, 249)
        XCTAssertEqual(Countries.search("alman", in: turkish).map(\.code), ["DE"])
        XCTAssertTrue(Countries.search("turkiye", in: turkish).map(\.code).contains("TR"), "no accents typed")
        XCTAssertTrue(Countries.search("TÜRKİYE", in: turkish).map(\.code).contains("TR"), "Turkish capitals")
        XCTAssertTrue(Countries.search("ISPANYA", in: turkish).map(\.code).contains("ES"), "a plain capital I for İspanya")
        XCTAssertTrue(Countries.search("germany", in: turkish).map(\.code).contains("DE"), "the English name finds it too")
        XCTAssertEqual(Countries.search("tr", in: turkish).first?.code, "TR", "the code typed comes first")
        XCTAssertEqual(Countries.search("qqqq", in: turkish), [])
    }

    func testEveryMissingToolHasAWayToGetIt() {
        let brew = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let nothing = DevTools()
        XCTAssertEqual(nothing.missing, ["Xcode Command Line Tools", "Git", "CMake", "Ninja"])
        let fixes = nothing.fixes(homebrew: brew)
        XCTAssertEqual(fixes.map(\.id), ["xcode", "brew"])
        XCTAssertEqual(fixes[0].command, "xcode-select --install")
        XCTAssertNil(fixes[0].program, "Apple's installer is copied, never run for the user")
        // Git comes with the Command Line Tools: Homebrew is not asked for it.
        XCTAssertEqual(fixes[1].names, ["CMake", "Ninja"])
        XCTAssertEqual(fixes[1].command, "brew install cmake ninja")
        XCTAssertEqual(fixes[1].program, brew)
        XCTAssertEqual(fixes[1].arguments, ["install", "cmake", "ninja"])
        // Everything a fix installs is something missing, and everything missing has a fix.
        XCTAssertEqual(Set(fixes.flatMap(\.names)), Set(["Xcode Command Line Tools", "CMake", "Ninja"]))

        // Without Homebrew: its site first, the command still there to copy, nothing to run.
        let bare = nothing.fixes(homebrew: nil)
        XCTAssertEqual(bare.map(\.id), ["xcode", "homebrew", "brew"])
        XCTAssertEqual(bare[1].link, DevTools.homebrewSite)
        XCTAssertNil(bare[1].command)
        XCTAssertNil(bare[2].program)

        let developer = URL(fileURLWithPath: "/Library/Developer/CommandLineTools")
        let onlyNinja = DevTools(developer: developer, git: URL(fileURLWithPath: "/usr/bin/git"), cmake: URL(fileURLWithPath: "/opt/homebrew/bin/cmake"))
        XCTAssertEqual(onlyNinja.fixes(homebrew: brew).map(\.command), ["brew install ninja"])
        let noGit = DevTools(developer: developer, cmake: URL(fileURLWithPath: "/c"), ninja: URL(fileURLWithPath: "/n"))
        XCTAssertEqual(noGit.fixes(homebrew: brew).map(\.command), ["brew install git"])
        let all = DevTools(developer: developer, git: URL(fileURLWithPath: "/g"), cmake: URL(fileURLWithPath: "/c"), ninja: URL(fileURLWithPath: "/n"))
        XCTAssertEqual(all.fixes(homebrew: brew), [])
    }

    func testHomebrewIsLookedForOnPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-brew-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let brew = folder.appendingPathComponent("brew")
        try Data("#!/bin/sh\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        XCTAssertEqual(DevTools.homebrew(environment: ["PATH": folder.path])?.path, brew.path)
    }
}
