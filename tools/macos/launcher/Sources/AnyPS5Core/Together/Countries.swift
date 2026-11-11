import Foundation

/// The countries a profile can name: ISO 3166-1 alpha-2, exactly the codes AnyTogether accepts
/// (packages/shared/src/profile.ts there), with their names as the system knows them in a
/// language. The profile keeps the two-letter code.
public enum Countries {
    public static let codes: [String] =
        "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW"
        .split(separator: " ").map(String.init)

    public struct Country: Equatable, Sendable {
        public let code: String
        public let name: String

        public init(code: String, name: String) {
            self.code = code
            self.name = name
        }
    }

    /// Whether `code` is one the server takes (in any case).
    public static func isKnown(_ code: String) -> Bool { codes.contains(code.uppercased()) }

    /// The country's name in `locale`'s language; the code itself where the system has none.
    public static func name(_ code: String, in locale: Locale) -> String {
        locale.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    /// 🇹🇷 from "TR": the two regional indicator letters.
    public static func flag(_ code: String) -> String {
        let letters = code.uppercased().unicodeScalars
        guard letters.count == 2, letters.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
        return String(String.UnicodeScalarView(letters.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) }))
    }

    /// Every country by its name in `locale`'s language, in that language's order.
    public static func all(in locale: Locale) -> [Country] {
        codes.map { Country(code: $0, name: name($0, in: locale)) }
            .sorted { $0.name.compare($1.name, options: [.caseInsensitive], range: nil, locale: locale) == .orderedAscending }
    }

    /// Letters as a search compares them: no capitals, no accents, and Turkish's dotless ı as i,
    /// so "turkiye", "TÜRKİYE" and "Türkiye" are one word.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).replacingOccurrences(of: "ı", with: "i")
    }

    /// The countries of `all` a search for `query` finds: by a part of the name in the launcher's
    /// language or in English, or by the code. The country whose code was typed comes first; an
    /// empty search finds them all.
    public static func search(_ query: String, in all: [Country]) -> [Country] {
        let words = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !words.isEmpty else { return all }
        let english = Locale(identifier: "en_US")
        let found = all.filter { country in
            fold(country.name).contains(words) || fold(name(country.code, in: english)).contains(words) || country.code.lowercased() == words
        }
        return found.filter { $0.code.lowercased() == words } + found.filter { $0.code.lowercased() != words }
    }
}
