import Foundation

/// New releases of the launcher on GitHub, and replacing this app with one.
public enum Updates {
    public static let latestURL = URL(string: "https://api.github.com/repos/utkuhalis/AnyPS5-ARM/releases/latest")!
    public static let assetName = "AnyPS5-macOS.zip"

    public struct Release: Equatable, Sendable {
        public var tag: String
        /// The release number alone, such as 0.2.6.
        public var version: String
        public var page: URL
        public var download: URL?
        public var size: Int?

        public init(tag: String, version: String, page: URL, download: URL?, size: Int?) {
            self.tag = tag
            self.version = version
            self.page = page
            self.download = download
            self.size = size
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// The release GitHub calls latest; drafts, prereleases and other answers (an error, a rate
    /// limit) are nil.
    public static func release(from data: Data) -> Release? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let numbers = parse(tag) else { return nil }
        let asset = (json["assets"] as? [[String: Any]] ?? []).first { $0["name"] as? String == assetName }
        return Release(tag: tag, version: numbers.release.map(String.init).joined(separator: "."), page: page,
                       download: (asset?["browser_download_url"] as? String).flatMap(URL.init(string:)), size: asset?["size"] as? Int)
    }

    /// Whether the release tag is past the running version. A development build (git describe:
    /// 0.2.4-arm-766-g…) is past its own tag but before the next release.
    public static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let offered = parse(tag), let running = parse(current) else { return false }
        if offered.release != running.release { return offered.release.lexicographicallyPrecedes(running.release) == false }
        return offered.build > running.build
    }

    static func parse(_ version: String) -> (release: [Int], build: Int)? {
        let text = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let head = text.prefix { $0.isNumber || $0 == "." }
        let release = head.split(separator: ".").compactMap { Int($0) }
        guard !release.isEmpty, release.count == head.split(separator: ".").count else { return nil }
        // git describe appends -<commits since the tag>-g<hash>.
        let parts = text.split(separator: "-")
        let build = parts.count >= 3 && parts.last?.hasPrefix("g") == true ? Int(parts[parts.count - 2]) ?? 0 : 0
        return (release + Array(repeating: 0, count: max(0, 3 - release.count)), build)
    }

    /// The latest release, when it is newer than `current`.
    public static func check(current: String, session: URLSession = .shared) async -> Release? {
        guard case .newer(let release) = await lookup(current: current, session: session) else { return nil }
        return release
    }

    /// What a check found: a newer release, none (this one is the latest), or no answer.
    public enum Lookup: Equatable, Sendable {
        case newer(Release)
        case current
        case failed
    }

    /// Asks GitHub for the latest release, never a cache, so a release just out is seen at once.
    public static func lookup(current: String, session: URLSession = .shared) async -> Lookup {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let release = release(from: data) else { return .failed }
        return isNewer(release.tag, than: current) ? .newer(release) : .current
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

    /// Downloads and unpacks the release, and checks that it is this app (`bundleIdentifier`) at a
    /// newer version. Returns the unpacked app, in a folder of its own under the temporary folder.
    public static func prepare(_ release: Release, bundleIdentifier: String, current: String,
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        guard let download = release.download else { throw Failure(description: "the release has no \(assetName)") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AnyPS5-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(assetName)
        try await self.download(download, to: zip, progress: progress)
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

    /// Starts the replacement; the caller quits right after so that `pid` (itself) ends.
    public static func replace(_ old: URL, with new: URL, pid: Int32) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", replacementScript(old: old, new: new, pid: pid)]
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
