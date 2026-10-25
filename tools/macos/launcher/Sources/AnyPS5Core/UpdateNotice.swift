import Foundation

/// Where the launcher's own update stands, as About shows it: never asked yet, asking, up to date,
/// a newer one (not downloaded: this copy cannot replace itself, or the download failed), its
/// download, or downloaded, checked and ready for a restart.
public enum LauncherUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checked: Date)
    case failed
    case available(version: String)
    case downloading(version: String, fraction: Double)
    case ready(version: String)

    /// The state from what the launcher knows: a ready update wins over a check on its way, a
    /// download over the check.
    public static func of(checking: Bool, newer: String?, progress: Double?, ready: String?, lastCheck: Date?, failed: Bool) -> LauncherUpdateState {
        if let ready { return .ready(version: ready) }
        if let newer, let progress { return .downloading(version: newer, fraction: progress) }
        if checking { return .checking }
        if let newer { return .available(version: newer) }
        if failed { return .failed }
        if let lastCheck { return .upToDate(checked: lastCheck) }
        return .idle
    }

    /// The download's percent, 0 to 100.
    public var percent: Int? {
        guard case .downloading(_, let fraction) = self else { return nil }
        return Int(min(1, max(0, fraction)) * 100)
    }
}

/// The quiet notice on the home screen once an update is ready: Restart Now, or Later (the
/// update then goes in when the launcher quits, so the next launch is the new version, and the
/// notice does not come back for that version).
public struct UpdateNotice: Equatable, Sendable {
    public private(set) var deferred: Set<String> = []

    public init() {}

    public func shows(_ state: LauncherUpdateState) -> Bool {
        guard case .ready(let version) = state else { return false }
        return !deferred.contains(version)
    }

    public mutating func later(_ state: LauncherUpdateState) {
        if case .ready(let version) = state { deferred.insert(version) }
    }
}

/// Restart Now never interrupts a game: with one running, the restart waits for it to close.
public enum UpdateRestart: Equatable, Sendable {
    case now
    case afterGame

    public static func decide(gameRunning: Bool) -> UpdateRestart { gameRunning ? .afterGame : .now }
}
