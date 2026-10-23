import Foundation

/// An anyps5:// link from a web page, a message or another app: anyps5://game/<title ID> shows
/// the game, anyps5://play/<title ID> does what Play does for it, anyps5://library and
/// anyps5://settings open those screens.
public enum DeepLink: Equatable, Sendable {
    case game(String)
    case play(String)
    case library
    case settings

    public static let scheme = "anyps5"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == DeepLink.scheme, let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        switch (host, parts.count) {
        case ("library", 0): self = .library
        case ("settings", 0): self = .settings
        case ("game", 1), ("play", 1):
            // Title IDs are four letters and five digits (PPSA15065, CUSA00001).
            let id = parts[0].uppercased()
            guard id.range(of: "^[A-Z]{4}[0-9]{5}$", options: .regularExpression) != nil else { return nil }
            self = host == "game" ? .game(id) : .play(id)
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case .game(let id): return URL(string: "\(DeepLink.scheme)://game/\(id)")!
        case .play(let id): return URL(string: "\(DeepLink.scheme)://play/\(id)")!
        case .library: return URL(string: "\(DeepLink.scheme)://library")!
        case .settings: return URL(string: "\(DeepLink.scheme)://settings")!
        }
    }
}
