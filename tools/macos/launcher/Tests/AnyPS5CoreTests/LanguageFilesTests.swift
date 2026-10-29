@testable import AnyPS5Core
import XCTest

/// The language files' reading: a user folder before the built-in one, English as the fallback,
/// "@meta" names and the placeholder rules of AnyPS5-Desktop's check_translations.dart.
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
        try write("builtin", "tr.json", #"{"@meta": {"name": "Türkçe", "consoleLanguage": 19}, "back": "Geri"}"#)
        try write("builtin", "en.json", #"{"@meta": {"name": "English", "consoleLanguage": 1}, "back": "Back", "games": "Games"}"#)
        try write("user", "de.json", #"{"@meta": {"name": "Deutsch", "consoleLanguage": 4}, "back": "Zurück"}"#)
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
        try write("builtin", "en.json", #"{"@meta": {"name": "English", "consoleLanguage": 1}, "back": "Back"}"#)
        try write("builtin", "tr.json", #"{"@meta": {"name": "Türkçe", "consoleLanguage": 19}, "back": "Geri"}"#)
        try write("user", "tr.json", #"{"@meta": {"name": "Türkçe (deneme)", "consoleLanguage": 19}, "back": "Geri dön"}"#)
        let texts = LanguageTexts(LanguageFiles.load(folders()))
        XCTAssertEqual(texts.text("back", in: "tr"), "Geri dön")
        XCTAssertEqual(texts.language("tr")?.name, "Türkçe (deneme)")
    }

    func testABrokenFileIsLeftOutForTheNextOneOfItsCode() throws {
        try write("builtin", "en.json", #"{"@meta": {"name": "English", "consoleLanguage": 1}, "back": "Back"}"#)
        try write("builtin", "tr.json", #"{"@meta": {"name": "Türkçe", "consoleLanguage": 19}, "back": "Geri"}"#)
        try write("user", "tr.json", #"{"back": "Geri""#)
        try write("user", "fr.json", #"["not", "an", "object"]"#)
        var log: [String] = []
        let languages = LanguageFiles.load(folders()) { log.append($0) }
        XCTAssertEqual(languages.map(\.code), ["en", "tr"])
        XCTAssertEqual(LanguageTexts(languages).text("back", in: "tr"), "Geri")
        XCTAssertEqual(log.count, 2)
    }

    func testMissingMetaGivesTheCodeAndEnglishConsoleLanguage() throws {
        let file = try LanguageFiles.parse(Data(#"{"back": "Tillbaka", "count": 3}"#.utf8), code: "sv")
        XCTAssertEqual(file.name, "sv")
        XCTAssertEqual(file.consoleLanguage, 1)
        XCTAssertEqual(file.texts, ["back": "Tillbaka"], "a value that is not a text is left out")
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
