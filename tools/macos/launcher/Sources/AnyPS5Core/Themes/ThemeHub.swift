import Foundation

/// The shared place for themes: an index of what people shared, read from a web address, and
/// each theme's file to download. It starts as a folder in the AnyPS5-ARM repository on GitHub
/// (shared by a pull request), to move to AnyPS5's own server.
public enum ThemeHub {
    public static let defaultBase = URL(string: "https://raw.githubusercontent.com/AnyTogether/AnyPS5-ARM/main/hub/")!
    /// Where a theme is shared from: a new issue on the repository, with the file attached.
    public static let shareURL = URL(string: "https://github.com/AnyTogether/AnyPS5-ARM/issues/new?labels=theme&title=Theme%3A%20")!

    public struct Theme: Identifiable, Equatable, Sendable {
        public var id: String { design.id }
        public var name: String { design.name }
        public let design: ThemeDesign
        public let package: URL
        public let preview: URL?

        public init(design: ThemeDesign, package: URL, preview: URL?) {
            self.design = design
            self.package = package
            self.preview = preview
        }
    }

    struct Index: Decodable {
        struct Entry: Decodable {
            let id: String
            let name: String
            let author: String
            let version: Int?
            let style: Int?
            let deep: String
            let middle: String
            let bright: String
            let accent: String
            let package: String
            let preview: String?
        }

        let themes: [Entry]
    }

    static func index(from data: Data, base: URL) throws -> [Theme] {
        try JSONDecoder().decode(Index.self, from: data).themes.compactMap { entry in
            guard let package = URL(string: entry.package, relativeTo: base)?.absoluteURL else { return nil }
            let design = ThemeDesign(id: entry.id, name: entry.name, author: entry.author, version: entry.version ?? 1, style: entry.style ?? 0,
                                     deep: entry.deep, middle: entry.middle, bright: entry.bright, accent: entry.accent)
            return Theme(design: design, package: package, preview: entry.preview.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL })
        }
    }

    /// What the Hub offers now.
    public static func themes(base: URL = defaultBase, session: URLSession = .shared) async throws -> [Theme] {
        var request = URLRequest(url: base.appendingPathComponent("themes.json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { throw URLError(.badServerResponse) }
        return try index(from: data, base: base)
    }

    /// Downloads a theme and installs it in `library`.
    public static func install(_ theme: Theme, into library: ThemeLibrary, session: URLSession = .shared) async throws -> ThemeDesign {
        let (file, response) = try await session.download(from: theme.package)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200 else { throw URLError(.badServerResponse) }
        return try library.install(file)
    }
}
