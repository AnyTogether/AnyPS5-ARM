import Foundation

/// A request body sent as it is, with its own content type: a file going up.
public struct TogetherRawBody: Sendable {
    public let data: Data
    public let contentType: String
    /// More headers to send with it (a part's X-Part-SHA256).
    public let headers: [String: String]

    public init(data: Data, contentType: String, headers: [String: String] = [:]) {
        self.data = data
        self.contentType = contentType
        self.headers = headers
    }

    /// multipart/form-data of text fields and files.
    public static func form(fields: [(name: String, value: String)] = [], files: [(name: String, filename: String, type: String, data: Data)],
                            boundary: String = "anyps5-\(UUID().uuidString)") -> TogetherRawBody {
        var body = Data()
        func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
        for field in fields {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(field.name)\"")
            line("")
            line(field.value)
        }
        for file in files {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename.replacingOccurrences(of: "\"", with: ""))\"")
            line("Content-Type: \(file.type)")
            line("")
            body.append(file.data)
            line("")
        }
        line("--\(boundary)--")
        return TogetherRawBody(data: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }
}

/// A theme on AnyTogether's Theme Hub, as it lists and shows them.
public struct TogetherHubTheme: Decodable, Equatable, Sendable, Identifiable {
    public struct Colors: Decodable, Equatable, Sendable {
        public let deep: String
        public let middle: String
        public let bright: String
        public let accent: String
    }

    public let id: String
    public let name: String
    public let maker: TogetherPerson?
    public let version: Int
    public let style: Int
    public let colors: Colors
    /// "picture", "video" or nil.
    public let background: String?
    public let music: Bool
    public let downloads: Int
    public let likes: Int
    public let preview: String
    public let thumb: String
    /// The .anyps5theme file.
    public let download: String
    /// The anyps5://theme/<id> link.
    public let open: String
    public let size: Int
    public let description: String?
    public let mine: Bool?

    /// As the launcher's Hub lists it, to install.
    public var hubTheme: ThemeHub.Theme? {
        guard let package = URL(string: download) else { return nil }
        let design = ThemeDesign(id: id, name: name, author: maker?.displayName ?? "", version: version, style: style,
                                 deep: colors.deep, middle: colors.middle, bright: colors.bright, accent: colors.accent)
        return ThemeHub.Theme(design: design, package: package, preview: URL(string: thumb))
    }

    /// Theme IDs are UUIDs.
    public static func isID(_ text: String) -> Bool {
        text.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }
}

extension ThemeHub {
    /// The Hub on an AnyTogether server: the same index the GitHub folder has.
    public static func base(onServer server: URL) -> URL {
        server.appendingPathComponent("api/v1/hub/", isDirectory: true)
    }

    /// The first of `bases` that offers themes: AnyTogether's Hub, then the GitHub folder while
    /// the server has none (or cannot be reached).
    public static func themes(from bases: [URL], session: URLSession = .shared) async throws -> [Theme] {
        var failure: Error?
        var answered = false
        for base in bases {
            do {
                let found = try await themes(base: base, session: session)
                answered = true
                if !found.isEmpty { return found }
            } catch {
                failure = error
            }
        }
        if !answered, let failure { throw failure }
        return []
    }
}

extension TogetherClient {
    /// Shares a theme file on the Hub, with a still of it (the server needs one); a theme shared
    /// before from the same design goes up as its new version instead.
    public func shareTheme(_ file: URL, preview: Data?, previewType: String = "image/png") async throws -> TogetherHubTheme {
        let data = try Data(contentsOf: file)
        var files = [(name: "theme", filename: file.lastPathComponent, type: "application/zip", data: data)]
        if let preview { files.append((name: "preview", filename: "preview.png", type: previewType, data: preview)) }
        let body = TogetherRawBody.form(files: files)
        do {
            return try JSONDecoder.together.decode(TogetherHubTheme.self, from: try await authorized("POST", "themes", body))
        } catch let problem as TogetherProblem where problem.status == 409 && problem.themeId != nil {
            let id = problem.themeId ?? ""
            return try JSONDecoder.together.decode(TogetherHubTheme.self, from: try await authorized("POST", "themes/\(Self.path(id))/versions", body))
        }
    }

    /// One theme, signed in or not (for an anyps5://theme link).
    public func hubTheme(_ id: String) async throws -> TogetherHubTheme {
        let path = "themes/\(Self.path(id))"
        let data = user == nil ? try await send("GET", path, nil) : try await authorized("GET", path, nil)
        return try JSONDecoder.together.decode(TogetherHubTheme.self, from: data)
    }
}
