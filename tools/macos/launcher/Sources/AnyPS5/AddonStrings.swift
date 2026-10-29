import Foundation

/// The texts of a game's dumped update and add-ons on its page, in both languages; kept apart
/// from `T` like `TPrep`.
enum TAddons {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case addons, addonsMore, updateApplied, updateToApply
    }

    static let english: [Key: String] = [
        .addons: "DLC (%d)",
        .addonsMore: "+%d more",
        .updateApplied: "Update v%@ applied",
        .updateToApply: "Update v%@ · unlock to apply",
    ]

    static let turkish: [Key: String] = [
        .addons: "DLC (%d)",
        .addonsMore: "+%d daha",
        .updateApplied: "v%@ güncellemesi uygulandı",
        .updateToApply: "v%@ güncellemesi · uygulamak için kilidi aç",
    ]
}
