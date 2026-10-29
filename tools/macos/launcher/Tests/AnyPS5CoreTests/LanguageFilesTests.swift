@testable import AnyPS5Core
import XCTest

/// The language files' reading: a user folder before the built-in one, English as the fallback,
/// the "languageName" text (or an old file's "@meta" name), the console language from the file's
/// code and the placeholder rules of AnyLauncher-Port's check_translations.dart.
final class LanguageFilesTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("anyps5-languages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("builtin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("user"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ folder: String, _ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(folder).appendingPathComponent(name))
    }

    func folders() -> [URL] { [root.appendingPathComponent("user"), root.appendingPathComponent("builtin")] }

    func testFilesAreFoundAndListedEnglishFirstThenByName() throws {
        try write("builtin", "tr.json", #"{"languageName": "Türkçe", "back": "Geri"}"#)
        try write("builtin", "en.json", #"{"languageName": "English", "back": "Back", "games": "Games"}"#)
        try write("user", "de.json", #"{"languageName": "Deutsch", "back": "Zurück"}"#)
        try write("builtin", "notes.txt", "not a language")
        let languages = LanguageFiles.load(folders())
        XCTAssertEqual(languages.map(\.code), ["en", "de", "tr"])
        XCTAssertEqual(languages.map(\.name), ["English", "Deutsch", "Türkçe"])
        XCTAssertEqual(languages.map(\.consoleLanguage), [1, 4, 19])
        let texts = LanguageTexts(languages)
        XCTAssertEqual(texts.text("back", in: "de"), "Zurück")
        XCTAssertEqual(texts.text("games", in: "de"), "Games", "a missing text is the English one")
        XCTAssertEqual(texts.text("games", in: "xx"), "Games", "a language without a file is English")
        XCTAssertEqual(texts.text("nowhere", in: "tr"), "nowhere", "a key English lacks shows as itself")
    }

    func testTheUserFolderComesBeforeTheBuiltInFileOfItsCode() throws {
        try write("builtin", "en.json", #"{"languageName": "English", "back": "Back"}"#)
        try write("builtin", "tr.json", #"{"languageName": "Türkçe", "back": "Geri"}"#)
        try write("user", "tr.json", #"{"languageName": "Türkçe (deneme)", "back": "Geri dön"}"#)
        let texts = LanguageTexts(LanguageFiles.load(folders()))
        XCTAssertEqual(texts.text("back", in: "tr"), "Geri dön")
        XCTAssertEqual(texts.language("tr")?.name, "Türkçe (deneme)")
    }

    func testABrokenFileIsLeftOutForTheNextOneOfItsCode() throws {
        try write("builtin", "en.json", #"{"languageName": "English", "back": "Back"}"#)
        try write("builtin", "tr.json", #"{"languageName": "Türkçe", "back": "Geri"}"#)
        try write("user", "tr.json", #"{"back": "Geri""#)
        try write("user", "fr.json", #"["not", "an", "object"]"#)
        var log: [String] = []
        let languages = LanguageFiles.load(folders()) { log.append($0) }
        XCTAssertEqual(languages.map(\.code), ["en", "tr"])
        XCTAssertEqual(LanguageTexts(languages).text("back", in: "tr"), "Geri")
        XCTAssertEqual(log.count, 2)
    }

    func testWithoutItsNameALanguageIsListedByItsCode() throws {
        let file = try LanguageFiles.parse(Data(#"{"back": "Tillbaka", "count": 3}"#.utf8), code: "sv")
        XCTAssertEqual(file.name, "sv")
        XCTAssertEqual(file.consoleLanguage, 13, "Swedish, from the code")
        XCTAssertEqual(file.texts, ["back": "Tillbaka"], "a value that is not a text is left out")
        let unknown = try LanguageFiles.parse(Data(#"{"languageName": "Esperanto"}"#.utf8), code: "eo")
        XCTAssertEqual(unknown.name, "Esperanto")
        XCTAssertEqual(unknown.consoleLanguage, 1, "a code the console does not know starts games in English")
    }

    func testTheConsoleLanguageComesFromTheCode() {
        XCTAssertEqual(ConsoleLanguage.forLocale("tr"), 19)
        XCTAssertEqual(ConsoleLanguage.forLocale("de"), 4)
        XCTAssertEqual(ConsoleLanguage.forLocale("de-AT"), 4)
        XCTAssertEqual(ConsoleLanguage.forLocale("en"), 1)
        XCTAssertEqual(ConsoleLanguage.forLocale("en-GB"), 18)
        XCTAssertEqual(ConsoleLanguage.forLocale("pt"), 7)
        XCTAssertEqual(ConsoleLanguage.forLocale("pt-BR"), 17)
        XCTAssertEqual(ConsoleLanguage.forLocale("pt_BR"), 17)
        XCTAssertEqual(ConsoleLanguage.forLocale("zh-Hant"), 10)
        XCTAssertEqual(ConsoleLanguage.forLocale("zh"), 11)
        XCTAssertEqual(ConsoleLanguage.forLocale("es-419"), 20)
        XCTAssertEqual(ConsoleLanguage.forLocale("nb"), 15)
        XCTAssertNil(ConsoleLanguage.forLocale("eo"))
    }

    func testAnOldFileStillWorks() throws {
        let old = try LanguageFiles.parse(Data(#"{"@meta": {"name": "Deutsch (alt)", "consoleLanguage": 4}, "back": "Zurück"}"#.utf8), code: "de")
        XCTAssertEqual(old.name, "Deutsch (alt)")
        XCTAssertEqual(old.consoleLanguage, 4)
        XCTAssertEqual(old.texts, ["back": "Zurück"], "\"@meta\" is never a text")
        let pirate = try LanguageFiles.parse(Data(#"{"@meta": {"name": "Pirate", "consoleLanguage": 18}}"#.utf8), code: "x-pirate")
        XCTAssertEqual(pirate.consoleLanguage, 18, "a code the console does not know keeps its file's number")
    }

    func testATranslationWithOtherPlaceholdersShowsTheEnglishText() throws {
        let english = LanguageFile(code: "en", name: "English", consoleLanguage: 1, texts: ["found": "%d games found", "who": "%@ and %@"])
        let other = LanguageFile(code: "tr", name: "Türkçe", consoleLanguage: 19, texts: ["found": "%@ oyun bulundu", "who": "%2$@ ve %1$@"])
        let texts = LanguageTexts([english, other])
        XCTAssertEqual(texts.text("found", in: "tr"), "%d games found")
        XCTAssertEqual(texts.text("who", in: "tr"), "%2$@ ve %1$@")
        XCTAssertEqual(LanguageFiles.problems(other, english: english.texts),
                       [#"tr.json: "found" has the placeholders #1 %@, English has #1 %d"#])
    }

    func testPlaceholdersAreCountedAsStringFormatFillsThem() {
        typealias P = LanguageFiles.Placeholder
        XCTAssertEqual(LanguageFiles.placeholders("%d h %d min"), [P(number: 1, kind: "d"), P(number: 2, kind: "d")])
        XCTAssertEqual(LanguageFiles.placeholders("%1$@ points to level %2$d"), [P(number: 1, kind: "@"), P(number: 2, kind: "d")])
        XCTAssertEqual(LanguageFiles.placeholders("%2$@ ve %1$@"), LanguageFiles.placeholders("%@ and %@"))
        XCTAssertEqual(LanguageFiles.placeholders("%%%d"), [P(number: 1, kind: "d")], "%% is a percent sign")
        XCTAssertEqual(LanguageFiles.placeholders("A new code in %d:%02d"), [P(number: 1, kind: "d"), P(number: 2, kind: "d")])
        XCTAssertEqual(LanguageFiles.placeholders("%.1f GB"), [P(number: 1, kind: "f")])
        XCTAssertEqual(LanguageFiles.placeholders("%ld"), [P(number: 1, kind: "ld")])
        XCTAssertEqual(LanguageFiles.placeholders("100 % sure, %0 tam"), [], "a lone percent sign is no placeholder")
        XCTAssertNotEqual(LanguageFiles.placeholders("%@"), LanguageFiles.placeholders("%d"))
    }
}
