@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The check of the language files in l10n (l10n/TRANSLATING.md), as AnyLauncher-Port's
/// tool/check_translations.dart does it for its own: every file one flat JSON object of texts
/// (Weblate's monolingual JSON, so no "@meta"), named by a locale code, its own name under
/// "languageName", no key English lacks, English's placeholders in each text, Turkish complete,
/// and en.json holding exactly the keys the code reads.
final class LanguageCheckTests: XCTestCase {
    let folder = T.sourceFolder

    override func setUp() {
        // Only the files in l10n, not a Languages folder on this Mac.
        T.texts = T.load([T.sourceFolder])
    }

    func file(_ code: String) throws -> LanguageFile {
        try LanguageFiles.parse(Data(contentsOf: folder.appendingPathComponent("\(code).json")), code: code)
    }

    func testEveryLanguageFilePassesTheCheck() throws {
        let english = try file("en").texts
        let codes = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
        XCTAssertTrue(codes.contains("en") && codes.contains("tr"), "\(codes)")
        print("en: \(english.count) texts")
        for code in codes {
            let data = try Data(contentsOf: folder.appendingPathComponent("\(code).json"))
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("\(code).json is not one JSON object: { \"key\": \"text\", ... }")
                continue
            }
            XCTAssertNil(object[LanguageFiles.legacyMeta], "\(code).json has the old \"@meta\" object, which Weblate cannot read: write \"\(LanguageFiles.nameKey)\": \"…\" instead (the console language comes from the file name)")
            XCTAssertTrue(code.range(of: #"^[a-z]{2,3}([-_]([A-Z][a-z]{3}|[A-Z]{2}|[0-9]{3}))?$"#, options: .regularExpression) != nil, "\(code).json has to be named by its language code: de.json, pt-BR.json, zh-Hant.json")
            XCTAssertFalse((object[LanguageFiles.nameKey] as? String ?? "x").trimmingCharacters(in: .whitespaces).isEmpty, "\(code).json: \"\(LanguageFiles.nameKey)\" is the language's own name and cannot be empty")
            for (key, value) in object where !(value is String) {
                XCTFail("\(code).json: \"\(key)\" has to be a text in quotes")
            }
            let language = try file(code)
            for problem in LanguageFiles.problems(language, english: english) { XCTFail(problem) }
            if code != "en" {
                let translated = language.texts.keys.filter { english[$0] != nil }.count
                print(String(format: "%@: %.1f %% translated (%d of %d)", code, Double(translated) * 100 / Double(english.count), translated, english.count))
            }
        }
    }

    func testTurkishHasEveryEnglishKey() throws {
        let english = try file("en").texts, turkish = try file("tr").texts
        XCTAssertEqual(english.keys.filter { turkish[$0] == nil }.sorted(), [], "keys of en.json missing from tr.json")
        XCTAssertEqual(english[LanguageFiles.nameKey], "English")
        XCTAssertEqual(turkish[LanguageFiles.nameKey], "Türkçe")
        XCTAssertEqual(try file("en").name, "English")
        XCTAssertEqual(try file("tr").name, "Türkçe")
        XCTAssertEqual(try file("tr").consoleLanguage, 19)
    }

    func testEnglishHasEveryKeyTheCodeUsesAndNoOther() throws {
        let english = try file("en").texts
        // The language's own name is read by Language.displayName, not through a texts enum.
        let used = Set(T.codeKeys + [LanguageFiles.nameKey])
        XCTAssertEqual(used.subtracting(english.keys).sorted(), [], "keys the code uses that en.json lacks")
        XCTAssertEqual(Set(english.keys).subtracting(used).sorted(), [], "keys of en.json no code uses (remove them from every file)")
        XCTAssertEqual(T.codeKeys.count + 1, used.count, "two code keys share one JSON key")
    }

    /// A texts enum the list in T.codeKeys does not name would escape the check above.
    func testCodeKeysNamesEveryTextsEnum() throws {
        let sources = folder.deletingLastPathComponent().appendingPathComponent("Sources/AnyPS5")
        var enums = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            enums += text.components(separatedBy: "    enum Key: String, CaseIterable {").count - 1
        }
        let localization = try String(contentsOf: sources.appendingPathComponent("Localization.swift"), encoding: .utf8)
        let listed = localization.components(separatedBy: ".Key.allCases.map(\\.rawValue)").count - 1
        XCTAssertEqual(enums, listed)
    }

    func testFormatsFillTheirArgumentsInBothLanguages() {
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertEqual(T.format(.profileHoursMinutes, 2, 5), "2 h 5 min")
        XCTAssertEqual(TP.format(.battery, 80), "80%")
        XCTAssertEqual(TL.format(.levelNext, "1,200", 7), "1,200 points to level 7")
        XCTAssertEqual(T.text(.accentMint), "Mint")
        T.language = .turkish
        XCTAssertEqual(T.format(.profileHoursMinutes, 2, 5), "2 sa 5 dk")
        XCTAssertEqual(TP.format(.battery, 80), "%80")
        XCTAssertEqual(T.text(.accentMint), "Nane")
        XCTAssertEqual(T.text(.back), "Geri")
        XCTAssertEqual(T.locale.identifier, "tr_TR")
    }

    func testLanguagesComeFromTheFiles() {
        XCTAssertEqual(Language.allCases.first, .english)
        XCTAssertTrue(Language.allCases.contains(.turkish))
        XCTAssertEqual(Language.turkish.displayName, "Türkçe")
        XCTAssertEqual(Language.turkish.consoleLanguage, 19)
        XCTAssertEqual(Language.english.consoleLanguage, 1)
        XCTAssertEqual(Language(rawValue: "tr"), .turkish)
        XCTAssertNil(Language(rawValue: "xx"))
    }

    func testPreferencesKeepTheLanguageAsItsCode() throws {
        let encoded = try JSONEncoder().encode(["language": Language.turkish])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"language":"tr"}"#)
        XCTAssertEqual(try JSONDecoder().decode([String: Language].self, from: Data(#"{"language":"en"}"#.utf8))["language"], .english)
    }
}
