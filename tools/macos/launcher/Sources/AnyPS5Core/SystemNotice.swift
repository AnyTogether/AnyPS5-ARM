import Foundation

/// Where a word said while the launcher is away goes, as on AnyPS5 Desktop (desktop_notice.dart):
/// over a game the card (TrophyBanner, which Desktop draws as the Mac's where it can), and with no
/// game playing a notification of the system's (Notification Center), which stays there to be
/// read later. The launcher in front says it in its own toast, and its callers only come here when
/// it is not, or for a card asked for anyway.
public enum SystemNotice {
    /// What the user said to macOS about the launcher's notifications.
    public enum Permission: Equatable, Sendable {
        /// Allowed, quietly (provisional) or not.
        case allowed
        case denied
        /// Not asked yet.
        case undecided
        /// Not a notification centre's app: run from `swift test`, `swift run` or a preview.
        case unavailable
    }

    public enum Route: Equatable, Sendable {
        /// The card over everything, as before.
        case card
        /// A notification of the system's in place of the card.
        case system
        /// The card this time, and macOS asked whether the launcher may notify: the first word
        /// away from the launcher with no game is the moment the question makes sense, not the
        /// first launch.
        case cardAndAsk
    }

    public static func route(launcherInFront: Bool, gamePlaying: Bool, permission: Permission) -> Route {
        // In front the caller wanted the card itself; over a game the card is what is seen (a
        // notification would sit behind a full-screen game, or cover it with a system banner).
        if launcherInFront || gamePlaying { return .card }
        switch permission {
        case .allowed: return .system
        case .undecided: return .cardAndAsk
        // Said no, or cannot: the card, as Desktop falls back to its own window when the
        // desktop cannot show a notice.
        case .denied, .unavailable: return .card
        }
    }

    /// Whether this process can have notifications at all: UNUserNotificationCenter needs an app
    /// bundle with an identifier, and stops the process outright without one (`swift test`).
    public static func available(bundlePath: String, bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return URL(fileURLWithPath: bundlePath).pathExtension == "app"
    }

    /// The notification's two lines: the card's title and its detail. An empty detail stays empty
    /// (macOS names the app above the title), as Desktop's unpacking notice has no second line.
    public static func lines(title: String, detail: String) -> (title: String, body: String) {
        (title.trimmingCharacters(in: .whitespacesAndNewlines), detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
