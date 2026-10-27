import Foundation

/// Which AnyTogether the launcher talks to. AnyTogether is open source and can be hosted by
/// anyone: the user may pick another server, and ANYTOGETHER_URL overrides both (staging, a
/// local one).
public enum TogetherServer {
    public static let standard = URL(string: "https://anytogether.net")!

    /// A server address as typed: https with a host, or http on this Mac only; no user, query or
    /// fragment; without the trailing slash. nil when it is not one.
    public static func address(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil else { return nil }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        return components.url
    }

    /// ANYTOGETHER_URL, then the user's choice, then AnyTogether's own server.
    public static func base(environment: [String: String] = ProcessInfo.processInfo.environment, chosen: String?) -> URL {
        if let forced = environment["ANYTOGETHER_URL"].flatMap(URL.init(string:)) { return forced }
        return chosen.flatMap(address) ?? standard
    }
}
