import Foundation

/// The texts of a game's dumped update and add-ons on its page, from the language files (l10n); kept apart
/// from `T` like `TPrep`.
enum TAddons {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case addons, addonsMore, updateApplied, updateToApply
    }
}
