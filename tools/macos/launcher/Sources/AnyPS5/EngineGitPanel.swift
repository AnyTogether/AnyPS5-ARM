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
}

extension AppModel {
    /// The build guide: configuring a build folder once is the player's (CMake, Ninja, the Command
    /// Line Tools).
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
    func refreshEngineTools() {
        guard let checkout = engineCheckout else { return }
        let cache = checkout.cache
        Task.detached(priority: .utility) {
            let tools = DevTools.find(cache: cache)
            await MainActor.run { if self.engineGit.tools != tools { self.engineGit.tools = tools } }
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

    /// Pulls, builds and makes the engine.
    func updateEngineFromGit() {
        guard let checkout = engineCheckout, engineGit.step == nil else { return }
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
            await MainActor.run { self.engineGitFinished(result, output: output, checkout: checkout) }
        }
    }

    private func engineGitFinished(_ result: Result<GitUpdateResult, GitUpdateFailure>, output: [String], checkout: EngineCheckout) {
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
            Sounds.shared.play(.unlocked)
            let commit = String(done.after.prefix(7))
            show(done.pulled ? TE.format(.engineGitDone, commit) : TE.format(.engineGitBuiltAt, commit), symbol: "hammer.fill")
        case .failure(let stopped):
            engineGit.failure = stopped.kind == .cancelled ? nil : stopped
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
        } else if let missing = state.tools?.missing, !missing.isEmpty {
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.format(.engineGitNeeds, ListFormatter.localizedString(byJoining: missing)),
                                 symbol: "hammer", kind: .action(destructive: false) { NSWorkspace.shared.open(AppModel.engineBuildGuide) }, wraps: true))
        } else if let build = checkout.buildFolder {
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.format(.engineGitUpdateDetail, build.lastPathComponent),
                                 symbol: "hammer", kind: .action(destructive: false) { [weak self] in self?.updateEngineFromGit() }, wraps: true))
        } else {
            rows.append(PanelRow(id: "engineGitUpdate", title: TE.text(.engineGitUpdate), detail: TE.text(.engineGitNoBuild),
                                 symbol: "hammer", kind: .action(destructive: false) { NSWorkspace.shared.open(AppModel.engineBuildGuide) }, wraps: true))
        }
        if state.step == nil, let stopped = state.failure {
            let shown = (stopped.tail.isEmpty ? state.output : stopped.tail).suffix(2).map { $0.trimmingCharacters(in: .whitespaces) }
            rows.append(PanelRow(id: "engineGitFailed", title: TE.format(.engineGitFailed, AppModel.engineGitReason(stopped.kind)),
                                 detail: (shown + [TE.text(.engineGitCopy)]).joined(separator: "\n"), symbol: "exclamationmark.triangle",
                                 kind: .action(destructive: false) { [weak self] in self?.copyEngineGitFailure() }, wraps: true))
        }
        let outdated = state.updated && state.step == nil ? outdatedGames.count : 0
        if outdated > 0 {
            rows.append(PanelRow(id: "engineGitRelinkAll", title: TE.text(.engineGitRelinkAll), detail: TE.format(.engineGitRelinkAllDetail, outdated),
                                 symbol: "arrow.triangle.2.circlepath", kind: .action(destructive: false) { [weak self] in self?.relinkAll() }))
        }
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
