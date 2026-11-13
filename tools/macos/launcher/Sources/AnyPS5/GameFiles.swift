import AnyPS5Core
import AppKit
import Foundation
import UniformTypeIdentifiers

/// The texts of the files panel: a zip in a games folder to unpack, Game Settings › Add Update.
/// The same keys and English as AnyLauncher Port's, so its translations fit.
enum TFiles {
    static func text(_ key: Key) -> String { T.string(key.rawValue) }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    enum Key: String, CaseIterable {
        case filesBusy, filesSpace, filesNoSpace, filesUnpacking, filesCopying, filesProgress, filesKeepsGoing, filesStop, filesStopped, filesLater
        case addUpdate, addUpdateDetail, addUpdateChoose, addUpdateOtherGame, addUpdateNotNewer, addUpdateHaveNewer, addUpdateHaveOlder, addUpdateNotADump
        case addUpdateTitle, addUpdateVersion, addUpdateAbout, addUpdateGo, addUpdateFailed, addUpdateMoved, addUpdateCopied
        case unpackTitle, unpackUpdateTitle, unpackAbout, unpackUpdateAbout, unpackUnsafe, unpackGo, unpackDone, unpackUpdateDone, unpackFailed
        case unpackFileTitle, unpackAboutFolder, unpackFileUnsafe, unpackFileDone, ffpfscCompressed, ffpfscUnsupported, ffpfscDamaged
        case addGameFile, addGameFileDetail, addGameFileChoose, addGameFileNoFolder, addGameFileThere, addGameFileHaveNewer, addGameFileNoGame
    }
}

/// What the files panel (Overlay.gameFiles) is about.
enum FilesAsk: Equatable {
    /// A game dropped into a games folder as a zip: unpacked into `into` (the folder beside it, or
    /// the update folder of the game in the library it is a newer version of).
    case unpack(GameArchive, ArchivePlan, into: URL, updateOf: Game?)
    /// Game Settings › Add Update: a dump of the game's update, checked, to be put beside it.
    case update(UpdateCandidate, game: Game, size: Int64)

    var archive: GameArchive? {
        if case .unpack(let archive, _, _, _) = self { return archive }
        return nil
    }
}

/// The panel's state: the question, the job running and how far it is.
struct GameFilesState: Equatable {
    var asked: FilesAsk?
    var working: FilesAsk?
    var done: Int64 = 0
    var total: Int64 = 0
}

/// What the files work keeps beside the published state.
@MainActor
final class GameFilesWork {
    /// The zips looked into, by path: their size then (a zip still being copied grows), when, and
    /// the plan (nil for one that could not be read as a zip yet).
    var plans: [String: (size: Int64, when: Date, plan: ArchivePlan?)] = [:]
    /// Zips answered Not Now, until the launcher starts again.
    var later: Set<String> = []
    /// The zips with a game in them, waiting to be offered.
    var waiting: [FilesAsk] = []
    var looking = false
    var again: [URL]?
    var retry: Task<Void, Never>?
    var cancel: UnpackCancel?

    /// How soon a zip that could not be read is looked into again: a copy that set the file's
    /// whole size first writes the zip's list of files last.
    nonisolated static let retryUnread: TimeInterval = 10
}

/// Zips dropped into the games folders (offered for unpacking, then read as any dump) and updates
/// added from a folder (Game Settings › Add Update). One job at a time, its progress in the panel;
/// Back hides the panel and the job goes on. AnyLauncher Port's game_files_model.dart, on the Mac.
extension AppModel {
    /// After a scan of the games folders: new zips are looked into (away from the interface), and
    /// one with a game in it is offered when nothing else is on the screen.
    func filesScanned(_ roots: [URL]) {
        let work = gameFilesWork
        if work.looking {
            work.again = roots
            return
        }
        if gameFiles.working == nil { GameArchives.removeLeftovers(roots) }
        let found = GameArchives.find(roots)
        let paths = Set(found.map(\.url.path))
        work.plans = work.plans.filter { paths.contains($0.key) }
        work.waiting.removeAll { !paths.contains($0.archive?.url.path ?? "") }
        work.looking = true
        let known = work.plans
        Task.detached(priority: .utility) {
            var plans = known
            var unread = false
            for archive in found {
                if let seen = plans[archive.url.path], seen.size == archive.size {
                    if seen.plan != nil { continue }
                    if Date().timeIntervalSince(seen.when) < GameFilesWork.retryUnread {
                        unread = true
                        continue
                    }
                }
                var plan = try? GameArchives.plan(archive.url)
                // No list of files: still being copied, or not a zip. Looked into again in a while.
                // A .ffpfsc that says why it will not unpack has its answer already.
                if plan?.files == 0, plan?.problem == nil { plan = nil }
                if plan == nil { unread = true }
                plans[archive.url.path] = (archive.size, Date(), plan)
            }
            let looked = plans, someUnread = unread
            await MainActor.run { self.filesLooked(found, plans: looked, unread: someUnread) }
        }
    }

    private func filesLooked(_ found: [GameArchive], plans: [String: (size: Int64, when: Date, plan: ArchivePlan?)], unread: Bool) {
        let work = gameFilesWork
        work.looking = false
        work.plans = plans
        work.waiting = found.compactMap { archive in
            guard let plan = plans[archive.url.path]?.plan, plan.looksLikeGame || plan.problem != nil else { return nil }
            return filesAsk(archive, plan)
        }
        offerNextFile()
        if let again = work.again {
            work.again = nil
            return filesScanned(again)
        }
        if unread, work.retry == nil {
            work.retry = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(GameFilesWork.retryUnread * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.gameFilesWork.retry = nil
                if !self.libraryRoots.isEmpty { self.filesScanned(self.libraryRoots) }
            }
        }
    }

    /// Where `archive` unpacks: the update folder of a game in the library when it is a newer
    /// version of it, else `folder` (the one beside it when not given). Nil when that folder is
    /// there already.
    func filesAsk(_ archive: GameArchive, _ plan: ArchivePlan, folder: URL? = nil) -> FilesAsk? {
        if let titleID = plan.titleID, let version = plan.version {
            for game in games where game.titleID.uppercased() == titleID.uppercased() {
                let problem = GameUpdates.problem(with: game, titleID: titleID, version: version)
                // The update the game has already, or one as new: nothing to offer.
                if problem == .haveNewer { return nil }
                if problem == nil { return .unpack(archive, plan, into: GameUpdates.target(game), updateOf: game) }
            }
        }
        let target = folder ?? archive.folder
        if FileManager.default.fileExists(atPath: target.path) { return nil }
        return .unpack(archive, plan, into: target, updateOf: nil)
    }

    /// The first zip waiting, offered when the home screen shows nothing else.
    func offerNextFile() {
        guard gameFiles.working == nil, preferences.onboarded else { return }
        // A question another screen took the place of is dropped.
        if gameFiles.asked != nil, overlay == .gameFiles { return }
        gameFiles.asked = nil
        guard overlay == nil, !playing else { return }
        guard let next = gameFilesWork.waiting.first(where: { !gameFilesWork.later.contains($0.archive?.url.path ?? "") }) else { return }
        gameFiles.asked = next
        open(.gameFiles)
    }

    /// Game Settings › Add Update: a folder is chosen and checked against `game`.
    func addUpdate(_ game: Game) {
        if gameFiles.working != nil { return show(TFiles.text(.filesBusy), symbol: "hourglass") }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = TFiles.text(.addUpdateChoose)
        panel.prompt = TFiles.text(.addUpdateGo)
        panel.directoryURL = game.folder.deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        addUpdate(game, from: folder)
    }

    /// Settings › Game Library › Add Game File: one .ffpfsc chosen and unpacked into a normal game
    /// folder, in the first games folder unless it already sits in a games folder.
    func addGameFile() {
        if gameFiles.working != nil { return show(TFiles.text(.filesBusy), symbol: "hourglass") }
        guard let first = libraryRoots.first else { return show(TFiles.text(.addGameFileNoFolder), symbol: "folder") }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "ffpfsc") { panel.allowedContentTypes = [type] }
        panel.message = TFiles.text(.addGameFileChoose)
        panel.prompt = TFiles.text(.unpackGo)
        panel.directoryURL = first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addGameFile(url, firstFolder: first)
    }

    /// The file at `url` looked into away from the interface, then offered or said to be no game.
    func addGameFile(_ url: URL, firstFolder: URL) {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let archive = GameArchive(url: url, size: size)
        let parent = url.deletingLastPathComponent().standardizedFileURL
        let inLibrary = libraryRoots.contains {
            let root = $0.standardizedFileURL
            return root == parent || root == parent.deletingLastPathComponent()
        }
        let target = inLibrary ? archive.folder : firstFolder.appendingPathComponent(archive.folder.lastPathComponent)
        Task.detached(priority: .utility) {
            let plan = try? GameArchives.plan(url)
            await MainActor.run { self.addGameFileLooked(archive, plan, into: target) }
        }
    }

    private func addGameFileLooked(_ archive: GameArchive, _ plan: ArchivePlan?, into target: URL) {
        guard let plan else { return show(TFiles.text(.ffpfscDamaged), symbol: "exclamationmark.triangle.fill") }
        guard plan.problem != nil || plan.looksLikeGame || !plan.refused.isEmpty else { return show(TFiles.text(.addGameFileNoGame), symbol: "exclamationmark.triangle.fill") }
        let ask: FilesAsk
        if plan.problem != nil {
            ask = .unpack(archive, plan, into: target, updateOf: nil)
        } else if let found = filesAsk(archive, plan, folder: target) {
            ask = found
        } else if FileManager.default.fileExists(atPath: target.path) {
            return show(TFiles.format(.addGameFileThere, target.lastPathComponent), symbol: "exclamationmark.triangle.fill")
        } else {
            return show(TFiles.text(.addGameFileHaveNewer), symbol: "exclamationmark.triangle.fill")
        }
        gameFiles.asked = ask
        open(.gameFiles)
    }

    /// The folder `folder` checked against `game`: why it is no update, or the panel asking.
    func addUpdate(_ game: Game, from folder: URL) {
        let checked = GameUpdates.check(folder, for: game)
        guard let update = checked.update else {
            let text: String = switch checked.problem {
            case .otherGame: TFiles.format(.addUpdateOtherGame, game.name)
            case .notNewer: TFiles.format(.addUpdateNotNewer, game.version)
            case .haveNewer: TFiles.format(.addUpdateHaveNewer, game.update?.shortVersion ?? "")
            case .haveOlder: TFiles.format(.addUpdateHaveOlder, GameUpdates.target(game).lastPathComponent)
            default: TFiles.text(.addUpdateNotADump)
            }
            return show(text, symbol: "exclamationmark.triangle.fill")
        }
        Task.detached(priority: .utility) {
            let size = GameLibrary.size(of: folder)
            await MainActor.run {
                self.gameFiles.asked = .update(update, game: game, size: size)
                self.open(.gameFiles)
            }
        }
    }

    var gameFilesTitle: String {
        switch gameFiles.working ?? gameFiles.asked {
        case .unpack(_, _, _, let game?): return TFiles.format(.unpackUpdateTitle, game.name)
        case .unpack(let archive, _, _, _): return TFiles.text(archive.isFfpfsc ? .unpackFileTitle : .unpackTitle)
        case .update(_, let game, _): return TFiles.format(.addUpdateTitle, game.name)
        case nil: return ""
        }
    }

    static func percentText(_ done: Int64, _ total: Int64) -> String {
        let fraction = total == 0 ? 0 : min(1, max(0, Double(done) / Double(total)))
        return fraction.formatted(.percent.precision(.fractionLength(0)).locale(T.locale))
    }

    func gameFilesRows() -> [PanelRow] {
        let state = gameFiles
        if let job = state.working {
            let copying: Bool = if case .update = job { true } else { false }
            return [
                PanelRow(id: "files-progress", title: TFiles.format(copying ? .filesCopying : .filesUnpacking, AppModel.percentText(state.done, state.total)),
                         detail: TFiles.format(.filesProgress, state.done.byteText, state.total.byteText) + "\n" + TFiles.text(.filesKeepsGoing),
                         symbol: copying ? "doc.on.doc" : "archivebox", kind: .info(""), wraps: true),
                PanelRow(id: "files-stop", title: TFiles.text(.filesStop), symbol: "stop.circle", kind: .action(destructive: true) { [weak self] in self?.stopFiles() }),
            ]
        }
        switch state.asked {
        case .unpack(let archive, let plan, let into, let game):
            if let problem = plan.problem {
                return [
                    PanelRow(id: "files-about", title: archive.name, detail: TFiles.text(problem == .compressed ? .ffpfscCompressed : .ffpfscUnsupported), symbol: "exclamationmark.triangle", kind: .info(""), wraps: true),
                    PanelRow(id: "files-later", title: T.text(.close), kind: .action(destructive: false) { [weak self] in self?.filesLater() }),
                ]
            }
            if !plan.refused.isEmpty {
                return [
                    PanelRow(id: "files-about", title: archive.name, detail: TFiles.text(archive.isFfpfsc ? .unpackFileUnsafe : .unpackUnsafe), symbol: "exclamationmark.shield", kind: .info(""), wraps: true),
                    PanelRow(id: "files-later", title: T.text(.close), kind: .action(destructive: false) { [weak self] in self?.filesLater() }),
                ]
            }
            let beside = into.standardizedFileURL == archive.folder.standardizedFileURL
            let about = game != nil ? TFiles.format(.unpackUpdateAbout, GameAddons.shortVersion(plan.version ?? ""), into.lastPathComponent)
                : TFiles.format(beside ? .unpackAbout : .unpackAboutFolder, into.lastPathComponent)
            let free = FreeSpace.available(at: into.deletingLastPathComponent())
            let short = free.map { $0 < plan.size + GameArchives.spaceMargin } ?? false
            let space = short ? TFiles.format(.filesNoSpace, plan.size.byteText, (free ?? 0).byteText) : TFiles.format(.filesSpace, plan.size.byteText)
            var head = plan.titleName ?? archive.name
            if plan.titleName != nil, let titleID = plan.titleID { head += " (\(titleID))" }
            var rows = [PanelRow(id: "files-about", title: head, detail: about + " " + space, symbol: short ? "externaldrive.badge.exclamationmark" : "archivebox", kind: .info(""), picture: plan.icon, wraps: true)]
            if !short {
                rows.append(PanelRow(id: "files-go", title: TFiles.text(.unpackGo), symbol: "arrow.down.doc", kind: .action(destructive: false) { [weak self] in self?.startFiles() }))
            }
            rows.append(PanelRow(id: "files-later", title: short ? T.text(.close) : TFiles.text(.filesLater), kind: .action(destructive: false) { [weak self] in self?.filesLater() }))
            return rows
        case .update(let update, let game, let size):
            return [
                PanelRow(id: "files-about", title: TFiles.format(.addUpdateVersion, update.shortVersion),
                         detail: TFiles.format(.addUpdateAbout, GameUpdates.target(game).lastPathComponent, size.byteText), symbol: "shippingbox", kind: .info(""), wraps: true),
                PanelRow(id: "files-go", title: TFiles.text(.addUpdateGo), symbol: "plus.square.on.square", kind: .action(destructive: false) { [weak self] in self?.startFiles() }),
                PanelRow(id: "files-later", title: T.text(.cancel), kind: .action(destructive: false) { [weak self] in self?.filesLater() }),
            ]
        case nil:
            return []
        }
    }

    /// Not now: the panel closes; a zip is offered again at the next start.
    func filesLater() {
        if let archive = gameFiles.asked?.archive { gameFilesWork.later.insert(archive.url.path) }
        gameFiles.asked = nil
        if overlay == .gameFiles { closeOverlay() }
        offerNextFile()
    }

    /// Back: the question is answered Not Now; a job goes on behind the home screen.
    func filesBack() {
        guard gameFiles.working != nil else { return filesLater() }
        closeOverlay()
        show(TFiles.text(.filesKeepsGoing), symbol: "arrow.down.doc")
    }

    func stopFiles() { gameFilesWork.cancel?.cancel() }

    /// The job asked about, in the background: progress in the panel, a word and a new scan when
    /// it is done.
    func startFiles() {
        guard let job = gameFiles.asked, gameFiles.working == nil else { return }
        let needed: Int64, folder: URL
        switch job {
        case .unpack(_, let plan, let into, _): (needed, folder) = (plan.size, into.deletingLastPathComponent())
        case .update(_, let game, let size): (needed, folder) = (size, game.folder.deletingLastPathComponent())
        }
        let free = FreeSpace.available(at: folder)
        // A move needs no room; a copy or an unpack does, checked when it cannot be a move.
        var shortage: Bool { free.map { $0 < needed + GameArchives.spaceMargin } ?? false }
        if case .unpack = job, shortage {
            return show(TFiles.format(.filesNoSpace, needed.byteText, (free ?? 0).byteText), symbol: "externaldrive.badge.exclamationmark")
        }
        if case .update(let update, let game, _) = job, shortage, !GameUpdates.sameVolume(update.folder, game.folder.deletingLastPathComponent()) {
            return show(TFiles.format(.filesNoSpace, needed.byteText, (free ?? 0).byteText), symbol: "externaldrive.badge.exclamationmark")
        }
        let cancel = UnpackCancel()
        gameFilesWork.cancel = cancel
        gameFiles.working = job
        gameFiles.done = 0
        gameFiles.total = needed
        Sounds.shared.play(.select)
        // A few times a second at most: each one draws the panel again.
        let progress = ProgressThrottle { [weak self] done, total in
            Task { @MainActor in
                guard let self, self.gameFiles.working == job else { return }
                self.gameFiles.done = done
                self.gameFiles.total = total
            }
        }
        Task.detached(priority: .utility) {
            var moved = false
            var failure: Error?
            do {
                switch job {
                case .unpack(let archive, _, let into, _):
                    try GameArchives.unpack(archive, into: into, progress: progress.tell, cancel: cancel)
                case .update(let update, let game, _):
                    moved = try GameUpdates.install(update, for: game, progress: progress.tell, cancel: cancel)
                }
            } catch {
                failure = error
            }
            let wasMoved = moved, error = failure
            await MainActor.run { self.filesFinished(job, moved: wasMoved, failure: error) }
        }
    }

    private func filesFinished(_ job: FilesAsk, moved: Bool, failure: Error?) {
        gameFiles.working = nil
        gameFilesWork.cancel = nil
        if gameFiles.asked == job { gameFiles.asked = nil }
        if let archive = job.archive { gameFilesWork.waiting.removeAll { $0.archive == archive } }
        if overlay == .gameFiles { closeOverlay() }
        // The game (or its update) is read first: its own notice, then this word over it.
        rescan()
        let text: String
        var symbol = "checkmark.circle.fill"
        if let failure {
            symbol = "exclamationmark.triangle.fill"
            if failure is UnpackCancelled {
                text = TFiles.text(.filesStopped)
                symbol = "stop.circle"
            } else {
                NSLog("[anyps5-launcher] %@ failed: %@", job.archive?.name ?? "the update", String(describing: failure))
                switch job {
                case .unpack(let archive, _, _, _): text = TFiles.format(.unpackFailed, archive.name)
                case .update: text = TFiles.text(.addUpdateFailed)
                }
            }
        } else {
            switch job {
            case .unpack(_, _, _, let game?): text = TFiles.format(.unpackUpdateDone, game.name)
            case .unpack(let archive, _, _, _): text = TFiles.format(archive.isFfpfsc ? .unpackFileDone : .unpackDone, archive.name)
            case .update(_, let game, _): text = TFiles.format(moved ? .addUpdateMoved : .addUpdateCopied, game.name)
            }
            if preferences.sounds { Sounds.shared.play(.unlocked) }
        }
        if NSApp?.isActive ?? true {
            show(text, symbol: symbol)
        } else {
            TrophyBanner.shared.notice(text, detail: "", symbol: symbol, icon: nil, cue: .select, sounds: preferences.sounds)
        }
        offerNextFile()
    }

    /// The files panel drawn offscreen (`--render-preview`) without a zip on the disk.
    func previewFiles(_ state: GameFilesState) {
        gameFiles = state
        overlay = .gameFiles
        panelInRows = true
        panelRow = gameFilesRows().firstIndex(where: \.focusable) ?? 0
    }
}

/// Progress told at most five times a second, from the thread doing the work.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let deliver: @Sendable (Int64, Int64) -> Void

    init(_ deliver: @escaping @Sendable (Int64, Int64) -> Void) { self.deliver = deliver }

    func tell(_ done: Int64, _ total: Int64) {
        lock.lock()
        let now = Date()
        let due = done == total || now.timeIntervalSince(last) > 0.2
        if due { last = now }
        lock.unlock()
        if due { deliver(done, total) }
    }
}
