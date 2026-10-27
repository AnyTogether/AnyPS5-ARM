import CryptoKit
import Foundation

/// toolkit.json, which tools/macos/toolkit_layout.sh writes into a toolkit made for download:
/// what it is and the sha256 of every other file in it.
public struct ToolkitManifest: Codable, Equatable, Sendable {
    public var format: Int
    /// The same as version.txt: "<release version>-<fingerprint>".
    public var version: String
    public var engineCommit: String?
    public var upstreamBase: String?
    public var buildDate: String?
    /// The oldest launcher that may use it.
    public var minimumLauncher: String?
    /// sha256 (hex) by path inside the toolkit folder.
    public var files: [String: String]

    public init(format: Int = ToolkitManifest.supportedFormat, version: String, engineCommit: String? = nil, upstreamBase: String? = nil,
                buildDate: String? = nil, minimumLauncher: String? = nil, files: [String: String] = [:]) {
        self.format = format
        self.version = version
        self.engineCommit = engineCommit
        self.upstreamBase = upstreamBase
        self.buildDate = buildDate
        self.minimumLauncher = minimumLauncher
        self.files = files
    }

    /// The newest format this launcher reads.
    public static let supportedFormat = 1

    public var built: Date? { buildDate.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

extension Toolkit {
    public var manifest: ToolkitManifest? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("toolkit.json")) else { return nil }
        return try? JSONDecoder().decode(ToolkitManifest.self, from: data)
    }

    /// What keeps `root` from being a toolkit the launcher can unlock games with, nil when
    /// nothing does: the relinker (executable), at least one library, the Vulkan loader with
    /// MoltenVK and its manifest, and the patches folder.
    public static func layoutProblem(at root: URL) -> String? {
        let fileManager = FileManager.default
        var folder: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &folder), folder.boolValue else { return "not a folder" }
        let relinker = root.appendingPathComponent("relinker")
        guard fileManager.fileExists(atPath: relinker.path) else { return "no relinker" }
        guard fileManager.isExecutableFile(atPath: relinker.path) else { return "the relinker is not executable" }
        let libraries = (try? fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("libs").path)) ?? []
        guard libraries.contains(where: { $0.hasSuffix(".prx") }) else { return "no libs/*.prx" }
        for name in ["libvulkan.1.dylib", "libMoltenVK.dylib", "MoltenVK_icd.json"] where !fileManager.fileExists(atPath: root.appendingPathComponent("vulkan/" + name).path) {
            return "no vulkan/" + name
        }
        guard fileManager.fileExists(atPath: root.appendingPathComponent("patches").path, isDirectory: &folder), folder.boolValue else { return "no patches folder" }
        return nil
    }

    /// What the build script writes after the release version: the first 12 hex digits of the
    /// sha256 of the relinker, the libraries and the patches, one after the other.
    static func fingerprint(of root: URL) -> String? {
        let fileManager = FileManager.default
        let relinker = root.appendingPathComponent("relinker")
        guard fileManager.fileExists(atPath: relinker.path) else { return nil }
        func files(_ folder: String, _ suffix: String) -> [URL] {
            ((try? fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? [])
                .filter { $0.hasSuffix(suffix) }.sorted().map { root.appendingPathComponent(folder).appendingPathComponent($0) }
        }
        var hasher = SHA256()
        for file in [relinker] + files("libs", ".prx") + files("patches", ".json") {
            guard (try? FileDigest.update(&hasher, with: file)) != nil else { return nil }
        }
        return String(FileDigest.hex(hasher.finalize()).prefix(12))
    }

    /// The release part of a toolkit version, without its fingerprint.
    public static func release(of version: String) -> String {
        let parts = version.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2, let last = parts.last, last.count == 12, last.allSatisfy(\.isHexDigit) else { return version }
        return parts.dropLast().joined(separator: "-")
    }

    /// A version as the launcher shows it: the release and six digits of the fingerprint.
    /// Between releases git describe's "-<commits>-g<hash>" becomes "+<commits>".
    public static func shortVersion(_ version: String) -> String {
        var release = release(of: version)
        guard release != version else { return version }
        let parts = release.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count >= 3, let hash = parts.last, hash.hasPrefix("g"), hash.dropFirst().allSatisfy(\.isHexDigit), Int(parts[parts.count - 2]) != nil {
            release = parts.dropLast(2).joined(separator: "-") + "+" + parts[parts.count - 2]
        }
        return release + " · " + version.suffix(12).prefix(6)
    }
}

enum FileDigest {
    static func update(_ hasher: inout SHA256, with file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty { hasher.update(data: data) }
    }

    static func sha256(_ file: URL) throws -> String {
        var hasher = SHA256()
        try update(&hasher, with: file)
        return hex(hasher.finalize())
    }

    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}

/// Checks a toolkit folder against its manifest: every file listed, with its sha256, and
/// nothing else (no links, no extra files, hidden or not).
public enum ToolkitVerifier {
    /// How many times a folder was hashed whole, for the tests.
    nonisolated(unsafe) static var fullChecks = 0

    public static func verify(_ folder: URL, manifest: ToolkitManifest) throws {
        fullChecks += 1
        guard manifest.format <= ToolkitManifest.supportedFormat else { throw InstallError("toolkit format \(manifest.format) is newer than this launcher reads") }
        if let outside = manifest.files.keys.first(where: { !isInside($0) }) { throw InstallError("the toolkit names \(outside), outside its folder") }
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: folder.path) else { throw InstallError("the toolkit cannot be read") }
        var seen = Set<String>()
        for case let relative as String in enumerator {
            let item = folder.appendingPathComponent(relative)
            let type = try fileManager.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType
            if type == .typeDirectory { continue }
            guard type == .typeRegular else { throw InstallError("\(relative) is not a plain file") }
            if relative == "toolkit.json" { continue }
            guard let expected = manifest.files[relative] else { throw InstallError("\(relative) is not in the toolkit's manifest") }
            guard try FileDigest.sha256(item) == expected.lowercased() else { throw InstallError("\(relative) does not match the toolkit's manifest") }
            seen.insert(relative)
        }
        if let missing = Set(manifest.files.keys).subtracting(seen).sorted().first { throw InstallError("\(missing) is missing from the toolkit") }
    }

    static func isInside(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}

/// The toolkits attached to the launcher's GitHub releases (AnyPS5-toolkit-macos-<release>.zip).
public enum EngineCatalogue {
    public static let releasesURL = URL(string: "https://api.github.com/repos/AnyTogether/AnyPS5-ARM/releases?per_page=40")!
    public static let assetPrefix = "AnyPS5-toolkit-macos-"

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// The release version in the asset's name, such as 0.2.16-arm.
        public var release: String
        public var tag: String
        public var title: String
        /// The first lines of the release notes, plain.
        public var summary: String
        public var date: Date?
        public var page: URL
        public var download: URL
        public var size: Int?
        /// The asset's sha256 as GitHub reports it, when it does.
        public var digest: String?
        public var prerelease: Bool
        /// The release's SHA256SUMS and SHA256SUMS.sig, nil when it is not signed.
        public var signature: ReleaseSigning.Assets?

        public var id: String { release }

        /// The asset's name, as the release's SHA256SUMS lists it.
        public var assetName: String { EngineCatalogue.assetPrefix + release + ".zip" }

        /// Signed; unsigned but older than signing (allowed with a warning); or unsigned and
        /// refused.
        public var trust: ReleaseSigning.Trust { ReleaseSigning.trust(release: release, signed: signature != nil) }

        public init(release: String, tag: String, title: String, summary: String, date: Date?, page: URL, download: URL, size: Int?, digest: String?, prerelease: Bool,
                    signature: ReleaseSigning.Assets? = nil) {
            self.release = release
            self.tag = tag
            self.title = title
            self.summary = summary
            self.date = date
            self.page = page
            self.download = download
            self.size = size
            self.digest = digest
            self.prerelease = prerelease
            self.signature = signature
        }
    }

    /// The toolkits of GitHub's list of releases, newest first; drafts are left out, and an
    /// answer that is no list (an error, a rate limit) is nil.
    public static func entries(from data: Data) -> [Entry]? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        var entries: [Entry] = []
        for release in list where release["draft"] as? Bool != true {
            guard let tag = release["tag_name"] as? String, let page = (release["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let assets = release["assets"] as? [[String: Any]] ?? []
            let signature = ReleaseSigning.assets(in: assets)
            for asset in assets {
                guard let name = asset["name"] as? String, name.hasPrefix(assetPrefix), name.hasSuffix(".zip"),
                      let download = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else { continue }
                let version = String(name.dropFirst(assetPrefix.count).dropLast(4))
                guard ToolkitStore.isSafeName(version), !entries.contains(where: { $0.release == version }) else { continue }
                let digest = (asset["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
                entries.append(Entry(release: version, tag: tag, title: release["name"] as? String ?? tag, summary: summary(of: release["body"] as? String ?? ""),
                                     date: (release["published_at"] as? String).flatMap(dates.date(from:)), page: page, download: download,
                                     size: asset["size"] as? Int, digest: digest, prerelease: release["prerelease"] as? Bool == true,
                                     signature: signature))
            }
        }
        return entries
    }

    /// The release notes' first lines without their Markdown, joined, at most 140 characters.
    public static func summary(of body: String) -> String {
        var pieces: [String] = []
        var length = 0
        for raw in body.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || ["#", "---", "```", "<!--", "|", ">"].contains(where: line.hasPrefix) { continue }
            line = line.replacingOccurrences(of: #"^([-*+]|\d+\.)\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            for mark in ["**", "__", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            pieces.append(line)
            length += line.count + 3
            if length >= 140 { break }
        }
        let text = pieces.joined(separator: " · ")
        return text.count <= 140 ? text : String(text.prefix(139)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The toolkits the engine picker offers on an update channel: nightly toolkits (those of
    /// pre-releases) only on Nightly.
    public static func offered(_ entries: [Entry], channel: Updates.Channel) -> [Entry] {
        channel == .nightly ? entries : entries.filter { !$0.prerelease }
    }

    /// GitHub's list of releases, never a cache; nil without an answer.
    public static func fetch(session: URLSession = .shared) async -> [Entry]? {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return entries(from: data)
    }
}

/// A toolkit downloaded into the store, verified when it was unpacked.
public struct InstalledToolkit: Equatable, Sendable {
    public let version: String
    public let folder: URL
    public let manifest: ToolkitManifest

    public init(version: String, folder: URL, manifest: ToolkitManifest) {
        self.version = version
        self.folder = folder
        self.manifest = manifest
    }

    public var release: String { Toolkit.release(of: version) }
    public var toolkit: Toolkit { Toolkit(root: folder) }
}

/// The downloaded toolkits, one folder each by version, in
/// ~/Library/Application Support/AnyPS5/Toolkits, and the last catalogue seen.
public struct ToolkitStore: Sendable {
    public let folder: URL

    public init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Toolkits")) {
        self.folder = folder
    }

    /// A version that can name a folder: letters, digits, dots, dashes and underscores, not
    /// starting with a dot.
    public static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("..")
            && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._-".unicodeScalars.contains($0) }
    }

    /// The toolkits in the store, newest build first.
    public func installed() -> [InstalledToolkit] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let found = names.filter(ToolkitStore.isSafeName).compactMap { name -> InstalledToolkit? in
            let root = folder.appendingPathComponent(name)
            guard let manifest = Toolkit(root: root).manifest, manifest.version == name, Toolkit.layoutProblem(at: root) == nil else { return nil }
            return InstalledToolkit(version: name, folder: root, manifest: manifest)
        }
        return found.sorted { ($0.manifest.buildDate ?? "", $0.version) > ($1.manifest.buildDate ?? "", $1.version) }
    }

    /// The downloaded toolkit of a release, if there is one.
    public func installed(release: String) -> InstalledToolkit? {
        installed().first { $0.release == release }
    }

    /// The toolkit of `version`, its files checked against its manifest again, for use.
    public func verifiedToolkit(version: String) throws -> Toolkit {
        guard ToolkitStore.isSafeName(version) else { throw InstallError("no toolkit \(version)") }
        let root = folder.appendingPathComponent(version)
        guard let manifest = Toolkit(root: root).manifest, manifest.version == version else { throw InstallError("toolkit \(version) is not downloaded") }
        if let problem = Toolkit.layoutProblem(at: root) { throw InstallError("toolkit \(version): \(problem)") }
        // Hashed whole once per change: the note of the last check names every file's size,
        // dates and inode, and the change time no one can set back.
        let note = folder.appendingPathComponent(".verified").appendingPathComponent(version)
        let signature = ToolkitStore.signature(of: root)
        if let signature, (try? String(contentsOf: note, encoding: .utf8)) == signature { return Toolkit(root: root) }
        try? FileManager.default.removeItem(at: note)
        try ToolkitVerifier.verify(root, manifest: manifest)
        if let signature {
            try? FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? signature.write(to: note, atomically: true, encoding: .utf8)
        }
        return Toolkit(root: root)
    }

    /// Every entry of a toolkit folder with its type, size, inode, modification and change
    /// times, hashed: anything written into the folder since changes it.
    static func signature(of root: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return nil }
        var lines: [String] = []
        var info = stat()
        guard lstat(root.path, &info) == 0 else { return nil }
        lines.append(". \(info.st_mode) \(info.st_ino) \(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)")
        for case let relative as String in enumerator {
            guard lstat(root.appendingPathComponent(relative).path, &info) == 0 else { return nil }
            lines.append("\(relative) \(info.st_mode) \(info.st_size) \(info.st_ino) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec) \(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)")
        }
        var hasher = SHA256()
        hasher.update(data: Data(lines.sorted().joined(separator: "\n").utf8))
        return FileDigest.hex(hasher.finalize())
    }

    /// Unpacks a downloaded toolkit into the store. `digest` (the release asset's sha256) is
    /// checked before anything is unpacked, `release` (from the asset's name) against what it
    /// holds; then every file against its manifest. Nothing in it runs before all of that passed.
    @discardableResult
    public func install(zip: URL, digest: String?, release: String?, launcherVersion: String) throws -> InstalledToolkit {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let digest, try FileDigest.sha256(zip) != digest.lowercased() { throw InstallError("the download does not match its release (sha256)") }
        try ToolkitStore.checkEntries(of: zip)
        let staging = folder.appendingPathComponent(".staging-" + UUID().uuidString)
        defer { try? fileManager.removeItem(at: staging) }
        try ToolkitStore.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        let root = try ToolkitStore.toolkitRoot(in: staging)
        guard let manifest = Toolkit(root: root).manifest else { throw InstallError("the download has no toolkit.json") }
        guard ToolkitStore.isSafeName(manifest.version) else { throw InstallError("the toolkit's version \(manifest.version) cannot be used") }
        if let release, Toolkit.release(of: manifest.version) != release { throw InstallError("the download holds \(manifest.version), not \(release)") }
        if let minimum = manifest.minimumLauncher, Updates.isNewer(minimum, than: launcherVersion) {
            throw InstallError("this engine needs AnyPS5 \(minimum) or newer")
        }
        try ToolkitVerifier.verify(root, manifest: manifest)
        guard Toolkit(root: root).version == manifest.version else { throw InstallError("version.txt does not match the toolkit's manifest") }
        if let problem = Toolkit.layoutProblem(at: root) { throw InstallError("the toolkit is incomplete: \(problem)") }
        Installer.clearMarks(root)
        let destination = folder.appendingPathComponent(manifest.version)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: root, to: destination)
        return InstalledToolkit(version: manifest.version, folder: destination, manifest: manifest)
    }

    /// Downloads a catalogue entry and installs it; the download is 90% of the progress.
    ///
    /// A signed release's signature is checked first and the download against its signed sums. An
    /// unsigned release published after signing began is refused; an older one only goes ahead
    /// with `allowUnsigned` (the user saw the warning) and is then checked with GitHub's sha256,
    /// which it must have.
    @discardableResult
    public func download(_ entry: EngineCatalogue.Entry, launcherVersion: String, allowUnsigned: Bool = false,
                         keys: [ReleaseSigning.Key] = ReleaseSigning.trustedKeys, session: URLSession = .shared,
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> InstalledToolkit {
        let digest = try await ToolkitStore.expectedDigest(of: entry, allowUnsigned: allowUnsigned, keys: keys, session: session)
        let fileManager = FileManager.default
        let downloads = folder.appendingPathComponent(".downloads")
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        let file = downloads.appendingPathComponent(UUID().uuidString + ".zip")
        defer {
            try? fileManager.removeItem(at: file)
            if (try? fileManager.contentsOfDirectory(atPath: downloads.path))?.isEmpty == true { try? fileManager.removeItem(at: downloads) }
        }
        try await Updates.download(entry.download, to: file) { progress($0 * 0.9) }
        let installed = try install(zip: file, digest: digest, release: entry.release, launcherVersion: launcherVersion)
        progress(1)
        return installed
    }

    /// The sha256 the download of `entry` must have, from its signed sums or (an older unsigned
    /// release the user agreed to) from GitHub; throws when it may not be downloaded at all.
    static func expectedDigest(of entry: EngineCatalogue.Entry, allowUnsigned: Bool, keys: [ReleaseSigning.Key], session: URLSession) async throws -> String {
        switch entry.trust {
        case .signed:
            guard let signature = entry.signature else { throw InstallError("engine \(entry.release) is not signed") }
            do {
                let sums = try await ReleaseSigning.fetch(signature, keys: keys, session: session)
                guard let digest = sums.digest(for: entry.assetName) else { throw ReleaseSigning.Failure("the signed release does not list \(entry.assetName)") }
                return digest
            } catch let failure as ReleaseSigning.Failure {
                throw InstallError("engine \(entry.release) was refused: \(failure.description)")
            }
        case .unsignedRefused:
            throw InstallError("engine \(entry.release) is not signed, though it came out after releases began to be signed: refused")
        case .unsignedOlder:
            guard allowUnsigned else { throw InstallError("engine \(entry.release) is unsigned (an older release)") }
            guard let digest = entry.digest else { throw InstallError("engine \(entry.release) has neither a signature nor a checksum from GitHub") }
            return digest
        }
    }

    public func remove(version: String) throws {
        guard ToolkitStore.isSafeName(version) else { throw InstallError("no toolkit \(version)") }
        try FileManager.default.removeItem(at: folder.appendingPathComponent(version))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(".verified").appendingPathComponent(version))
    }

    /// Removes every downloaded toolkit not in `keeping`; returns their versions.
    @discardableResult
    public func removeUnused(keeping: Set<String>) -> [String] {
        installed().map(\.version).filter { !keeping.contains($0) && (try? remove(version: $0)) != nil }
    }

    // MARK: Catalogue cache

    public struct CachedCatalogue: Codable, Equatable, Sendable {
        public var entries: [EngineCatalogue.Entry]
        public var checked: Date
    }

    var catalogueFile: URL { folder.appendingPathComponent(".catalogue.json") }

    /// The catalogue as it was last seen, for when GitHub cannot be reached.
    public func cachedCatalogue() -> CachedCatalogue? {
        guard let data = try? Data(contentsOf: catalogueFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedCatalogue.self, from: data)
    }

    public func saveCatalogue(_ entries: [EngineCatalogue.Entry], checked: Date) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(CachedCatalogue(entries: entries, checked: checked)) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: catalogueFile, options: .atomic)
    }

    // MARK: Unpacking

    /// Refuses an archive holding a link or a path that leaves its folder, before unpacking.
    static func checkEntries(of zip: URL) throws {
        let listing = try output("/usr/bin/zipinfo", [zip.path])
        if listing.split(separator: "\n").contains(where: { $0.first == "l" }) { throw InstallError("the download holds a link") }
        for name in try output("/usr/bin/zipinfo", ["-1", zip.path]).split(separator: "\n") {
            let path = name.hasSuffix("/") ? String(name.dropLast()) : String(name)
            guard ToolkitVerifier.isInside(path) else { throw InstallError("the download names \(path), outside its folder") }
        }
    }

    /// The unpacked folder holding toolkit.json: the archive's own folder or its single folder.
    static func toolkitRoot(in staging: URL) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: staging.appendingPathComponent("toolkit.json").path) { return staging }
        let items = ((try? fileManager.contentsOfDirectory(atPath: staging.path)) ?? []).filter { $0 != "__MACOSX" }
        guard items.count == 1, fileManager.fileExists(atPath: staging.appendingPathComponent(items[0]).appendingPathComponent("toolkit.json").path) else {
            throw InstallError("the download is not a toolkit")
        }
        return staging.appendingPathComponent(items[0])
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        _ = try output(tool, arguments)
    }

    static func output(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(process.terminationStatus))") }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Which toolkit unlocks a game: the one inside the app, a downloaded one by version, or the
/// folder the user picked (Settings → Engine).
public enum EngineChoice: Equatable, Hashable, Sendable {
    case builtIn
    case custom
    case downloaded(String)

    /// The launcher's default (Preferences) and a game's own choice (GameSettings.engine) as
    /// they are saved: nil or "builtin", "custom", or a downloaded version.
    public init(stored: String?) {
        switch stored {
        case nil, "builtin": self = .builtIn
        case "custom": self = .custom
        case let version?: self = .downloaded(version)
        }
    }

    /// How the default is saved (nil for the built-in toolkit).
    public var stored: String? {
        switch self {
        case .builtIn: return nil
        case .custom: return "custom"
        case .downloaded(let version): return version
        }
    }

    /// How a game's own choice is saved: nil follows the default, so built in is spelled out.
    public var gameStored: String { stored ?? "builtin" }

    /// A game's own choice over the default.
    public static func resolve(game: String?, default fallback: String?) -> EngineChoice {
        game.map(EngineChoice.init(stored:)) ?? EngineChoice(stored: fallback)
    }

    /// The chosen toolkit among those at hand; the built-in one when the choice is gone.
    public func toolkit(builtIn: Toolkit?, custom: Toolkit?, installed: [InstalledToolkit]) -> Toolkit? {
        switch self {
        case .builtIn: return builtIn
        case .custom: return custom ?? builtIn
        case .downloaded(let version): return installed.first { $0.version == version }?.toolkit ?? builtIn
        }
    }

    public func toolkit(builtIn: Toolkit?, custom: Toolkit?, store: ToolkitStore) -> Toolkit? {
        toolkit(builtIn: builtIn, custom: custom, installed: store.installed())
    }
}
