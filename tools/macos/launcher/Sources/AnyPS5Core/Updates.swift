import Foundation

/// New releases of the launcher on GitHub, and replacing this app with one.
///
/// Two update channels: Stable follows the release GitHub calls latest; Nightly the newest
/// release including pre-releases. Nightly builds are tagged
/// `v<next release>-arm-nightly.<YYYYMMDD>.<n>` (tools/macos/publish_nightly.sh), the next
/// release being the last one with its last number raised and n counting the day's builds from
/// 1, so that they sort after the release before them and before the release they lead to:
/// 0.2.16 < 0.2.16 + 766 commits < 0.2.17-nightly.20261025.1 < 0.2.17-nightly.20261025.2 <
/// 0.2.17-nightly.20261026.1 < 0.2.17.
public enum Updates {
    public static let latestURL = URL(string: "https://api.github.com/repos/AnyTogether/AnyPS5-ARM/releases/latest")!
    public static let releasesURL = URL(string: "https://api.github.com/repos/AnyTogether/AnyPS5-ARM/releases?per_page=30")!
    public static let assetName = "AnyPS5-macOS.zip"

    public enum Channel: String, Codable, CaseIterable, Sendable {
        case stable, nightly
    }

    public struct Release: Equatable, Sendable {
        public var tag: String
        /// The release number alone, such as 0.2.6, or with its nightly part, such as
        /// 0.2.17-nightly.20261025.1.
        public var version: String
        public var page: URL
        public var download: URL?
        public var size: Int?
        public var prerelease: Bool
        public var published: Date?
        /// The release's SHA256SUMS and SHA256SUMS.sig; nil when it is not signed, and then it is
        /// never installed.
        public var signature: ReleaseSigning.Assets?

        public init(tag: String, version: String, page: URL, download: URL?, size: Int?, prerelease: Bool = false, published: Date? = nil,
                    signature: ReleaseSigning.Assets? = nil) {
            self.tag = tag
            self.version = version
            self.page = page
            self.download = download
            self.size = size
            self.prerelease = prerelease
            self.published = published
            self.signature = signature
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// A launcher version or release tag, in the order releases come out: "v0.2.16-arm",
    /// "0.2.16-arm-766-gee1fab911" (git describe between releases),
    /// "v0.2.17-arm-nightly.20261025.1", and git describe past a nightly tag.
    public struct Version: Comparable, Sendable, CustomStringConvertible {
        /// The release number, at least three parts.
        public var numbers: [Int]
        /// A nightly build of `numbers` (before it is released): its day (YYYYMMDD) and its
        /// count that day; nil for the release itself.
        public var nightly: (day: Int, count: Int)?
        /// Commits past the tag (git describe).
        public var build: Int

        public init?(_ text: String) {
            let text = text.hasPrefix("v") ? String(text.dropFirst()) : text
            let head = text.prefix { $0.isNumber || $0 == "." }
            let numbers = head.split(separator: ".").compactMap { Int($0) }
            guard !numbers.isEmpty, numbers.count == head.split(separator: ".", omittingEmptySubsequences: false).count else { return nil }
            self.numbers = numbers + Array(repeating: 0, count: max(0, 3 - numbers.count))
            let parts = text.split(separator: "-")
            nightly = nil
            if let part = parts.first(where: { $0.hasPrefix("nightly.") }) {
                let fields = part.dropFirst("nightly.".count).split(separator: ".", omittingEmptySubsequences: false)
                guard (1...2).contains(fields.count), let day = Int(fields[0]), fields[0].count == 8 else { return nil }
                guard let count = fields.count == 2 ? Int(fields[1]) : 0 else { return nil }
                nightly = (day, count)
            }
            // git describe appends -<commits since the tag>-g<hash>.
            build = parts.count >= 3 && parts.last?.hasPrefix("g") == true ? Int(parts[parts.count - 2]) ?? 0 : 0
        }

        /// The release number, a nightly's part after it: 0.2.17 or 0.2.17-nightly.20261025.1.
        public var description: String {
            numbers.map(String.init).joined(separator: ".") + (nightly.map { "-nightly.\($0.day).\($0.count)" } ?? "")
        }

        public var isNightly: Bool { nightly != nil }

        public static func < (a: Version, b: Version) -> Bool {
            if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
            switch (a.nightly, b.nightly) {
            case (nil, .some): return false
            case (.some, nil): return true
            case let (.some(x), .some(y)) where x != y: return (x.day, x.count) < (y.day, y.count)
            default: return a.build < b.build
            }
        }

        public static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
    }

    /// One release as GitHub describes it, nil for a draft, a tag that is no version or another
    /// shape; a pre-release only when `prerelease` allows it.
    static func release(from json: [String: Any], prerelease allowed: Bool) -> Release? {
        guard let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, let version = Version(tag) else { return nil }
        let prerelease = json["prerelease"] as? Bool == true
        guard allowed || !prerelease else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { $0["name"] as? String == assetName }
        return Release(tag: tag, version: version.description, page: page,
                       download: (asset?["browser_download_url"] as? String).flatMap(URL.init(string:)), size: asset?["size"] as? Int,
                       prerelease: prerelease, published: (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                       signature: ReleaseSigning.assets(in: assets))
    }

    /// The release GitHub calls latest; drafts, prereleases and other answers (an error, a rate
    /// limit) are nil.
    public static func release(from data: Data) -> Release? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return release(from: json, prerelease: false)
    }

    /// GitHub's list of releases, pre-releases included, drafts left out; nil for an answer that
    /// is no list.
    public static func releases(from data: Data) -> [Release]? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return list.compactMap { release(from: $0, prerelease: true) }
    }

    /// The release a channel offers out of a list: the highest version carrying the app (a
    /// pre-release only on Nightly), the later published when two tie.
    public static func newest(_ releases: [Release], channel: Channel) -> Release? {
        releases.filter { $0.download != nil && (channel == .nightly || !$0.prerelease) }.max { a, b in
            guard let x = Version(a.tag), let y = Version(b.tag) else { return false }
            if x != y { return x < y }
            return (a.published ?? .distantPast) < (b.published ?? .distantPast)
        }
    }

    /// Whether the release tag is past the running version. A development build (git describe:
    /// 0.2.4-arm-766-g…) is past its own tag but before the next release, a nightly before the
    /// release it leads to: switching back to Stable never goes back to an older release.
    public static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let offered = Version(tag), let running = Version(current) else { return false }
        return running < offered
    }

    /// The latest release, when it is newer than `current`.
    public static func check(current: String, channel: Channel = .stable, session: URLSession = .shared) async -> Release? {
        guard case .newer(let release) = await lookup(current: current, channel: channel, session: session) else { return nil }
        return release
    }

    /// What a check found: a newer release, none (this one is the latest), or no answer.
    public enum Lookup: Equatable, Sendable {
        case newer(Release)
        case current
        case failed
    }

    /// Asks GitHub for the channel's newest release, never a cache, so a release just out is
    /// seen at once: the latest release on Stable, the list of releases on Nightly.
    public static func lookup(current: String, channel: Channel = .stable, session: URLSession = .shared) async -> Lookup {
        var request = URLRequest(url: channel == .stable ? latestURL : releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed }
        let found: Release?
        switch channel {
        case .stable:
            guard let release = release(from: data) else { return .failed }
            found = release
        case .nightly:
            guard let list = releases(from: data) else { return .failed }
            found = newest(list, channel: .nightly)
        }
        guard let found, isNewer(found.tag, than: current) else { return .current }
        return .newer(found)
    }

    /// The async download calls tell no delegate how far they are, so the task's own Progress is
    /// watched instead.
    static func download(_ url: URL, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let watching = Locked<NSKeyValueObservation?>(nil)
        defer { watching.value?.invalidate() }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { downloaded, response, error in
                if let error { return done.resume(throwing: error) }
                guard let downloaded, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return done.resume(throwing: Failure(description: "the download failed"))
                }
                // The downloaded file is deleted when this handler returns.
                do {
                    try FileManager.default.moveItem(at: downloaded, to: file)
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
            watching.value = task.progress.observe(\.fractionCompleted) { reported, _ in
                let fraction = reported.fractionCompleted
                if fraction > 0, fraction < 1 { progress(fraction) }
            }
            task.resume()
        }
        progress(1)
    }

    /// Checks the release's signature (SHA256SUMS.sig by a key built into this launcher), downloads
    /// it, checks the download against the signed SHA256SUMS, unpacks it and checks that it is this
    /// app (`bundleIdentifier`) at a newer version. Returns the unpacked app, in a folder of its own
    /// under the temporary folder. An unsigned release is refused before anything is downloaded:
    /// every version newer than a launcher that checks signatures came out signed.
    public static func prepare(_ release: Release, bundleIdentifier: String, current: String, keys: [ReleaseSigning.Key] = ReleaseSigning.trustedKeys,
                               session: URLSession = .shared, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard let download = release.download else { throw Failure(description: "the release has no \(assetName)") }
        guard let signature = release.signature else {
            throw Failure(description: "AnyPS5 \(release.version) is not signed, so it was not installed; get it from \(release.page.absoluteString) only if you trust it")
        }
        let sums: ReleaseSigning.Sums
        do {
            sums = try await ReleaseSigning.fetch(signature, keys: keys, session: session)
        } catch let failure as ReleaseSigning.Failure {
            throw Failure(description: "the update was not installed: \(failure.description)")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(assetName)
        try await self.download(download, to: zip, progress: progress)
        do {
            try sums.check(zip, as: assetName)
        } catch let failure as ReleaseSigning.Failure {
            try? FileManager.default.removeItem(at: folder)
            throw Failure(description: "the update was not installed: \(failure.description)")
        }
        let unpacked = folder.appendingPathComponent("app")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let app = unpacked.appendingPathComponent("AnyPS5.app")
        try check(app, bundleIdentifier: bundleIdentifier, current: current)
        return app
    }

    static func check(_ app: URL, bundleIdentifier: String, current: String) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw Failure(description: "the download holds no AnyPS5.app")
        }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw Failure(description: "the download is another app") }
        guard let version = info["CFBundleShortVersionString"] as? String, isNewer(version, than: current) else {
            throw Failure(description: "the download is not newer than this version")
        }
    }

    /// A shell script that waits for `pid` to end, puts `new` where `old` is (keeping `old` if
    /// that fails) and then runs `relaunch` on it.
    static func replacementScript(old: URL, new: URL, pid: Int32, relaunch: String = "/usr/bin/open") -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let previous = old.path + ".previous"
        return """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(quoted(previous))
        if mv \(quoted(old.path)) \(quoted(previous)) && /usr/bin/ditto \(quoted(new.path)) \(quoted(old.path)); then
            rm -rf \(quoted(previous)) \(quoted(new.deletingLastPathComponent().deletingLastPathComponent().path))
            /usr/bin/xattr -dr com.apple.quarantine \(quoted(old.path)) 2>/dev/null
        else
            rm -rf \(quoted(old.path))
            mv \(quoted(previous)) \(quoted(old.path))
        fi
        \(relaunch) \(quoted(old.path))
        """
    }

    /// What the replacement runs on the new app: `open` for Restart Now, nothing for Later (the
    /// update goes in as the launcher quits, and the next launch is the new version).
    public static func relaunchCommand(_ relaunch: Bool) -> String { relaunch ? "/usr/bin/open" : "true" }

    /// Starts the replacement; the caller quits right after so that `pid` (itself) ends.
    public static func replace(_ old: URL, with new: URL, pid: Int32, relaunch: Bool = true) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", replacementScript(old: old, new: new, pid: pid, relaunch: relaunchCommand(relaunch))]
        try process.run()
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "\(tool) failed") }
    }
}
