import AnyPS5Core
import AppKit
import Foundation

/// Settings › Engine › Update from Git: an engine folder that is a git checkout of AnyPS5-ARM,
/// pulled and built in place (git pull --ff-only, the submodules, ninja for the relinker and the
/// libraries) and made into an engine the launcher uses as Your Own Build. Games unlocked with the
/// build before then offer Relink All. Every command runs as its own process, away from the
/// interface. AnyLauncher Port's engine_git_model.dart, on the Mac.
struct EngineGitState: Equatable {
    /// The step running now, nil when idle.
    var step: GitStep?
    /// The last lines the running command printed.
    var lines: [String] = []
    /// Why the last update stopped, nil after one that went through.
    var failure: GitUpdateFailure?
    /// What the last update printed, for Copy.
    var output: [String] = []
    /// The last update went through: Relink All is offered for the games made before it.
    var updated = false
    /// The developer tools on this Mac, looked for when Settings opens.
    var tools: DevTools?
    /// The remote being asked for new commits before a game starts.
    var checking = false
    /// Homebrew's brew on this Mac, looked for with the tools: it installs CMake and Ninja.
    var homebrew: URL?
    /// The tools being installed now (Install now), nil when none are.
    var installing: [String]?
}

extension AppModel {
    /// The build guide: what to install (CMake, Ninja, the Command Line Tools) and the build
    /// folder's setup, which Update from Git runs itself when there is none.
    static let engineBuildGuide = URL(string: "https://github.com/AnyTogether/AnyPS5-ARM/blob/main/docs/dev/MACOS_PORT.md")!

    /// Where the engines made from the checkout's build are kept.
    static var gitEngineFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/GitEngine")
    }

    /// The chosen engine folder when it is a checkout of AnyPS5-ARM.
    var engineCheckout: EngineCheckout? {
        preferences.engineCheckout.flatMap { EngineCheckout.at(URL(fileURLWithPath: $0)) }
    }

    /// The developer tools looked for again, away from the interface (xcode-select runs).
    /// `announce` says what it found (Check again, and after an install): everything is there, or
    /// what still is not. Nothing has to be restarted: the folders are read again each time.
    func refreshEngineTools(announce: Bool = false) {
        guard let checkout = engineCheckout else { return }
        let cache = checkout.cache
        Task.detached(priority: .utility) {
            let tools = DevTools.find(cache: cache)
            let homebrew = DevTools.homebrew()
            await MainActor.run { self.engineToolsFound(tools, homebrew: homebrew, announce: announce) }
        }
    }

    func engineToolsFound(_ tools: DevTools, homebrew: URL?, announce: Bool) {
        if engineGit.tools != tools { engineGit.tools = tools }
        if engineGit.homebrew != homebrew { engineGit.homebrew = homebrew }
        // An update that stopped for a tool that is there now no longer says so.
        if tools.missing.isEmpty, let stopped = engineGit.failure, case .missingTools = stopped.kind { engineGit.failure = nil }
        guard announce else { return }
        if tools.missing.isEmpty {
            show(TE.text(.engineGitToolsReady), symbol: "checkmark.circle.fill")
        } else {
            show(TE.format(.engineGitStillMissing, ListFormatter.localizedString(byJoining: tools.missing)), symbol: "hammer")
        }
    }

    /// The rows under Update from Git while tools are missing: for each way to get them, the
    /// command to copy (or the page to open), Install now where the launcher can run it as the
    /// user (Homebrew), and Check again.
    func engineToolFixRows(_ tools: DevTools) -> [PanelRow] {
        var rows: [PanelRow] = []
        for fix in tools.fixes(homebrew: engineGit.homebrew) {
            let names = ListFormatter.localizedString(byJoining: fix.names)
            if let link = fix.link {
                rows.append(PanelRow(id: "engineGitFixLink-" + fix.id, title: TE.format(.engineGitFixBrew, names), detail: (link.host ?? "") + link.path, symbol: "link",
                                     kind: .action(destructive: false) { NSWorkspace.shared.open(link) }, wraps: true))
            }
            guard let command = fix.command else { continue }
            rows.append(PanelRow(id: "engineGitFixCopy-" + fix.id, title: TE.format(.engineGitFixCopy, names), detail: command, symbol: "doc.on.doc",
                                 kind: .action(destructive: false) { [weak self] in self?.copyEngineToolCommand(command) }, wraps: true))
            if fix.program != nil {
                rows.append(PanelRow(id: "engineGitFixRun-" + fix.id, title: TE.format(.engineGitFixRun, names), detail: TE.text(.engineGitFixRunDetail), symbol: "arrow.down.circle",
                                     kind: .action(destructive: false) { [weak self] in self?.installEngineTools(fix) }, wraps: true))
            }
        }
        rows.append(PanelRow(id: "engineGitRecheck", title: TE.text(.engineGitRecheck), detail: TE.text(.engineGitRecheckDetail), symbol: "arrow.clockwise",
                             kind: .action(destructive: false) { [weak self] in self?.refreshEngineTools(announce: true) }))
        return rows
    }

    func copyEngineToolCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        show(TE.text(.engineGitFixCopied), symbol: "doc.on.doc")
    }

    /// Install now: `fix`'s command run here as the user, its lines shown as an update's are. It
    /// never runs as administrator and nothing is typed into it; when it ends the tools are looked
    /// for again.
    func installEngineTools(_ fix: DevToolFix, runner: CommandRunner = SystemCommands()) {
        guard let program = fix.program, let checkout = engineCheckout, engineGit.step == nil, engineGit.installing == nil else { return }
        let cancel = UnpackCancel()
        engineGitCancel = cancel
        engineGit.installing = fix.names
        engineGit.lines = []
        let names = ListFormatter.localizedString(byJoining: fix.names)
        let arguments = fix.arguments, directory = checkout.root
        let lines = LineThrottle { [weak self] recent in
            Task { @MainActor in if self?.engineGit.installing != nil { self?.engineGit.lines = recent } }
        }
        Task.detached(priority: .userInitiated) {
            var environment = ProcessInfo.processInfo.environment
            // Homebrew's own folders on PATH (an app opened from the Finder has a short one).
            environment["PATH"] = (DevTools.extraFolders + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
            let code = (try? runner.run(program, arguments, in: directory, environment: environment, cancel: cancel, onLine: lines.add)) ?? -1
            let stopped = cancel.cancelled
            await MainActor.run { self.engineToolsInstalled(names, worked: code == 0, stopped: stopped) }
        }
    }

    func engineToolsInstalled(_ names: String, worked: Bool, stopped: Bool) {
        engineGitCancel = nil
        engineGit.installing = nil
        engineGit.lines = []
        if stopped { return }
        if worked {
            refreshEngineTools(announce: true)
        } else {
            Sounds.shared.play(.back)
            show(TE.format(.engineGitFixFailed, names), symbol: "exclamationmark.triangle.fill")
            refreshEngineTools()
        }
    }

    /// A checkout chosen as the engine folder: its build made into an engine at once when it is
    /// built already, else Update from Git builds it.
    func useEngineCheckout(_ checkout: EngineCheckout) {
        preferences.engineCheckout = checkout.root.path
        engineGit = EngineGitState()
        refreshEngineTools()
        show(TE.format(.engineFolderUsed, checkout.root.abbreviatedPath), symbol: "folder.badge.gearshape")
        guard checkout.isBuilt else { return }
        let vulkan = builtInToolkit ?? customToolkit ?? installedToolkits.first.map { Toolkit(root: $0.folder) }
        let folder = AppModel.gitEngineFolder
        Task.detached(priority: .utility) {
            let tools = DevTools.find(cache: checkout.cache)
            let release = EngineGit(checkout, tools: tools).describe()
            let toolkit = try? EngineGit.makeToolkit(from: checkout, vulkanFrom: vulkan, in: folder, release: release)
            await MainActor.run {
                guard let toolkit, self.preferences.engineCheckout == checkout.root.path else { return }
                self.useGitToolkit(toolkit)
            }
        }
    }

    /// The engine made from the build becomes Your Own Build and the default engine, as the engine
    /// folder is on Windows and Linux.
    private func useGitToolkit(_ toolkit: Toolkit) {
        preferences.customToolkit = toolkit.root.path
        customToolkit = toolkit
        if defaultEngine != .custom { preferences.engine = EngineChoice.custom.stored }
        if !unlockBusy { EngineGit.removeOld(in: AppModel.gitEngineFolder, keeping: toolkit.root) }
    }

    /// Settings › Engine › Update from Git Before Playing is on and the engine is a checkout.
    var updatesBeforePlay: Bool { preferences.engineGitBeforePlay == true && engineCheckout != nil }

    /// The checkout's remote asked before `game` starts, as on Windows and Linux: new commits are
    /// pulled and built first and the game unlocked again with the new build. Offline, without an
    /// upstream branch, or with nothing changed by a stopped update, the current build plays.
    func playAfterGitCheck(_ game: Game, play: @escaping () -> Void) {
        if let step = engineGit.step { return show(TE.format(.engineGitRunning, AppModel.engineGitStepName(step)), symbol: "hammer") }
        if engineGit.checking { return show(TE.text(.engineGitChecking), symbol: "hammer") }
        guard let checkout = engineCheckout else { return play() }
        // Another game is being unlocked with the build as it is: no build now, the game plays.
        if unlockBusy { return play() }
        let tools = engineGit.tools ?? DevTools.find(cache: checkout.cache)
        guard tools.git != nil else { return play() }
        engineGit.checking = true
        let built = preferences.engineGitBuilt?[checkout.root.path]
        let git = EngineGit(checkout, tools: tools)
        Task { @MainActor in
            let needed = await Task.detached(priority: .userInitiated) { git.needsUpdate(built: built) }.value
            engineGit.checking = false
            // An unlock began while the remote was asked: the build would rewrite what it uses.
            guard needed == true, !unlockBusy, engineCheckout?.root == checkout.root else { return play() }
            if !tools.missing.isEmpty {
                show(TE.format(.engineGitPlayAnyway, AppModel.engineGitReason(.missingTools(tools.missing))), symbol: "exclamationmark.triangle.fill")
                return play()
            }
            show(TE.text(.engineGitBeforePlayStart), symbol: "hammer")
            updateEngineFromGit(quiet: true) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    if case .installed(outdated: true) = self.state(of: game) { self.updateAndPlay(game) } else { play() }
                case .failure(let stopped) where stopped.kind == .cancelled:
                    self.show(TE.text(.engineGitStopped), symbol: "stop.circle")
                case .failure(let stopped) where stopped.untouched:
                    // Nothing changed (a tree with changes, offline): the current build plays.
                    self.show(TE.format(.engineGitPlayAnyway, AppModel.engineGitReason(stopped.kind)), symbol: "exclamationmark.triangle.fill")
                    play()
                case .failure(let stopped):
                    Sounds.shared.play(.back)
                    self.show(TE.format(.engineGitFailed, AppModel.engineGitReason(stopped.kind)), symbol: "exclamationmark.triangle.fill")
                }
            }
        }
    }

    /// Pulls, builds and makes the engine; `quiet` leaves what it says to `then`.
    func updateEngineFromGit(quiet: Bool = false, then: ((Result<GitUpdateResult, GitUpdateFailure>) -> Void)? = nil) {
        guard let checkout = engineCheckout, engineGit.step == nil, engineGit.installing == nil else { return }
        // A game being unlocked uses the engine the update would replace.
        if unlockBusy { return show(TE.text(.engineGitWaitUnlock), symbol: "hourglass") }
        let tools = engineGit.tools ?? DevTools.find(cache: checkout.cache)
        if !tools.missing.isEmpty {
            engineGit.tools = tools
            return show(TE.format(.engineGitNeeds, ListFormatter.localizedString(byJoining: tools.missing)), symbol: "hammer")
        }
        let cancel = UnpackCancel()
        engineGitCancel = cancel
        engineGit = EngineGitState(step: .checking, tools: tools)
        let vulkan = builtInToolkit ?? customToolkit ?? installedToolkits.first.map { Toolkit(root: $0.folder) }
        let folder = AppModel.gitEngineFolder
        let git = EngineGit(checkout, tools: tools)
        let lines = LineThrottle { [weak self] recent in
            Task { @MainActor in if self?.engineGit.step != nil { self?.engineGit.lines = recent } }
        }
        Task.detached(priority: .userInitiated) {
            let result: Result<GitUpdateResult, GitUpdateFailure>
            do {
                result = .success(try git.update(in: folder, vulkanFrom: vulkan, cancel: cancel, onStep: { step in
                    lines.reset()
                    Task { @MainActor in
                        self.engineGit.step = step
                        self.engineGit.lines = []
                    }
                }, onLine: lines.add))
            } catch let failure as GitUpdateFailure {
                result = .failure(failure)
            } catch {
                result = .failure(GitUpdateFailure(.build, [error.localizedDescription]))
            }
            let output = git.output
            await MainActor.run {
                self.engineGitFinished(result, output: output, checkout: checkout, quiet: quiet)
                then?(result)
            }
        }
    }

    private func engineGitFinished(_ result: Result<GitUpdateResult, GitUpdateFailure>, output: [String], checkout: EngineCheckout, quiet: Bool = false) {
        engineGitCancel = nil
        engineGit.step = nil
        engineGit.lines = []
        engineGit.output = output
        switch result {
        case .success(let done):
            var built = preferences.engineGitBuilt ?? [:]
            built[checkout.root.path] = done.after
            preferences.engineGitBuilt = built
            useGitToolkit(done.toolkit)
            engineGit.failure = nil
            engineGit.updated = true
            guard !quiet else { return }
            Sounds.shared.play(.unlocked)
            let commit = String(done.after.prefix(7))
            show(done.pulled ? TE.format(.engineGitDone, commit) : TE.format(.engineGitBuiltAt, commit), symbol: "hammer.fill")
        case .failure(let stopped):
            engineGit.failure = stopped.kind == .cancelled ? nil : stopped
            if quiet { return }
            if stopped.kind == .cancelled {
                show(TE.text(.engineGitStopped), symbol: "stop.circle")
            } else {
                Sounds.shared.play(.back)
                show(TE.format(.engineGitFailed, AppModel.engineGitReason(stopped.kind)), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func stopEngineGit() { engineGitCancel?.cancel() }

    /// Why an update stopped, for people.
    static func engineGitReason(_ kind: GitFailureKind) -> String {
        switch kind {
        case .missingTools(let names): return TE.format(.engineGitNeedsReason, ListFormatter.localizedString(byJoining: names))
        case .notGit: return TE.text(.engineGitNotGit)
        case .dirty: return TE.text(.engineGitDirty)
        case .noBuild: return TE.text(.engineGitNoBuildReason)
        case .configure: return TE.text(.engineGitConfigureFailed)
        case .pull: return TE.text(.engineGitPullFailed)
        case .submodules: return TE.text(.engineGitSubmodulesFailed)
        case .build: return TE.text(.engineGitBuildFailed)
        case .toolkit: return TE.text(.engineGitToolkitFailed)
        case .cancelled: return TE.text(.engineGitStopped)
        }
    }

    static func engineGitStepName(_ step: GitStep) -> String {
        switch step {
        case .checking: return TE.text(.engineGitStepChecking)
        case .pulling: return TE.text(.engineGitStepPulling)
        case .submodules: return TE.text(.engineGitStepSubmodules)
        case .configuring: return TE.text(.engineGitStepConfiguring)
        case .building: return TE.text(.engineGitStepBuilding)
        case .assembling: return TE.text(.engineGitStepAssembling)
        }
    }

    /// The output of the last update that stopped, the end that says why.
    var engineGitFailureText: String {
        guard let stopped = engineGit.failure else { return "" }
        return ([TE.format(.engineGitFailed, AppModel.engineGitReason(stopped.kind))] + engineGit.output + stopped.tail.filter { !engineGit.output.contains($0) })
            .joined(separator: "\n")
    }

    func copyEngineGitFailure() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engineGitFailureText, forType: .string)
        show(TE.text(.engineGitCopied), symbol: "doc.on.doc")
    }

    /// The installed games made with another engine than the one chosen for them now.
    var outdatedGames: [Game] {
        games.filter { if case .installed(outdated: true) = state(of: $0) { return true } else { return false } }
    }

    /// Unlocks again every installed game made with the build before.
    func relinkAll() {
        let outdated = outdatedGames
        guard !outdated.isEmpty else { return }
        for game in outdated { unlock(game) }
        show(TE.format(.engineGitRelinking, outdated.count), symbol: "arrow.triangle.2.circlepath")
    }

    /// The rows after Engine Folder when it is a git checkout.
    func engineGitRows() -> [PanelRow] {
        guard let checkout = engineCheckout else { return [] }
        let state = engineGit
        var rows: [PanelRow] = []
        if let step = state.step {
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.format(.engineGitRunning, AppModel.engineGitStepName(step)),
                                 detail: (state.lines.map { $0.trimmingCharacters(in: .whitespaces) } + [TE.text(.engineGitStop)]).joined(separator: "\n"),
                                 symbol: "hammer", kind: .action(destructive: true) { [weak self] in self?.stopEngineGit() }, wraps: true))
        } else if let installing = state.installing {
            rows.append(PanelRow(id: "engineGitFixRunning", title: TE.format(.engineGitFixRunning, ListFormatter.localizedString(byJoining: installing)),
                                 detail: (state.lines.map { $0.trimmingCharacters(in: .whitespaces) } + [TE.text(.engineGitStop)]).joined(separator: "\n"),
                                 symbol: "arrow.down.circle", kind: .action(destructive: true) { [weak self] in self?.stopEngineGit() }, wraps: true))
        } else if let tools = state.tools, !tools.missing.isEmpty {
            // Everything missing at once, then how to get each: nothing is found out one run at a time.
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.format(.engineGitNeeds, ListFormatter.localizedString(byJoining: tools.missing)),
                                 symbol: "hammer", kind: .action(destructive: false) { NSWorkspace.shared.open(AppModel.engineBuildGuide) }, wraps: true))
            rows += engineToolFixRows(tools)
        } else if let build = checkout.buildFolder {
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.format(.engineGitUpdateDetail, build.lastPathComponent),
                                 symbol: "hammer", kind: .action(destructive: false) { [weak self] in self?.updateEngineFromGit() }, wraps: true))
        } else {
            // No build folder yet: the update sets one up first, as on Windows and Linux.
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.text(.engineGitSetUpDetail),
                                 symbol: "hammer", kind: .action(destructive: false) { [weak self] in self?.updateEngineFromGit() }, wraps: true))
        }
        if state.step == nil, let stopped = state.failure {
            let shown = (stopped.tail.isEmpty ? state.output : stopped.tail).suffix(2).map { $0.trimmingCharacters(in: .whitespaces) }
            rows.append(PanelRow(id: "engineGitFailed", title: TE.format(.engineGitFailed, AppModel.engineGitReason(stopped.kind)),
                                 detail: (shown + [TE.text(.engineGitCopy)]).joined(separator: "\n"), symbol: "exclamationmark.triangle",
                                 kind: .action(destructive: false) { [weak self] in self?.copyEngineGitFailure() }, wraps: true))
            // A tool to install, or CMake's setup: the guide says how.
            if stopped.guideHelps {
                rows.append(PanelRow(id: "engineGitGuide", title: TE.text(.engineGitGuideMac), detail: AppModel.engineBuildGuide.host.map { $0 + AppModel.engineBuildGuide.path } ?? "",
                                     symbol: "book", kind: .action(destructive: false) { NSWorkspace.shared.open(AppModel.engineBuildGuide) }, wraps: true))
            }
        }
        let outdated = state.updated && state.step == nil ? outdatedGames.count : 0
        if outdated > 0 {
            rows.append(PanelRow(id: "engineGitRelinkAll", title: TE.text(.engineGitRelinkAll), detail: TE.format(.engineGitRelinkAllDetail, outdated),
                                 symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in self?.relinkAll() }))
        }
        rows.append(PanelRow(id: "engineGitBeforePlay", title: TE.text(.engineGitBeforePlay), detail: TE.text(.engineGitBeforePlayDetail), symbol: "arrow.down.circle",
                             kind: .toggle(preferences.engineGitBeforePlay == true) { [weak self] value in self?.preferences.engineGitBeforePlay = value ? true : nil }))
        return rows
    }
}

/// The last three lines a command printed, told a few times a second at most (a build prints a
/// line per file).
final class LineThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var recent: [String] = []
    private var last = Date.distantPast
    private let deliver: @Sendable ([String]) -> Void

    init(_ deliver: @escaping @Sendable ([String]) -> Void) { self.deliver = deliver }

    func reset() {
        lock.lock()
        recent = []
        lock.unlock()
    }

    func add(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lock.lock()
        recent.append(line)
        if recent.count > 3 { recent.removeFirst(recent.count - 3) }
        let now = Date()
        let due = now.timeIntervalSince(last) > 0.25
        if due { last = now }
        let lines = recent
        lock.unlock()
        if due { deliver(lines) }
    }
}
