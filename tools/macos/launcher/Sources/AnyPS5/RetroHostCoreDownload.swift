import AnyPS5Core
import Foundation

/// A core package as an emulator of its own, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_host_core_download_model.dart): today the PS2 emulator, LRPS2, which the
/// player adds beside the installed host from the host's own release and removes again
/// (protocol.md "Finding and checking the host", "Adding a core package"). A player who never adds
/// it never downloads it. It moves with the host: a host update puts in place the same packages
/// from the new release (`RetroHostDownloads.download()`). Offered only while the installed host's
/// release has the package, so never for a host 1.0.0.
@MainActor
final class RetroHostCoreDownloads {
    /// The host download the package is added beside.
    private unowned let host: RetroHostDownloads
    let core: RetroHostCorePackage

    init(host: RetroHostDownloads, core: RetroHostCorePackage) {
        self.host = host
        self.core = core
    }

    private var app: AppModel { host.app }

    /// Whether the package is added beside the installed host, as the host's last look found it.
    var installed: Bool { host.installed != nil && host.installedCores.contains(core) }

    /// Whether the player can add it: a signed host is installed and its release has the package.
    var offered: Bool { host.offered && host.installed != nil && host.offeredCores.contains(core) }

    /// Why the last download failed; a sentence, or nil.
    private(set) var error: String?
    /// The installed host's release could not be found on GitHub, or lacks the package.
    private(set) var notYet = false
    private(set) var progress: RetroHostDownloads.Progress?
    private var task: Task<Void, Never>?
    var downloading: Bool { task != nil }
    /// The checked files are being written beside the host: past the point of stopping.
    private(set) var placing = false
    private var removing = false
    /// The last half percent of the download the row was drawn at.
    private var shownStep = -1

    /// A download or a removal is under way: the host is not downloaded meanwhile.
    var busy: Bool { downloading || removing }

    /// Whether a change to the host's folder must wait: the host or this package is being changed,
    /// or the launcher is going.
    private var blocked: Bool { busy || host.downloading || host.installing || host.closed }

    /// Downloads the package from the installed host's release, checks it against the SHA256SUMS
    /// kept beside the host and adds it there, the host kept for the next game shut down first.
    /// The first one added turns its games on (Run PS2 games in the separate host). Runs only when
    /// the player selected it; said to the player however it ends.
    func add() {
        guard !blocked, let releases = host.releases else { return }
        if host.hostInUse { return app.show(TRetro.text(.retroHostPs2CloseGame), symbol: "opticaldisc") }
        error = nil
        notYet = false
        progress = RetroHostDownloads.Progress(phase: .looking)
        app.objectWillChange.send()
        task = Task { [weak self] in await self?.run(releases) }
    }

    private func run(_ releases: @Sendable () async throws -> [RetroHostUpstreamRelease]) async {
        defer {
            host.installing = false
            placing = false
            task = nil
            progress = nil
            app.objectWillChange.send()
        }
        do {
            let store = host.store
            let tag = store.installedTag
            let release = try await releases().first { $0.tag == tag }
            try Task.checkCancellation()
            shownStep = -1
            let download = try await store.fetchCore(release, core, configuration: host.configuration) { received, total in
                Task { @MainActor [weak self] in
                    guard let self, self.task != nil, !self.placing else { return }
                    self.progress = RetroHostDownloads.Progress(phase: .download, received: received, total: total)
                    let step = Int((self.progress?.fraction ?? 0) * 200)
                    if step != self.shownStep {
                        self.shownStep = step
                        self.app.objectWillChange.send()
                    }
                }
            }
            if host.closed { return }
            progress = RetroHostDownloads.Progress(phase: .checking)
            host.installing = true
            app.objectWillChange.send()
            if host.hostInUse { throw RetroHostDownloadError(.badLayout, TRetro.text(.retroHostPs2CloseGame)) }
            // The host kept for the next game lets go of its files before the package goes in.
            await app.stopKeptRetroHost()
            if host.hostInUse { throw RetroHostDownloadError(.badLayout, TRetro.text(.retroHostPs2CloseGame)) }
            if host.closed { return }
            try Task.checkCancellation()
            placing = true
            app.objectWillChange.send()
            do {
                try await store.putCoreInPlace(download, core)
            } catch {
                host.lookAgain()
                throw error
            }
            // The first PS2 emulator added turns PS2 games in the host on: the player asked for it.
            if app.preferences.retroHostPs2 != true { app.preferences.retroHostPs2 = true }
            host.lookAgain()
            Sounds.shared.play(.unlocked)
            app.show(TRetro.format(.retroHostPs2Ready, "\(host.version.map { "\($0)" } ?? "")"), symbol: "checkmark.circle.fill")
        } catch let failure as RetroHostDownloadError {
            switch failure.kind {
            case .cancelled:
                break
            case .notAvailable:
                notYet = true
                app.show(TRetro.text(.retroHostPs2NotYet), symbol: "opticaldisc")
            default:
                error = failure.message
                app.show(TRetro.format(.retroHostPs2DownloadFailed, failure.message), symbol: "exclamationmark.triangle.fill")
            }
        } catch is CancellationError {
            // Stopped: what came is kept for the next try.
        } catch {
            self.error = error.localizedDescription
            app.show(TRetro.format(.retroHostPs2DownloadFailed, error.localizedDescription), symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Removes the package from beside the host, the host kept for the next game shut down first.
    /// Its games' setting, BIOS, memory cards and save states stay. Gives the task that removes it.
    @discardableResult
    func remove() -> Task<Void, Never>? {
        guard !blocked, installed else { return nil }
        if host.hostInUse {
            app.show(TRetro.text(.retroHostPs2CloseGame), symbol: "opticaldisc")
            return nil
        }
        removing = true
        host.installing = true
        app.objectWillChange.send()
        return Task { [weak self] in await self?.runRemove() }
    }

    private func runRemove() async {
        defer {
            removing = false
            host.installing = false
            host.lookAgain()
            app.objectWillChange.send()
        }
        do {
            await app.stopKeptRetroHost()
            if host.hostInUse { throw RetroHostDownloadError(.badLayout, TRetro.text(.retroHostPs2CloseGame)) }
            try host.store.removeCore(core)
            app.show(TRetro.text(.retroHostPs2Removed), symbol: "checkmark.circle.fill")
        } catch {
            let message = (error as? RetroHostDownloadError)?.message ?? error.localizedDescription
            app.show(TRetro.format(.retroHostPs2RemoveFailed, message), symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Stops the download; what came is kept, to carry on next time. Once the files are being
    /// written it runs to the end.
    func cancel() {
        if !placing { task?.cancel() }
    }

    /// Settings › Emulators' row for the package, beside the host's own: one select to download it,
    /// then how it goes; once added, its version, which is the host's, and a select looks for a
    /// newer release of both, as the host's row does. Nothing where it is not offered, or the
    /// unchecked host `ANYPS5_RETRO_HOST` names is used.
    func rows(uncheckedHost: Bool) -> [PanelRow] {
        guard !uncheckedHost, offered else { return [] }
        if downloading {
            return [RetroHostDownloads.progressRow(id: "retro-host-ps2-download", title: .retroHostPs2Downloading, progress: progress,
                                                   placing: placing) { [weak self] in self?.cancel() }]
        }
        if installed {
            return [PanelRow(id: "retro-host-ps2-download", title: TRetro.format(.retroHostPs2Installed, host.version.map { "\($0)" } ?? ""),
                             detail: TRetro.text(.retroHostPs2InstalledDetail), symbol: "checkmark.seal",
                             kind: .action(destructive: false) { [weak self] in self?.host.download() })]
        }
        return [PanelRow(id: "retro-host-ps2-download", title: TRetro.text(.retroHostPs2Download),
                         detail: error ?? TRetro.text(notYet ? .retroHostPs2NotYet : .retroHostPs2DownloadDetail), symbol: "arrow.down.circle",
                         kind: .action(destructive: false) { [weak self] in self?.add() })]
    }

    /// The row that removes the package, once it is added and nothing else changes the host: hidden
    /// while the host downloads or installs, when `remove()` would do nothing.
    func removeRows(uncheckedHost: Bool) -> [PanelRow] {
        guard !uncheckedHost, installed, !blocked else { return [] }
        return [PanelRow(id: "retro-host-ps2-remove", title: TRetro.text(.retroHostPs2Remove), detail: TRetro.text(.retroHostPs2RemoveDetail),
                         symbol: "trash", kind: .action(destructive: true) { [weak self] in _ = self?.remove() })]
    }
}
