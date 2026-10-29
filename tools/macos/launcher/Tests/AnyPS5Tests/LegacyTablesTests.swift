@testable import AnyPS5
import AnyPS5Core
import XCTest

/// The texts the launcher had in its Swift tables, against the language files that replace them:
/// every English and Turkish text has to be there, unchanged, under its key's JSON name.
final class LegacyTablesTests: XCTestCase {
    let en = try! LanguageFiles.parse(Data(contentsOf: T.sourceFolder.appendingPathComponent("en.json")), code: "en").texts
    let tr = try! LanguageFiles.parse(Data(contentsOf: T.sourceFolder.appendingPathComponent("tr.json")), code: "tr").texts
    var compared = 0

    func compare<Key: RawRepresentable & CaseIterable & Hashable>(_ table: String, _ keys: Key.AllCases, english: [Key: String], turkish: [Key: String]) where Key.RawValue == String {
        // The accent names are new keys of T, compared below.
        let keys = keys.filter { table != "T" || !$0.rawValue.hasPrefix("accent") || english[$0] != nil }
        XCTAssertEqual(english.count, keys.count, "\(table): English table and keys")
        XCTAssertEqual(turkish.count, keys.count, "\(table): Turkish table and keys")
        for key in keys {
            XCTAssertEqual(en[key.rawValue], english[key], "\(table).\(key) en")
            XCTAssertEqual(tr[key.rawValue], turkish[key], "\(table).\(key) tr")
            compared += 1
        }
    }

    func testEveryOldTextIsInTheLanguageFiles() {
        compare("T", T.Key.allCases, english: T.english, turkish: T.turkish)
        compare("TAddons", TAddons.Key.allCases, english: TAddons.english, turkish: TAddons.turkish)
        compare("TK", TK.Key.allCases, english: TK.english, turkish: TK.turkish)
        compare("TA", TA.Key.allCases, english: TA.english, turkish: TA.turkish)
        compare("TB", TB.Key.allCases, english: TB.english, turkish: TB.turkish)
        compare("TW", TW.Key.allCases, english: TW.english, turkish: TW.turkish)
        compare("TCap", TCap.Key.allCases, english: TCap.english, turkish: TCap.turkish)
        compare("TChat", TChat.Key.allCases, english: TChat.english, turkish: TChat.turkish)
        compare("TCloud", TCloud.Key.allCases, english: TCloud.english, turkish: TCloud.turkish)
        compare("TP", TP.Key.allCases, english: TP.english, turkish: TP.turkish)
        compare("FP", FP.Key.allCases, english: FP.english, turkish: FP.turkish)
        compare("TE", TE.Key.allCases, english: TE.english, turkish: TE.turkish)
        compare("FS", FS.Key.allCases, english: FS.english, turkish: FS.turkish)
        compare("TU", TU.Key.allCases, english: TU.english, turkish: TU.turkish)
        compare("TF", TF.Key.allCases, english: TF.english, turkish: TF.turkish)
        compare("TPresets", TPresets.Key.allCases, english: TPresets.english, turkish: TPresets.turkish)
        compare("TG", TG.Key.allCases, english: TG.english, turkish: TG.turkish)
        compare("TH", TH.Key.allCases, english: TH.english, turkish: TH.turkish)
        compare("JS", JS.Key.allCases, english: JS.english, turkish: JS.turkish)
        compare("TL", TL.Key.allCases, english: TL.english, turkish: TL.turkish)
        compare("PT", PT.Key.allCases, english: PT.english, turkish: PT.turkish)
        compare("TPow", TPow.Key.allCases, english: TPow.english, turkish: TPow.turkish)
        compare("TPrep", TPrep.Key.allCases, english: TPrep.english, turkish: TPrep.turkish)
        compare("TPro", TPro.Key.allCases, english: TPro.english, turkish: TPro.turkish)
        compare("TC", TC.Key.allCases, english: TC.english, turkish: TC.turkish)
        compare("SP", SP.Key.allCases, english: SP.english, turkish: SP.turkish)
        compare("TS", TS.Key.allCases, english: TS.english, turkish: TS.turkish)
        compare("TSteam", TSteam.Key.allCases, english: TSteam.english, turkish: TSteam.turkish)
        XCTAssertEqual(compared, 1811)
        // The accent names that were written inline in Theme.swift.
        let accents: [(String, String, String)] = [("accentBlue", "Blue", "Mavi"), ("accentMint", "Mint", "Nane"), ("accentCoral", "Coral", "Mercan"),
                                                   ("accentViolet", "Violet", "Mor"), ("accentGold", "Gold", "Altın"), ("accentWhite", "White", "Beyaz"), ("accentIce", "Ice", "Buz")]
        for (key, english, turkish) in accents {
            XCTAssertEqual(en[key], english)
            XCTAssertEqual(tr[key], turkish)
        }
        XCTAssertEqual(en.count, compared + accents.count, "en.json has no other texts")
        XCTAssertEqual(tr.count, compared + accents.count, "tr.json has no other texts")
    }
}
