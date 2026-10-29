import AnyPS5Core
import AppKit
import SwiftUI
import SystemConfiguration
import UniformTypeIdentifiers

/// The report of one game's last start, as the crash panel shows it.
struct SessionReportState {
    let game: Game
    /// Opened because the game stopped, not from its options.
    let afterCrash: Bool
    /// Read off the main thread; nil until then.
    var report: SessionReport?
    var issue: IssueDraft?
    var engineIssue: IssueDraft?
    /// The end of the log the panel shows, cleaned like the report.
    var tail: [String] = []
    /// The step that shows what the issue will carry before it opens.
    var sharing = false
}

/// What the launcher knows about a game's last start beyond its log.
struct LastSession {
    var started = Date()
    var traced = false
    var pid: pid_t?
    var ended: Date?
    var withoutWindow = false
}

extension AppModel {
    nonisolated static var launcherVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    /// The game stopped abnormally: the report is offered at once, over the home screen, or said
    /// in a toast when something else is open.
    func offerReport(_ game: Game) {
        // Over "How did it run?" too: after a crash the report matters more.
        guard running == nil, starting == nil, overlay == nil || overlay == .log || overlay == .compat else {
            let reason = diagnoses[game.id]?.summary ?? TC.text(.reportNoWindow)
            return show(game.name + ": " + reason, symbol: "exclamationmark.triangle.fill")
        }
        Sounds.shared.play(.back)
        openSessionReport(game, afterCrash: true)
    }

    /// Opens the crash panel on the game's last start and reads its report off the main thread:
    /// the log, macOS's crash report for that process, the last unlock's output and this Mac.
    func openSessionReport(_ game: Game, afterCrash: Bool) {
        sessionReport = SessionReportState(game: game, afterCrash: afterCrash)
        open(.crashReport)
        let facts = lastSessions[game.id]
        let settings = launchSettings(for: game)
        let unlockedWith = installedRecords[game.id]?.toolkit
        let engineNow = engineVersion(for: game)
        let diagnosis = diagnoses[game.id]
        let channel = updateChannel.rawValue
        let display = NSScreen.main?.maximumFramesPerSecond
        let controllers = Controllers.shared.reportLines
        // The computer's name from SystemConfiguration: Host.current() can wait on the network.
        let names = [SCDynamicStoreCopyComputerName(nil, nil) as String?, togetherUser?.handle, togetherUser?.displayName].compactMap { $0 }
        let secrets = allSecrets
        Task.detached(priority: .userInitiated) {
            let session = Diagnosis.lastSession(GameLog.tail(GameLog.file(titleID: game.titleID), bytes: 32 << 20))
            let since = facts?.started ?? Date().addingTimeInterval(-86_400)
            let crash = Diagnosis.crashReport(since: since, bundleIdentifier: game.bundleIdentifier, pid: facts?.pid)
            var report = SessionReport(gameName: game.name, titleID: game.titleID, gameVersion: game.version, settings: settings,
                                       system: .current(displayHz: display), launcherVersion: AppModel.launcherVersion, session: session,
                                       privacy: .current(names: names, secrets: secrets))
            report.updateChannel = channel
            report.unlockedWith = unlockedWith
            report.engineNow = engineNow
            report.diagnosis = diagnosis ?? Diagnosis.read(session: session, crashReport: crash)
            report.startedWithoutWindow = facts?.withoutWindow ?? false
            // A start the launcher no longer remembers says so on its start line.
            report.traced = facts?.traced ?? session.prefix { $0 != "\n" }.hasSuffix(" trace")
            report.started = facts?.started
            report.ended = facts?.ended
            report.crashReport = crash
            report.unlockLog = GameLog.readUnlockLog(titleID: game.titleID)
            report.controllers = controllers
            let finished = report
            let issue = IssueDraft.crash(finished)
            let engineIssue = IssueDraft.engine(finished)
            let tail = finished.logTail(48)
            await MainActor.run {
                guard self.sessionReport?.game.id == game.id else { return }
                self.sessionReport?.report = finished
                self.sessionReport?.issue = issue
                self.sessionReport?.engineIssue = engineIssue
                self.sessionReport?.tail = tail
            }
        }
    }

    func crashReportRows() -> [PanelRow] {
        guard let current = sessionReport else { return [] }
        let game = current.game
        let name = current.report?.fileName ?? "AnyPS5-\(game.titleID).zip"
        let export = PanelRow(id: "export", title: TC.text(.reportExport), detail: TC.format(.reportExportDetail, name), symbol: "square.and.arrow.down",
                              kind: .action(destructive: false) { [weak self] in self?.exportReport() })
        if current.sharing {
            return [
                PanelRow(id: "github", title: TC.text(.reportGitHub), detail: TC.text(.reportGitHubDetail), symbol: "arrow.up.forward.app",
                         kind: .action(destructive: false) { [weak self] in self?.openIssue(engine: false) }),
                PanelRow(id: "engine", title: TC.text(.reportEngine), detail: TC.text(.reportEngineDetail), symbol: "gearshape.2",
                         kind: .action(destructive: false) { [weak self] in self?.openIssue(engine: true) }),
                export,
                PanelRow(id: "back", title: TC.text(.reportBack), symbol: "chevron.left", kind: .action(destructive: false) { [weak self] in self?.leaveSharing() }),
            ]
        }
        var rows = [
            export,
            PanelRow(id: "issue", title: TC.text(.reportOpenIssue), detail: TC.text(.reportOpenIssueDetail), symbol: "exclamationmark.bubble",
                     kind: .action(destructive: false) { [weak self] in self?.enterSharing() }),
            PanelRow(id: "log", title: TC.text(.reportShowLog), symbol: "doc.text", kind: .action(destructive: false) { [weak self] in self?.openLog(game) }),
        ]
        if case .installed = state(of: game) {
            rows.append(PanelRow(id: "trace", title: TC.text(.reportPlayTraced), detail: TC.text(.reportPlayTracedDetail), symbol: "text.magnifyingglass",
                                 kind: .action(destructive: false) { [weak self] in
                self?.closeOverlay()
                self?.play(game, trace: true)
            }))
        }
        rows.append(PanelRow(id: "close", title: T.text(.close), symbol: "xmark", kind: .action(destructive: false) { [weak self] in self?.closeOverlay() }))
        return rows
    }

    /// Back steps out of the shared text first; Options closes the panel.
    func crashReportCommand(_ command: Command) -> Bool {
        if command == .back, sessionReport?.sharing == true {
            leaveSharing()
            return true
        }
        if command == .back || command == .options {
            closeOverlay()
            return true
        }
        return panelCommand(command)
    }

    private func enterSharing() {
        guard sessionReport?.issue != nil else { return }
        Sounds.shared.play(.select)
        withAnimation(Motion.overlay) { sessionReport?.sharing = true }
        panelRow = 0
    }

    private func leaveSharing() {
        Sounds.shared.play(.back)
        withAnimation(Motion.overlay) { sessionReport?.sharing = false }
        panelRow = 1
    }

    private func openIssue(engine: Bool) {
        guard let current = sessionReport, let draft = engine ? current.engineIssue : current.issue else { return }
        Sounds.shared.play(.select)
        NSWorkspace.shared.open(draft.url)
        show(TC.format(.reportIssueOpened, current.report?.fileName ?? ""), symbol: "arrow.up.forward.app")
    }

    /// Saves the report where the user picks, the Desktop first. The panel is all this does; the
    /// report itself is made by SessionReport.
    func exportReport() {
        guard let report = sessionReport?.report else { return }
        let panel = NSSavePanel()
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = report.fileName
        panel.allowedContentTypes = [report.archived ? .zip : .plainText]
        panel.canCreateDirectories = true
        panel.prompt = TC.text(.reportExport)
        guard panel.runModal() == .OK, let file = panel.url else { return }
        Task.detached(priority: .userInitiated) {
            let written = (try? report.write(to: file)) != nil
            await MainActor.run {
                guard written else { return self.show(TC.text(.reportSaveFailed), symbol: "exclamationmark.triangle.fill") }
                NSWorkspace.shared.activateFileViewerSelecting([file])
                self.show(TC.format(.reportSaved, file.lastPathComponent), symbol: "doc.badge.checkmark")
            }
        }
    }

    /// Fills the panel with a made-up report, for the previews.
    func previewSessionReport(_ report: SessionReport, sharing: Bool) {
        guard let game = selectedGame else { return }
        sessionReport = SessionReportState(game: game, afterCrash: true, report: report, issue: IssueDraft.crash(report), engineIssue: IssueDraft.engine(report),
                                           tail: report.logTail(48), sharing: sharing)
        overlay = .crashReport
        panelInRows = true
        panelRow = 0
    }
}

/// After a game stopped (or from its options): why, on which Mac and engine, the end of its log,
/// and the actions to export the report or open an issue; the issue's text before it is shared.
struct CrashReportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.previewRender) private var previewRender

    var body: some View {
        if let current = model.sessionReport {
            HStack(alignment: .top, spacing: 40 * scale) {
                VStack(alignment: .leading, spacing: 22 * scale) {
                    header(current)
                    reason(current)
                    if let report = current.report { facts(report) }
                    RowList(rows: model.panelCategories().first?.rows ?? [], focusedRow: model.panelRow)
                    hints(current)
                }
                .frame(width: 540 * scale, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                side(current)
            }
            .padding(.horizontal, 70 * scale)
            .padding(.vertical, 56 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .screenFrost(0.74)
        }
    }

    private func header(_ current: SessionReportState) -> some View {
        HStack(spacing: 20 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(0.08))
                if let icon = current.game.icon {
                    ArtworkImage(url: icon, maxPixels: 400)
                } else {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 26 * scale)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 76 * scale, height: 76 * scale)
            .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(TC.text(current.sharing ? .reportKickerShare : .reportKicker))
                    .font(.display(12 * scale, .semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(current.afterCrash ? TC.format(.reportStopped, current.game.name) : TC.format(.reportLastSession, current.game.name))
                    .font(.display(30 * scale, .light))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
    }

    private func reasonText(_ current: SessionReportState) -> String? {
        guard let report = current.report else { return nil }
        if let diagnosis = report.diagnosis { return diagnosis.summary }
        return TC.text(report.startedWithoutWindow ? .reportNoWindow : .reportNormal)
    }

    private func reason(_ current: SessionReportState) -> some View {
        let abnormal = current.report?.abnormal ?? current.afterCrash
        return HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
            Image(systemName: current.report == nil ? "hourglass" : abnormal ? "exclamationmark.triangle.fill" : "checkmark.circle")
            Text(reasonText(current) ?? TC.text(.reportReading))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
        .font(.display(16 * scale, .medium))
        .foregroundStyle(abnormal ? Color(red: 1, green: 0.78, blue: 0.5) : .white.opacity(0.85))
        .padding(16 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(14 * scale, opacity: 0.5)
    }

    private func facts(_ report: SessionReport) -> some View {
        let engine = report.unlockedWith ?? report.engineNow
        let seconds: Int? = report.started.flatMap { started in report.ended.map { Int($0.timeIntervalSince(started)) } }
        let crash = report.crashReport.flatMap(Diagnosis.crashException) ?? TC.text(.reportCrashNone)
        let rows: [(String, String)] = [
            (TC.text(.reportFactMac), "\(report.system.model) · \(report.system.chip) · \(report.system.memoryGB) GB · macOS \(report.system.macOS.split(separator: " ").first ?? "")"),
            (TC.text(.reportFactEngine), engine.map(Toolkit.shortVersion) ?? "—"),
            (TC.text(.reportFactCrash), crash),
            (TC.text(.reportFactSession), seconds.map { TC.format(.reportRan, max(0, $0) / 60) } ?? "—"),
            (TC.text(.reportFactLogging), report.traced ? TC.text(.reportOn) : T.text(.off)),
        ]
        return Grid(alignment: .leading, horizontalSpacing: 18 * scale, verticalSpacing: 7 * scale) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0).foregroundStyle(.white.opacity(0.5))
                    Text(row.1).foregroundStyle(.white.opacity(0.88)).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .font(.display(14 * scale))
        .padding(.horizontal, 4 * scale)
    }

    private func hints(_ current: SessionReportState) -> some View {
        HStack(spacing: 22 * scale) {
            Hint(keys: "↑ ↓", label: T.text(.hintMove))
            Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
            Hint(keys: "esc / ○", label: current.sharing ? TC.text(.reportBack) : T.text(.close))
        }
    }

    /// The end of the log, or the issue's text exactly as the link carries it.
    private func side(_ current: SessionReportState) -> some View {
        let sharing = current.sharing
        let text: String
        if sharing {
            text = current.issue?.preview ?? ""
        } else if current.report != nil {
            text = current.tail.isEmpty ? TC.text(.reportNoLog) : current.tail.joined(separator: "\n")
        } else {
            text = ""
        }
        return VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 10 * scale) {
                Image(systemName: sharing ? "eye" : "text.alignleft").foregroundStyle(model.accent)
                Text(TC.text(sharing ? .reportShareTitle : .reportLogTail)).font(.display(18 * scale, .semibold)).foregroundStyle(.white)
            }
            if sharing {
                Text(TC.text(.reportShareDetail))
                    .font(.display(13 * scale))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            textPane(text, newestLast: !sharing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glass(14 * scale, opacity: 0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func textPane(_ text: String, newestLast: Bool) -> some View {
        let content = Text(text)
            .font(.system(size: 11.5 * scale, design: .monospaced))
            .foregroundStyle(.white.opacity(0.82))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18 * scale)
        if previewRender {
            Color.clear.overlay(alignment: newestLast ? .bottom : .top) { content }.clipped()
        } else {
            ScrollView { content }
                .defaultScrollAnchor(newestLast ? .bottom : .top)
                .id(newestLast)
        }
    }
}
