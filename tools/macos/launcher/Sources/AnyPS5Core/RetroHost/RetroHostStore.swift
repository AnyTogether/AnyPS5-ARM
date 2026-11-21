import Foundation

/// One file of a host release on GitHub.
public struct RetroHostAsset: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let size: Int64
    /// GitHub's SHA-256 of the file in hex (its `digest`), nil when the API gave none.
    public let sha256: String?

    public init(name: String, url: URL, size: Int64, sha256: String? = nil) {
        self.name = name
        self.url = url
        self.size = size
        self.sha256 = sha256
    }
}

/// A release of the emulator host on GitHub, as its API lists it.
public struct RetroHostUpstreamRelease: Equatable, Sendable {
    public let tag: String
    public let prerelease: Bool
    public let assets: [RetroHostAsset]

    public init(tag: String, prerelease: Bool = false, assets: [RetroHostAsset]) {
        self.tag = tag
        self.prerelease = prerelease
        self.assets = assets
    }

    /// The tag without its v: 1.0.0.
    public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    public func named(_ name: String) -> RetroHostAsset? { assets.first { $0.name == name } }

    /// SHA256SUMS and SHA256SUMS.sig, when the release has both.
    public var signatureFiles: (sums: RetroHostAsset, signature: RetroHostAsset)? {
        guard let sums = named(ReleaseSigning.sumsName), let signature = named(ReleaseSigning.signatureName) else { return nil }
        return (sums, signature)
    }
}

/// Why a download of the host stopped, by kind, as the row in Settings › Emulators tells it.
public struct RetroHostDownloadError: Error, Equatable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        /// No signed release for this system: "not available yet".
        case notAvailable
        /// A signature or a sum did not match.
        case signature
        case network
        case cancelled
        /// The release was not what it should be, or could not be put in place.
        case badLayout
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { message }
}

/// A release `RetroHostStore.fetch` downloaded: the folder its files are in, and the tag it was
/// published under, which its signed version must match on install too.
public struct RetroHostDownload: Equatable, Sendable {
    public let folder: URL
    public let tag: String
}

/// The emulator host the launcher downloaded from the host repository's signed GitHub releases,
/// as on Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_host_store.dart), in
/// ~/Library/Application Support/AnyPS5/RetroHost beside the toolkits:
///
/// ```text
/// RetroHost/
///     host/          the unpacked zip, with SHA256SUMS, SHA256SUMS.sig, the .files and
///                    .release-tag (the tag it was published under) beside it
///     host.new/      a host being unpacked (RetroHostRelease.install)
///     host.old/      the host it replaces, until it can be removed
///     .downloads/    files on their way, kept to carry on after a stop
/// ```
///
/// It is the launcher's own storage, which only the user can write (protocol.md "Finding and
/// checking the host"). Nothing is downloaded unasked: `fetch` runs when the player asks for it.
public struct RetroHostStore: Sendable {
    /// Where the host releases are published.
    public static let repository = "AnyTogether/anyps5-retro-host"
    public static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AnyPS5/RetroHost")

    public let root: URL
    /// The keys a release must be signed with; the launcher's built-in keys when nil.
    public let keys: [ReleaseSigning.Key]?
    /// The system whose files are used; nil where no host is released.
    public let system: RetroHostSystem?

    public init(root: URL = RetroHostStore.defaultRoot, keys: [ReleaseSigning.Key]? = nil,
                system: RetroHostSystem? = RetroHostSystem.current) {
        self.root = root
        self.keys = keys
        self.system = system
    }

    public var folder: URL { root.appendingPathComponent("host") }
    var downloads: URL { root.appendingPathComponent(".downloads") }

    /// The host to start, when its files are there; it is checked before each start (`check()`). A
    /// host left in `host.old` by a launcher stopped in the middle of putting a new one in place is
    /// put back first (`RetroHostRelease.restore`). Its `ps2Core` is the release's LRPS2 when the
    /// release's `.files` lists one, and nil otherwise, even with a stray `pcsx2_libretro` file in
    /// the folder.
    public func installed() -> RetroHostInstall? {
        guard let target = system else { return nil }
        RetroHostRelease.restore(folder)
        guard version != nil else { return nil }
        let host = folder.appendingPathComponent(target.executable).path
        let core = folder.appendingPathComponent(target.core).path
        guard GameLibrary.isFile(host), GameLibrary.isFile(core) else { return nil }
        let ps2Core = folder.appendingPathComponent(target.ps2Core).path
        return RetroHostInstall(host: host, core: core,
                                ps2Core: RetroHostRelease.installedHasPs2Core(folder, system: target) ? ps2Core : nil, checked: true)
    }

    /// The installed host's version as its SHA256SUMS names it, for showing; not checked.
    public var version: RetroHostVersion? { system.flatMap { RetroHostRelease.installedVersion(folder, system: $0) } }

    /// The checks before a start (`RetroHostRelease.checkBeforeStart`); the host's file stays held
    /// in the result until the host it starts has exited.
    public func check() async throws -> RetroHostChecked {
        try await RetroHostRelease.checkBeforeStart(folder, keys: keys, system: system)
    }

    /// The release to install from `releases` (newest first, as `releases(session:)` gives them):
    /// the newest that is not a pre-release, is tagged `v<version>` at or above the launcher's
    /// minimum, and has SHA256SUMS and SHA256SUMS.sig; nil when there is none.
    public static func newest(_ releases: [RetroHostUpstreamRelease]) -> RetroHostUpstreamRelease? {
        releases.first { release in
            guard !release.prerelease, release.signatureFiles != nil, release.tag.hasPrefix("v"),
                  let version = RetroHostVersion(release.version) else { return false }
            return version >= RetroHostRelease.minimumVersion
        }
    }

    /// The releases GitHub lists (as many as it gives at once), newest version first, without
    /// drafts.
    public static func releases(session: URLSession = .shared,
                                api: URL = URL(string: "https://api.github.com")!) async throws -> [RetroHostUpstreamRelease] {
        var request = URLRequest(url: api.appendingPathComponent("repos/\(repository)/releases"), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        if var parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
            parts.queryItems = [URLQueryItem(name: "per_page", value: "100")]
            request.url = parts.url
        }
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AnyPS5", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let answer: (Data, URLResponse)
        do {
            answer = try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw RetroHostDownloadError(.cancelled, "the download was stopped") }
            throw RetroHostDownloadError(.network, "GitHub could not be reached: \(error.localizedDescription)")
        }
        let (data, response) = answer
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw RetroHostDownloadError(.network, "GitHub sent no releases")
        }
        let releases = list.compactMap { entry -> RetroHostUpstreamRelease? in
            guard entry["draft"] as? Bool != true, let tag = entry["tag_name"] as? String else { return nil }
            let assets = (entry["assets"] as? [[String: Any]] ?? []).compactMap { asset -> RetroHostAsset? in
                guard let name = asset["name"] as? String, let link = asset["browser_download_url"] as? String,
                      let url = URL(string: link), let size = (asset["size"] as? NSNumber)?.int64Value else { return nil }
                let digest = asset["digest"] as? String
                let sha = digest.flatMap { $0.hasPrefix("sha256:") && $0.count == 71 ? String($0.dropFirst(7)).lowercased() : nil }
                return RetroHostAsset(name: name, url: url, size: size, sha256: sha)
            }
            return RetroHostUpstreamRelease(tag: tag, prerelease: entry["prerelease"] as? Bool ?? false, assets: assets)
        }
        return releases.sorted { a, b in
            switch (RetroHostVersion(a.version), RetroHostVersion(b.version)) {
            case (let x?, let y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.tag > b.tag
            }
        }
    }

    /// Downloads `release` into `.downloads/<tag>` and gives that folder with the tag, once its
    /// signature is checked and its files match the signed sums; `putInPlace` then installs it.
    ///
    /// The signature comes first: SHA256SUMS and SHA256SUMS.sig are fetched and checked before
    /// anything else, with the version they sign held to the release's tag, and this system's zip
    /// and `.files` are fetched against the digests the signed sums give them. A release without a
    /// signature, or without files for this system, is not available; there is no way to take it
    /// unsigned. A redirect from https to plain http is refused. Files fetched before a stop are
    /// kept, so the next try carries on. Cancelling the calling task stops it.
    public func fetch(_ release: RetroHostUpstreamRelease?, configuration: URLSessionConfiguration = .default,
                      progress: @escaping @Sendable (_ received: Int64, _ total: Int64) -> Void = { _, _ in }) async throws -> RetroHostDownload {
        guard let target = system else { throw RetroHostDownloadError(.notAvailable, "no emulator host is released for this system") }
        guard let release, let signatureFiles = release.signatureFiles else {
            throw RetroHostDownloadError(.notAvailable, "no signed emulator host has been published yet")
        }
        let download = downloads.appendingPathComponent(release.tag)
        try FileManager.default.createDirectory(at: download, withIntermediateDirectories: true)
        for asset in [signatureFiles.sums, signatureFiles.signature] {
            guard asset.size <= Int64(ReleaseSigning.largestFile) else {
                throw RetroHostDownloadError(.signature, "\(asset.name) of \(release.tag) is too large")
            }
            try await Self.get(asset, into: download, sha256: asset.sha256, configuration: configuration) { _ in }
        }
        let signed: RetroHostSignedRelease
        do {
            signed = try RetroHostRelease.signed(
                sums: try Data(contentsOf: download.appendingPathComponent(ReleaseSigning.sumsName)),
                signature: try Data(contentsOf: download.appendingPathComponent(ReleaseSigning.signatureName)),
                tag: release.tag, keys: keys, system: target)
        } catch let failure as RetroHostReleaseFailure {
            forget(download)
            throw RetroHostDownloadError(failure.notReleased ? .notAvailable : .signature, "\(release.tag): \(failure.message)")
        }
        var assets: [RetroHostAsset] = []
        for name in [signed.filesName, signed.zipName] {
            guard let asset = release.named(name) else { throw RetroHostDownloadError(.notAvailable, "\(release.tag) has no \(name)") }
            assets.append(asset)
        }
        let total = assets.reduce(Int64(0)) { $0 + $1.size }
        var before: Int64 = 0
        for asset in assets {
            let start = before
            try await Self.get(asset, into: download, sha256: signed.sums.digest(for: asset.name), configuration: configuration) { fraction in
                progress(start + Int64(Double(asset.size) * fraction), total)
            }
            before += asset.size
        }
        try Task.checkCancellation()
        return RetroHostDownload(folder: download, tag: release.tag)
    }

    /// One file of a release into `folder`, going on from what an earlier try kept (and tried
    /// again by itself, DownloadRetry), then checked against its size and `sha256`. A file that
    /// does not match is deleted.
    static func get(_ asset: RetroHostAsset, into folder: URL, sha256: String?, configuration: URLSessionConfiguration,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
        let file = folder.appendingPathComponent(asset.name)
        if FontDownloads.size(of: file) == asset.size, let sha256, (try? FileDigest.sha256(file)) == sha256 { return progress(1) }
        if FontDownloads.size(of: file) > asset.size { try? FileManager.default.removeItem(at: file) }
        do {
            // Tried again by itself when it fails on the way, going on from what came.
            try await DownloadRetry.run(url: asset.url, file: file, expected: asset.size, httpsOnly: true, configuration: configuration, progress: progress)
        } catch let error as URLError where error.code == .cancelled {
            if Task.isCancelled { throw RetroHostDownloadError(.cancelled, "the download was stopped") }
            throw RetroHostDownloadError(.network, "\(asset.name) could not be downloaded")
        } catch let error as FontDownloadError {
            throw RetroHostDownloadError(.network, "\(asset.name): \(error.message)")
        } catch {
            if Task.isCancelled { throw RetroHostDownloadError(.cancelled, "the download was stopped") }
            throw RetroHostDownloadError(.network, "\(asset.name) could not be downloaded: \(error.localizedDescription)")
        }
        try Task.checkCancellation()
        guard FontDownloads.size(of: file) == asset.size else {
            throw RetroHostDownloadError(.network, "the download of \(asset.name) stopped short")
        }
        if let sha256, (try? FileDigest.sha256(file)) != sha256 {
            try? FileManager.default.removeItem(at: file)
            throw RetroHostDownloadError(.signature, "\(asset.name) does not match the signed release")
        }
        progress(1)
    }

    /// Installs what `fetch` downloaded in place of the installed host, through
    /// `RetroHostRelease.install`, which checks it all again from the files on disk before it
    /// unpacks, its signed version against the tag included; gives its version. Stop the host
    /// first.
    public func putInPlace(_ download: RetroHostDownload) async throws -> RetroHostVersion {
        let version: RetroHostVersion
        do {
            version = try await RetroHostRelease.install(download.folder, into: folder, tag: download.tag, keys: keys, system: system)
        } catch let failure as RetroHostReleaseFailure {
            throw RetroHostDownloadError(.badLayout, failure.message)
        } catch {
            throw RetroHostDownloadError(.badLayout, "the host could not be written: \(error.localizedDescription)")
        }
        forget(downloads)
        return version
    }

    private func forget(_ folder: URL) {
        // Left for the next download when it cannot be removed.
        try? FileManager.default.removeItem(at: folder)
    }
}
