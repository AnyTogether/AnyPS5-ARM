import Foundation

/// A download into a file that carries on where it stopped (ResumableDownload), tried again by
/// itself when a try fails on the way: a dropped connection, a stalled one (the session's request
/// timeout, 60 s without bytes by default), or an answer another try may get past, such as the
/// 403 GitHub's storage gives once the signed address it redirected to has expired. Each try
/// starts at the release's own address, so GitHub's redirect is followed afresh and gives a new
/// signed address, and asks only for what the file still lacks. Windows and Linux do the same
/// (AssetDownload.fetch in AnyPS5 Desktop).
public enum DownloadRetry {
    /// Tries of one download, the first one included.
    public static let attempts = 4

    /// The pauses before the second, third and later tries (the last one repeats). Tests make
    /// them short.
    nonisolated(unsafe) static var pauses: [Duration] = [.seconds(1), .seconds(3), .seconds(8)]

    /// Whether another try may get past `error`: a network failure that is not the user's stop,
    /// or an answer of the download's host that may change (`passing(status:)`).
    public static func passing(_ error: Error) -> Bool {
        if let error = error as? URLError { return error.code != .cancelled }
        if let error = error as? FontDownloadError, let status = error.status { return passing(status: status) }
        return false
    }

    /// The storage host's refusals of a signed address that expired (401, 403, 410), a timeout,
    /// too many requests and the server's own errors. A 404 is not: the file is not there.
    public static func passing(status: Int) -> Bool {
        [401, 403, 408, 410, 429].contains(status) || status >= 500
    }

    /// Downloads `url` into `file`, going on from what the file already holds; `expected` is the
    /// size, 0 when it is not known. When every try failed the file is kept, for the next download
    /// to carry on, and the last failure is thrown. Cancelling the calling task stops it at once,
    /// in a pause between tries too.
    static func run(url: URL, file: URL, expected: Int64, httpsOnly: Bool = false, configuration: URLSessionConfiguration,
                    attempts: Int = DownloadRetry.attempts, progress: @escaping @Sendable (Double) -> Void) async throws {
        let attempts = max(1, attempts)
        for attempt in 1...attempts {
            do {
                try Task.checkCancellation()
                try await ResumableDownload(url: url, file: file, expected: expected, httpsOnly: httpsOnly, progress: progress)
                    .run(configuration: configuration)
                if expected <= 0 || FontDownloads.size(of: file) >= expected { return }
                if attempt == attempts {
                    throw FontDownloadError("the download of \(url.lastPathComponent) stopped short (tried \(attempts) times)")
                }
            } catch {
                guard attempt < attempts, passing(error), !Task.isCancelled else { throw error }
            }
            try await Task.sleep(for: pauses.isEmpty ? .zero : pauses[min(attempt - 1, pauses.count - 1)])
        }
    }
}
