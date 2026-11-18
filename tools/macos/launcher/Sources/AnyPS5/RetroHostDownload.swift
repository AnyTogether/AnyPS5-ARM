import AnyPS5Core
import Foundation

/// The PS1 emulator host as a managed download, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_host_download_model.dart): Settings › Emulators offers it from the host
/// repository's signed releases, the player selects it to download or update it, and it is
/// checked on download and before every game (`RetroHostStore`). A debug build that runs the host
/// `ANYPS5_RETRO_HOST` names offers none.
@MainActor
final class RetroHostDownloads {
    /// How far a download is: looking for the release, fetching its files, or checking them.
    struct Progress: Equatable {
        enum Phase: Equatable { case looking, download, checking }
        var phase: Phase
        var received: Int64 = 0
        var total: Int64 = 0

        var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : (phase == .checking ? 1 : 0) }
    }

    private unowned let app: AppModel
    let store: RetroHostStore
    /// Where the host's releases are read; nil where none can be (the tests, unless they give one).
    private let releases: (@Sendable () async throws -> [RetroHostUpstreamRelease])?
    private let configuration: URLSessionConfiguration

    init(app: AppModel, store: RetroHostStore, releases: (@Sendable () async throws -> [RetroHostUpstreamRelease])?,
         configuration: URLSessionConfiguration) {
        self.app = app
        self.store = store
        self.releases = releases
        self.configuration = configuration
        look()
    }

    /// The installed host to start, as `RetroHostStore.installed()` last found it; checked before
    /// each start all the same.
    private(set) var installed: RetroHostInstall?
    /// The installed host's version, for its row.
    private var version: RetroHostVersion?

    /// Reads the installed host from disk: when the model is made, and again only when its folder
    /// may have changed (a new host put in place, or the installed one failing its check), not on
    /// every play or Settings row.
    private func look() {
        installed = store.installed()
        version = installed == nil ? nil : store.version
    }

    /// `look()` once the model is made: where the host gained or lost LRPS2, the library is scanned
    /// again, as it lists PS2 cue sheets only while the host plays PS2 discs.
    private func lookAgain() {
        let ps2 = installed?.ps2Core != nil
        look()
        if (installed?.ps2Core != nil) != ps2, app.listsRetroGames {
            if app.persists { app.rescan() } else { app.scanAtOnce() }
        }
    }

    /// The last look found no signed host release yet.
    private(set) var notYet = false
    /// Why the last download failed; a sentence, or nil.
    private(set) var error: String?
    /// Why the installed host failed its check before a start, until it is downloaded again.
    private(set) var broken: String?
    private(set) var progress: Progress?
    private var task: Task<Void, Never>?
    var downloading: Bool { task != nil }
    /// The new host is being put in place of the old: no host may start until it is.
    private(set) var installing = false
    /// The checked files are being written over the old host's: past the point of stopping, so the
    /// row no longer offers it (`cancel()` does nothing).
    private(set) var placing = false
    private var starts = 0
    private var closed = false
    /// The last half percent of the download the row was drawn at.
    private var shownStep = -1

    /// A start of a game in the host holds the installed host from its checks until its play is
    /// set (`releaseStart()`), so a download does not put a new host in place meanwhile: it refuses,
    /// as for a game playing. False, and nothing held, while a new host is being put in place.
    func holdForStart() -> Bool {
        if installing { return false }
        starts += 1
        return true
    }

    /// The start `holdForStart()` held has its play, or did not start.
    func releaseStart() {
        starts = max(0, starts - 1)
    }

    /// Whether this launcher can download a host: it has the releases to read and a system the
    /// host is released for (an Apple silicon Mac).
    var offered: Bool { releases != nil && store.system != nil }

    /// The installed host failed its check before a start: `reason` says how. Its row then offers
    /// it again.
    func failedCheck(_ reason: String) {
        broken = reason
        lookAgain()
        app.objectWillChange.send()
    }

    /// A game plays in a host, or one is starting.
    private var hostInUse: Bool { starts > 0 || app.retroPlay != nil }

    /// Downloads the newest signed host, or a newer one than the installed host, checks it and puts
    /// it in place. Runs only when the player selected it; said to the player however it ends.
    func download() {
        guard task == nil, !closed, let releases, store.system != nil else { return }
        if hostInUse { return app.show(TRetro.text(.retroHostDownloadCloseGame), symbol: "opticaldisc") }
        error = nil
        notYet = false
        progress = Progress(phase: .looking)
        app.objectWillChange.send()
        task = Task { [weak self] in await self?.run(releases) }
    }

    private func run(_ releases: @Sendable () async throws -> [RetroHostUpstreamRelease]) async {
        defer {
            installing = false
            placing = false
            task = nil
            progress = nil
            app.objectWillChange.send()
        }
        let before = store.version
        do {
            let release = RetroHostStore.newest(try await releases())
            let offered = release.flatMap { RetroHostVersion($0.version) }
            if let before, broken == nil, let offered, offered <= before, await installedPassesCheck() {
                return app.show(TRetro.format(.retroHostUpToDate, "\(before)"), symbol: "checkmark.circle.fill")
            }
            try Task.checkCancellation()
            let store = self.store
            shownStep = -1
            let download = try await store.fetch(release, configuration: configuration) { received, total in
                Task { @MainActor [weak self] in
                    guard let self, self.task != nil, !self.placing else { return }
                    self.progress = Progress(phase: .download, received: received, total: total)
                    let step = Int((self.progress?.fraction ?? 0) * 200)
                    if step != self.shownStep {
                        self.shownStep = step
                        self.app.objectWillChange.send()
                    }
                }
            }
            if closed { return }
            progress = Progress(phase: .checking)
            installing = true
            app.objectWillChange.send()
            if hostInUse { throw RetroHostDownloadError(.badLayout, TRetro.text(.retroHostDownloadCloseGame)) }
            // The host kept for the next game lets go of its files before the new host goes in.
            await app.stopKeptRetroHost()
            if hostInUse { throw RetroHostDownloadError(.badLayout, TRetro.text(.retroHostDownloadCloseGame)) }
            if closed { return }
            try Task.checkCancellation()
            placing = true
            app.objectWillChange.send()
            let version: RetroHostVersion
            do {
                version = try await store.putInPlace(download)
            } catch {
                lookAgain()
                throw error
            }
            lookAgain()
            broken = nil
            // The first host installed turns PS1 games in the host on: the player asked for it.
            if before == nil { app.setRetroHostPs1(true) }
            Sounds.shared.play(.unlocked)
            app.show(TRetro.format(.retroHostReady, "\(version)"), symbol: "checkmark.circle.fill")
        } catch let failure as RetroHostDownloadError {
            switch failure.kind {
            case .cancelled:
                break
            case .notAvailable:
                notYet = true
                app.show(TRetro.text(.retroHostNotYet), symbol: "opticaldisc")
            default:
                error = failure.message
                app.show(TRetro.format(.retroHostDownloadFailed, failure.message), symbol: "exclamationmark.triangle.fill")
            }
        } catch is CancellationError {
            // Stopped: what came is kept for the next try.
        } catch {
            self.error = error.localizedDescription
            app.show(TRetro.format(.retroHostDownloadFailed, error.localizedDescription), symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Whether the installed host is there whole and passes the checks before a start; only then
    /// is a release of the same version not downloaded again.
    private func installedPassesCheck() async -> Bool {
        guard store.installed() != nil else { return false }
        guard let checked = try? await store.check() else { return false }
        checked.release()
        return true
    }

    /// Stops the download; what came is kept, to carry on next time. Once the new host is being put
    /// in place it runs to the end.
    func cancel() {
        if !placing { task?.cancel() }
    }

    /// The launcher goes: a download stops, and one already fetched is not put in place, since the
    /// hosts the launcher shuts down as it goes may not have exited yet.
    func close() {
        closed = true
        cancel()
    }

    /// Settings › Emulators' row for the download: one select to download the host, then how it
    /// goes; once installed, its version, and a select looks for a newer one. Nothing where no host
    /// can be downloaded, or the unchecked host `ANYPS5_RETRO_HOST` names is used.
    func rows(uncheckedHost: Bool) -> [PanelRow] {
        guard offered, !uncheckedHost else { return [] }
        if downloading {
            let now = progress
            let detail: String
            if placing {
                detail = TRetro.text(.retroHostChecking)
            } else {
                let step: String
                switch now?.phase {
                case .download where (now?.total ?? 0) > 0:
                    step = TFiles.format(.filesProgress, (now?.received ?? 0).byteText, (now?.total ?? 0).byteText)
                case .checking:
                    step = TRetro.text(.retroHostChecking)
                default:
                    step = TRetro.text(.retroHostLooking)
                }
                detail = TRetro.format(.retroHostProgress, step)
            }
            return [PanelRow(id: "retro-host-download", title: TRetro.format(.retroHostDownloading, Int((now?.fraction ?? 0) * 100)),
                             detail: detail, symbol: "arrow.down.circle", kind: .action(destructive: false) { [weak self] in self?.cancel() })]
        }
        let detail: String
        if broken != nil {
            detail = TRetro.text(.retroHostBrokenDetail)
        } else if let error {
            detail = error
        } else if notYet {
            detail = TRetro.text(.retroHostNotYet)
        } else {
            detail = TRetro.text(version == nil ? .retroHostDownloadDetail : .retroHostInstalledDetail)
        }
        let title = version == nil || broken != nil ? TRetro.text(.retroHostDownload) : TRetro.format(.retroHostInstalled, "\(version!)")
        return [PanelRow(id: "retro-host-download", title: title, detail: detail,
                         symbol: version == nil || broken != nil ? "arrow.down.circle" : "checkmark.seal",
                         kind: .action(destructive: false) { [weak self] in self?.download() })]
    }
}

extension AppModel {
    /// Settings › Emulators' rows for the emulator host: its download, or the notice that this
    /// build runs an unchecked host, as on Windows and Linux.
    func retroHostSettingsRows() -> [PanelRow] {
        let unchecked = retroHostUnchecked != nil
        var rows = retroHostDownload.rows(uncheckedHost: unchecked)
        if unchecked {
            rows.append(PanelRow(id: "retro-host-unchecked", title: TRetro.text(.retroHostUnchecked),
                                 detail: TRetro.text(.retroHostUncheckedDetail), symbol: "flask", kind: .info(""), wraps: true))
        }
        return rows + retroHostPlayRows()
    }
}
