import Foundation

/// Keeps a list's focus on the same item when items come or go around it: a panel focused on
/// "Call Mira" stays on it when a game invite is put above, so Return does what it shows.
public enum ListFocus {
    /// Where the focused item is now: the index of `id` in `ids`, else `fallback` (the index it
    /// had) within the list.
    public static func index(of id: String?, in ids: [String], fallback: Int) -> Int {
        if let id, let found = ids.firstIndex(of: id) { return found }
        return ids.isEmpty ? 0 : min(max(0, fallback), ids.count - 1)
    }
}
