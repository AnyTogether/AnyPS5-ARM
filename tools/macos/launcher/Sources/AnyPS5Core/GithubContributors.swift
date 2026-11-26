import Foundation

/// The launcher's contributors for Settings › About, read from GitHub's public API as Windows and
/// Linux read them (AnyPS5-Desktop's github_contributors.dart). Both launchers credit the people
/// of AnyTogether/AnyPS5-Desktop, where the launcher's features are built first: AnyPS5-ARM's own
/// list is the engine's, hundreds of upstream contributors long.
public enum GithubContributors {
    public static let repository = "AnyTogether/AnyPS5-Desktop"
    /// The owner, shown first in Settings › About whatever GitHub says.
    public static let ownerLogin = "utkuhalis"
    public static let ownerName = "Utku Halis"
    public static let ownerPage = URL(string: "https://github.com/\(ownerLogin)")!
    /// How many people besides the owner About shows; See all on GitHub has the rest.
    public static let shown = 12
    public static let allPage = URL(string: "https://github.com/\(repository)/graphs/contributors")!

    public struct Person: Equatable, Sendable {
        public let login: String
        public let avatar: String
        public let page: URL
        public let contributions: Int

        public init(login: String, avatar: String, page: URL, contributions: Int) {
            self.login = login
            self.avatar = avatar
            self.page = page
            self.contributions = contributions
        }
    }

    /// The people in GitHub's answer, highest contribution first as GitHub sends them. Bots
    /// (logins ending in [bot]) and entries without a login are left out; anything but a list is
    /// no one.
    public static func people(from data: Data) -> [Person] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let json = entry as? [String: Any], let login = json["login"] as? String, !login.isEmpty, !login.hasSuffix("[bot]") else { return nil }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(login)")!
            return Person(login: login, avatar: json["avatar_url"] as? String ?? "", page: page, contributions: (json["contributions"] as? NSNumber)?.intValue ?? 0)
        }
    }

    /// The repository's contributors; no one when GitHub cannot be reached or answers anything else.
    public static func fetch(session: URLSession = .shared, api: URL = URL(string: "https://api.github.com")!, perPage: Int = 30) async -> [Person] {
        var parts = URLComponents(url: api.appendingPathComponent("repos/\(repository)/contributors"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "per_page", value: String(perPage))]
        guard let url = parts?.url else { return [] }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AnyPS5", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return people(from: data)
    }
}
