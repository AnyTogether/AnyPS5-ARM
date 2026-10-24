import Foundation

/// The themes on this Mac, one folder each (theme.json and its files) under Application
/// Support/AnyPS5/Themes: made in the Studio, or installed from a file or the Hub.
public final class ThemeLibrary: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// The largest background or music file a theme may bring.
    static let largestFile = 300 * 1024 * 1024

    public let folder: URL

    public init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Themes")) {
        self.folder = folder
    }

    /// Every theme, by name.
    public var all: [ThemeDesign] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? JSONDecoder().decode(ThemeDesign.self, from: Data(contentsOf: $0.appendingPathComponent("theme.json"))) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func design(_ id: String) -> ThemeDesign? {
        try? JSONDecoder().decode(ThemeDesign.self, from: Data(contentsOf: home(id).appendingPathComponent("theme.json")))
    }

    /// One of a theme's files, if it has it.
    public func file(_ name: String?, of design: ThemeDesign) -> URL? {
        guard let name, let safe = Self.plainName(name) else { return nil }
        let url = home(design.id).appendingPathComponent(safe)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes `design`, with a new background or music file when given (copied in as
    /// background.<ext> or music.<ext>); files not given stay as they were.
    @discardableResult
    public func save(_ design: ThemeDesign, background: URL?, music: URL?) throws -> ThemeDesign {
        var design = design
        design.id = Self.plainName(design.id) ?? UUID().uuidString.lowercased()
        let home = home(design.id)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let background { design.background = try copy(background, as: "background", into: home, replacing: design.background) }
        if let music { design.music = try copy(music, as: "music", into: home, replacing: design.music) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(design).write(to: home.appendingPathComponent("theme.json"), options: .atomic)
        return design
    }

    public func remove(_ id: String) throws {
        guard let safe = Self.plainName(id) else { return }
        try FileManager.default.removeItem(at: home(safe))
    }

    /// The theme as one file to share.
    public func export(_ design: ThemeDesign, to file: URL) throws {
        try? FileManager.default.removeItem(at: file)
        try SaveBackup.run("/usr/bin/ditto", ["-c", "-k", home(design.id).path, file.path])
    }

    /// Installs a theme file, replacing a theme with the same id. Only theme.json and the files
    /// it names come in, by plain names, and none larger than `largestFile`.
    @discardableResult
    public func install(_ file: URL) throws -> ThemeDesign {
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("theme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stage) }
        do {
            try SaveBackup.run("/usr/bin/ditto", ["-x", "-k", file.path, stage.path])
        } catch {
            throw Failure(description: "\(file.lastPathComponent) is not a theme file")
        }
        // The zip may hold the folder itself or its contents.
        guard let json = FileManager.default.enumerator(at: stage, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "theme.json" }),
              var design = try? JSONDecoder().decode(ThemeDesign.self, from: Data(contentsOf: json)) else {
            throw Failure(description: "\(file.lastPathComponent) is not a theme file")
        }
        let source = json.deletingLastPathComponent()
        design.id = Self.plainName(design.id) ?? UUID().uuidString.lowercased()
        func take(_ name: String?) -> URL? {
            guard let name, let safe = Self.plainName(name) else { return nil }
            let url = source.appendingPathComponent(safe)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= Self.largestFile else { return nil }
            return url
        }
        let background = take(design.background), music = take(design.music)
        design.background = nil
        design.music = nil
        try? FileManager.default.removeItem(at: home(design.id))
        return try save(design, background: background, music: music)
    }

    private func home(_ id: String) -> URL { folder.appendingPathComponent(id) }

    private func copy(_ file: URL, as stem: String, into home: URL, replacing old: String?) throws -> String {
        let name = stem + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension.lowercased())
        let target = home.appendingPathComponent(name)
        if let old, let safe = Self.plainName(old) { try? FileManager.default.removeItem(at: home.appendingPathComponent(safe)) }
        if file.standardizedFileURL != target.standardizedFileURL {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: file, to: target)
        }
        return name
    }

    /// A name with no folders in it, or nil.
    static func plainName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.hasPrefix("."), trimmed.count <= 128 else { return nil }
        return trimmed
    }
}
