@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The check of the language files in l10n (l10n/TRANSLATING.md), as AnyPS5-Desktop's
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

    func testAGameReadyWithoutSomeFilesSaysSoInOneShortSentenceWithoutTheFiles() {
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertNil(AppModel.leftOutText("Orbit Runner", []))
        XCTAssertEqual(
            AppModel.leftOutText("Orbit Runner", [
                LeftOutModule("sce_module/libSceNpCppWebApi.prx", .notRelinked, "bad"),
                LeftOutModule("sce_module/libSceNpWebApi.prx", .notRelinked, "bad"),
            ]),
            "Orbit Runner is ready. A few of its files could not be converted and were left out."
        )
        XCTAssertEqual(
            AppModel.leftOutText("Orbit Runner", [
                LeftOutModule("sce_module/libSceNpCppWebApi.prx", .notRelinked),
                LeftOutModule("sce_module/libSceFace.prx", .encrypted),
            ]),
            "Orbit Runner is ready, but some of its files are encrypted in the dump. If it does not start, dump it again."
        )
        // Gran Turismo 7 with its wheel module neither an ELF nor a SELF: the same short note.
        XCTAssertEqual(
            AppModel.leftOutText("Gran Turismo 7", [LeftOutModule("sce_module/pdiWheel_0.prx", .encrypted)]),
            "Gran Turismo 7 is ready, but some of its files are encrypted in the dump. If it does not start, dump it again."
        )
    }

    func testFormatsFillTheirArgumentsInBothLanguages() {
        let saved = T.language
        defer { T.language = saved }
        T.language = .english
        XCTAssertEqual(T.format(.profileHoursMinutes, 2, 5), "2 h 5 min")
        XCTAssertEqual(TP.format(.battery, 80), "80%")
        XCTAssertEqual(TL.format(.levelNext, "1,200", 7), "1,200 points to level 7")
        XCTAssertEqual(T.text(.accentMint), "Mint")
        // One player in the singular, as on Windows and Linux.
        XCTAssertEqual(TS.format(.boardPlayersOne, 1), "1 player")
        XCTAssertEqual(TS.format(.boardPlayers, 2), "2 players")
        XCTAssertEqual(FP.format(.playersOne, 1), "1 player on AnyTogether")
        XCTAssertEqual(T.format(.gamePlayersOne, 1, 1), "1 of 1 player")
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

    /// VK's twelve languages, carried over from AnyLauncher Port where both launchers' English
    /// reads the same (scripts/import-port-translations.py): listed by their own names, complete,
    /// and English wherever they have no text.
    func testThePortsLanguagesAreListedAndFallBackToEnglish() throws {
        let saved = T.language
        defer { T.language = saved }
        let names = ["ar": "العربية", "bho": "भोजपुरी", "bn": "বাংলা", "de": "Deutsch", "es": "Español", "fr": "Français",
                     "hi": "हिन्दी", "id": "Bahasa Indonesia", "ja": "日本語", "pt": "Português", "ru": "Русский", "ur": "اردو",
                     // VK's second batch.
                     "am": "አማርኛ", "cs": "Čeština", "da": "Dansk", "fil": "Filipino", "hu": "Magyar", "km": "ភាសាខ្មែរ",
                     "ko": "한국어", "lo": "ພາສາລາວ", "ms": "Bahasa Melayu", "no": "Norsk", "ro": "Română", "sv": "Svenska",
                     "zh-Hans": "简体中文", "zh-Hant": "繁體中文"]
        let english = try file("en").texts
        for (code, name) in names {
            let language = try XCTUnwrap(Language(rawValue: code), "\(code).json is listed")
            XCTAssertEqual(language.displayName, name)
            let texts = try file(code).texts
            XCTAssertGreaterThan(texts.count, 500, "\(code).json carries the shared texts")
            XCTAssertLessThanOrEqual(texts.count, english.count, "\(code).json has no key English lacks")
            for (key, text) in texts {
                XCTAssertEqual(LanguageFiles.placeholders(text), LanguageFiles.placeholders(english[key] ?? ""), "\(code).json: \(key)")
            }
            // A key the language leaves out shows in English (none is left out while the file is complete).
            T.language = language
            if let missing = english.keys.sorted().first(where: { texts[$0] == nil }) {
                XCTAssertEqual(T.string(missing), english[missing])
            }
        }
        T.language = try XCTUnwrap(Language(rawValue: "de"))
        XCTAssertEqual(T.text(.back), "Zurück")
        XCTAssertEqual(T.string("welcomeSubtitle"), try file("de").texts["welcomeSubtitle"], "the Mac's own words, which the Port says of a PC, are translated here")
    }

    /// The first start picks the Mac's language, as AnyPS5-Desktop's launcher does: Chinese by
    /// its script or region, Norwegian and Filipino by any of their codes.
    func testTheFirstStartPicksTheMacsLanguage() throws {
        let codes = Language.allCases.map(\.code)
        let cases: [(String, String?)] = [
            ("zh-Hans-CN", "zh-Hans"), ("zh-CN", "zh-Hans"), ("zh_SG", "zh-Hans"), ("zh", "zh-Hans"),
            ("zh-Hant-TW", "zh-Hant"), ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-MO", "zh-Hant"),
            ("zh-Hant-HK", "zh-Hant"), ("zh-Hant", "zh-Hant"),
            ("nb-NO", "no"), ("nn-NO", "no"), ("no", "no"), ("fil-PH", "fil"), ("tl-PH", "fil"),
            ("ko-KR", "ko"), ("km-KH", "km"), ("lo-LA", "lo"), ("am-ET", "am"), ("cs-CZ", "cs"), ("hu-HU", "hu"),
            ("ro-RO", "ro"), ("ms-MY", "ms"), ("sv-SE", "sv"), ("da-DK", "da"), ("de_DE@euro", "de"), ("pt-BR", "pt"),
            ("eo", nil),
        ]
        for (system, code) in cases {
            XCTAssertEqual(LanguageFiles.match([system], codes: codes), code, system)
        }
        XCTAssertEqual(LanguageFiles.match(["eo", "fr-CA", "en-US"], codes: codes), "fr")
        XCTAssertEqual(LanguageFiles.match(["pt-BR"], codes: ["en", "pt", "pt-BR"]), "pt-BR")
        XCTAssertEqual(LanguageFiles.match(["pt_PT"], codes: ["en", "pt", "pt-BR"]), "pt")
        XCTAssertEqual(Preferences.firstStart(preferred: ["zh-Hant-TW", "en-US"]).language.code, "zh-Hant")
        XCTAssertEqual(Preferences.firstStart(preferred: ["nb-NO"]).language.code, "no")
        XCTAssertEqual(Preferences.firstStart(preferred: ["eo"]).language, .english)
        XCTAssertEqual(Preferences.firstStart(preferred: []).language, .english)
    }

    /// Arabic and Urdu mirror the screens, and ← and → then follow what is drawn.
    func testRightToLeftLanguagesMirrorTheArrows() throws {
        XCTAssertTrue(try XCTUnwrap(Language(rawValue: "ar")).isRightToLeft)
        XCTAssertTrue(try XCTUnwrap(Language(rawValue: "ur")).isRightToLeft)
        XCTAssertFalse(Language.english.isRightToLeft)
        XCTAssertFalse(Language.turkish.isRightToLeft)
        XCTAssertEqual(Command.left.mirrored, .right)
        XCTAssertEqual(Command.right.mirrored, .left)
        XCTAssertEqual(Command.select.mirrored, .select)
        XCTAssertEqual(Command.nextGame.mirrored, .nextGame)
    }

    func testPreferencesKeepTheLanguageAsItsCode() throws {
        let encoded = try JSONEncoder().encode(["language": Language.turkish])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"{"language":"tr"}"#)
        XCTAssertEqual(try JSONDecoder().decode([String: Language].self, from: Data(#"{"language":"en"}"#.utf8))["language"], .english)
    }
}
