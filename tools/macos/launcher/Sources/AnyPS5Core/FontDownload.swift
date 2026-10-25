import CryptoKit
import Foundation

/// A font archive the launcher downloads the first time a game needs it: where it is, the
/// SHA-256 it must have and the files taken out of it, each with its own SHA-256.
public struct FontPackage: Sendable {
    public struct File: Sendable {
        /// The path inside the archive.
        public let member: String
        /// The name it gets in the fonts folder (what the engine looks for).
        public let name: String
        public let sha256: String
        public let size: Int64

        public init(member: String, name: String, sha256: String, size: Int64) {
            self.member = member
            self.name = name
            self.sha256 = sha256
            self.size = size
        }
    }

    public let url: URL
    public let sha256: String
    public let size: Int64
    public let files: [File]

    public init(url: URL, sha256: String, size: Int64, files: [File]) {
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.files = files
    }

    public var archiveName: String { url.lastPathComponent }
    /// What the files take once installed.
    public var installedSize: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Noto Sans CJK 2.004 from Noto's own release (github.com/notofonts/noto-cjk, SIL Open Font
    /// License 1.1): the collections of the four weights the engine opens. Each holds Japanese
    /// (face 0), Korean (1), Simplified Chinese (2), Traditional Chinese and Hong Kong in this
    /// order, as SystemFont.cpp expects.
    public static let notoCJK = FontPackage(
        url: URL(string: "https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/03_NotoSansCJK-OTC.zip")!,
        sha256: "528f4e1b25ff3badb0321b38d015d954c4c0de926c7830ef50e4a1948f6a3eed",
        size: 104_680_673,
        files: [
            File(member: "NotoSansCJK-Light.ttc", name: "NotoSansCJK-Light.ttc", sha256: "872def437cf8b9c41bf1736da891e34a8c25b764c0c4a51418d3745570660f42", size: 18_160_344),
            File(member: "NotoSansCJK-Regular.ttc", name: "NotoSansCJK-Regular.ttc", sha256: "b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a", size: 19_484_784),
            File(member: "NotoSansCJK-Medium.ttc", name: "NotoSansCJK-Medium.ttc", sha256: "197d5e1e019faca33a4d55931c7d68b8056f3b97cb862049f5cb8de9efdfb8ce", size: 18_354_360),
            File(member: "NotoSansCJK-Bold.ttc", name: "NotoSansCJK-Bold.ttc", sha256: "faa5f3656a78b2e2d450d27fe8382c778bc2b6bb5ea29c986664a6a435056ceb", size: 20_050_760),
            // The licence the fonts come under, kept beside them.
            File(member: "LICENSE", name: "LICENSE-NotoSansCJK.txt", sha256: "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2", size: 4_301),
        ])
}

public struct FontDownloadError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// The downloaded fonts in Application Support/AnyPS5/Fonts/<folder>: whether they are there, and
/// getting them. A download that stops keeps what came (in .download) and goes on from there the
/// next time; nothing is installed before the archive and every file in it match their SHA-256.
public struct FontDownloads: Sendable {
    public static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/Fonts")

    public let package: FontPackage
    public let folder: URL

    public init(package: FontPackage = .notoCJK, folder: URL = FontDownloads.root.appendingPathComponent("CJK")) {
        self.package = package
        self.folder = folder
    }

    var downloads: URL { folder.appendingPathComponent(".download") }
    var partial: URL { downloads.appendingPathComponent(package.archiveName + ".part") }

    /// Every file of the package is in the folder, at its size (its SHA-256 was checked when it
    /// was installed).
    public var installed: Bool {
        package.files.allSatisfy { FontDownloads.size(of: folder.appendingPathComponent($0.name)) == $0.size }
    }

    /// How much of an earlier download is kept, in bytes.
    public var resumable: Int64 { FontDownloads.size(of: partial) }

    /// Deletes the downloaded fonts and any download kept.
    public func remove() throws {
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// Downloads the archive (going on from an earlier download), checks it, takes the files out,
    /// checks them and puts them in the folder. `progress` hears the download's share, 0 to 1.
    public func install(configuration: URLSessionConfiguration = .default, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if installed { return progress(1) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try checkSpace()
        let resumed = resumable > 0
        try await fetch(configuration: configuration, progress: progress)
        if try FontDownloads.sha256(of: partial) != package.sha256 {
            try? fileManager.removeItem(at: partial)
            guard resumed else { throw FontDownloadError("the download of \(package.archiveName) did not match its SHA-256, so it was deleted") }
            // What was kept from before may have been the bad part: once more from the start.
            try await fetch(configuration: configuration, progress: progress)
            guard try FontDownloads.sha256(of: partial) == package.sha256 else {
                try? fileManager.removeItem(at: partial)
                throw FontDownloadError("the download of \(package.archiveName) did not match its SHA-256, so it was deleted")
            }
        }
        let staging = downloads.appendingPathComponent("unpacked-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try FontDownloads.unzip(partial, members: package.files.map(\.member), into: staging)
        for file in package.files {
            let unpacked = staging.appendingPathComponent((file.member as NSString).lastPathComponent)
            guard fileManager.fileExists(atPath: unpacked.path) else { throw FontDownloadError("\(package.archiveName) holds no \(file.member)") }
            guard try FontDownloads.sha256(of: unpacked) == file.sha256 else {
                try? fileManager.removeItem(at: partial)
                throw FontDownloadError("\(file.member) in \(package.archiveName) did not match its SHA-256")
            }
        }
        for file in package.files {
            let destination = folder.appendingPathComponent(file.name)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: staging.appendingPathComponent((file.member as NSString).lastPathComponent), to: destination)
        }
        try? fileManager.removeItem(at: downloads)
        progress(1)
    }

    /// The archive into .download, going on after a dropped connection up to `attempts` times.
    func fetch(configuration: URLSessionConfiguration, attempts: Int = 4, progress: @escaping @Sendable (Double) -> Void) async throws {
        for attempt in 1...attempts {
            do {
                try await ResumableDownload(url: package.url, file: partial, expected: package.size, progress: progress).run(configuration: configuration)
                if resumable >= package.size { return }
                if attempt == attempts { throw FontDownloadError("the download of \(package.archiveName) stopped short") }
            } catch let error as URLError where attempt < attempts && error.code != .cancelled {
                try? await Task.sleep(for: .milliseconds(300 * attempt))
            }
        }
    }

    /// Refuses to begin without room for the archive and what comes out of it.
    func checkSpace() throws {
        let values = try? downloads.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return }
        let needed = (package.size - resumable) + package.installedSize + (256 << 20)
        if free < needed {
            throw FontDownloadError("the fonts need \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) free; there is \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
        }
    }

    static func unzip(_ archive: URL, members: [String], into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -j drops the folders inside the archive; only the members named come out.
        process.arguments = ["-o", "-j", "-qq", archive.path] + members + ["-d", folder.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FontDownloadError("could not unpack \(archive.lastPathComponent): \(String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 1 << 20), !block.isEmpty { hasher.update(data: block) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func size(of file: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? -1
    }
}

/// One HTTP download into a file that goes on where the file ends: a Range request, appended to
/// on 206, started again on 200.
final class ResumableDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let url: URL
    let file: URL
    let expected: Int64
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var offset: Int64 = 0
    private var handle: FileHandle?
    private var finished = false
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    init(url: URL, file: URL, expected: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.url = url
        self.file = file
        self.expected = expected
        self.progress = progress
    }

    func run(configuration: URLSessionConfiguration) async throws {
        offset = max(0, FontDownloads.size(of: file))
        if offset >= expected && expected > 0 { return }
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            session.dataTask(with: request(url)).resume()
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        return request
    }

    /// GitHub sends the download on to its storage: the Range goes along.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = newRequest
        lock.withLock { if offset > 0 { next.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") } }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        lock.lock()
        defer { lock.unlock() }
        do {
            switch status {
            case 206:
                let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range") ?? ""
                guard ResumableDownload.start(ofContentRange: range) == offset else {
                    throw FontDownloadError("the server went on from another place than asked (\(range))")
                }
                handle = try FileHandle(forWritingTo: file)
                try handle?.seekToEnd()
            case 200:
                // The server sends the whole file: what was kept goes.
                handle = try FileHandle(forWritingTo: file)
                try handle?.truncate(atOffset: 0)
                offset = 0
            case 416 where offset > 0:
                // Nothing left to send: the file is whole already (its SHA-256 says so or not).
                finished = true
                return completionHandler(.cancel)
            default:
                throw FontDownloadError("the server answered \(status)")
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        do {
            try handle?.write(contentsOf: data)
            offset += Int64(data.count)
        } catch {
            failure = error
            dataTask.cancel()
        }
        let done = offset
        lock.unlock()
        if expected > 0 { progress(min(0.999, Double(done) / Double(expected))) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        try? handle?.close()
        handle = nil
        let outcome: Error? = finished ? nil : failure ?? error
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let outcome { continuation?.resume(throwing: outcome) } else { continuation?.resume() }
    }

    /// The first byte of a `bytes <first>-<last>/<total>` Content-Range.
    static func start(ofContentRange range: String) -> Int64? {
        guard range.hasPrefix("bytes "), let dash = range.firstIndex(of: "-") else { return nil }
        return Int64(range[range.index(range.startIndex, offsetBy: 6)..<dash].trimmingCharacters(in: .whitespaces))
    }
}
