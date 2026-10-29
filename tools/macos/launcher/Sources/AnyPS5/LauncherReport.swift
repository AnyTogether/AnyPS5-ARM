import AnyPS5Core
import AppKit
import SwiftUI
import SystemConfiguration

/// The launcher's own health for this run: its marker, the catcher of an uncaught exception or a
/// fatal signal, and the watchdog the main thread pings four times a second (LauncherHealth).
@MainActor
final class LauncherWatch {
    static let shared = LauncherWatch()
    private(set) var health: LauncherHealth?
    private var watch: StallWatch?
    private var pinger: Timer?
    private var lines: [String] = []
    private var second = ProcessInfo.processInfo.systemUptime
    private var lastPing = ProcessInfo.processInfo.systemUptime
    private var worstGap: TimeInterval = 0
    /// What is on screen, for the line a second the report keeps.
    var describe: (() -> String)?
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Starts this run's watch (not under a debugger); `found` gets what an earlier run left.
    func start(version: String, found: @escaping @MainActor (LauncherProblem) -> Void) {
        guard health == nil, !LauncherHealth.debuggerAttached else { return }
        let bundle = Bundle.main.bundleIdentifier ?? "org.anyps5.launcher"
        let health = LauncherHealth(version: version, crashReport: { since, pid in
            Diagnosis.crashReport(since: since, bundleIdentifier: bundle, pid: pid, process: "AnyPS5")
        })
        self.health = health
        let started = Date()
        // Reading the folder and macOS's crash reports is off the main thread.
        Task.detached(priority: .utility) {
            let problem = health.start(now: started)
            CrashCatcher.install(health: health)
            await MainActor.run {
                self.watch = StallWatch(health: health, started: started)
                self.startPinging()
                if let problem { found(problem) }
            }
        }
    }

    private func startPinging() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.ping() } }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pinger = timer
    }

    private func ping() {
        let now = ProcessInfo.processInfo.systemUptime
        let front = NSApp?.isActive == true
        worstGap = max(worstGap, now - lastPing)
        lastPing = now
        var changed: [String]?
        if now - second >= 1 {
            lines.append("\(Self.clock.string(from: Date())) \(describe?() ?? "") · longest main-thread gap \(Int(worstGap * 1000)) ms" + (front ? "" : " · behind"))
            if lines.count > LauncherHealth.keptLines { lines.removeFirst(lines.count - LauncherHealth.keptLines) }
            second = now
            worstGap = 0
            changed = lines
        }
        watch?.ping(watching: front, lines: changed, error: nil)
    }

    /// The launcher quits as it should: nothing to offer next time.
    func quitting() {
        pinger?.invalidate()
        pinger = nil
        watch?.closing()
        health?.closed()
    }
}

/// An earlier run's crash or stall, the issue it opens and how to put it aside.
struct LauncherReportState {
    let problem: LauncherProblem
    var issue: IssueDraft?
    let forget: () -> Void
    var offered = false

    /// "AnyPS5 closed unexpectedly", "AnyPS5 froze for 12 seconds", "AnyPS5 froze and was closed".
    var headline: String {
        switch problem.kind {
        case .crash: return TC.text(.launcherReportCrash)
        case .hang where problem.recovered == true: return TC.format(.launcherReportHang, Int((problem.stalledFor ?? 0).rounded()))
        case .hang: return TC.text(.launcherReportHangEnded)
        }
    }
}

extension AppModel {
    /// This run's marker and watchdog; an earlier run's crash or stall is offered once the home
    /// screen is free.
    func watchLauncher() {
        LauncherWatch.shared.describe = { [weak self] in self?.healthLine ?? "" }
        LauncherWatch.shared.start(version: AppModel.launcherVersion) { [weak self] problem in
            self?.launcherProblemFound(problem) { LauncherWatch.shared.health?.forget() }
        }
    }

    /// What the report's line a second says is on screen.
    var healthLine: String {
        var parts = [overlay.map { "\($0)" } ?? "Home (\(focus))"]
        parts.append("\(games.count) games, #\(selected)")
        if let starting { parts.append("starting \(starting.titleID)") }
        if let running { parts.append("playing \(running.game.titleID)") }
        return parts.joined(separator: " · ")
    }

    /// An earlier run's problem: the issue is made off the main thread, and the panel waits for
    /// the home screen to be free.
    func launcherProblemFound(_ problem: LauncherProblem, forget: @escaping () -> Void) {
        launcherReport = LauncherReportState(problem: problem, forget: forget)
        let names = [SCDynamicStoreCopyComputerName(nil, nil) as String?, togetherUser?.handle, togetherUser?.displayName].compactMap { $0 }
        let secrets = allSecrets
        let display = NSScreen.main?.maximumFramesPerSecond
        Task.detached(priority: .utility) {
            let issue = IssueDraft.launcherProblem(problem, system: .current(displayHz: display), privacy: .current(names: names, secrets: secrets))
            await MainActor.run {
                self.launcherReport?.issue = issue
                self.offerLauncherReport()
            }
        }
    }

    /// The home screen became free: the report, once, if there is one.
    func offerLauncherReportSoon() {
        guard launcherReport.map({ !$0.offered }) == true else { return }
        DispatchQueue.main.async { [weak self] in self?.offerLauncherReport() }
    }

    func offerLauncherReport() {
        guard var report = launcherReport, !report.offered, report.issue != nil, preferences.onboarded, overlay == nil,
              starting == nil, running == nil, pairing == nil, ringing == nil, fontWait == nil, shareWatch == nil else { return }
        report.offered = true
        launcherReport = report
        menuIndex = 0
        open(.launcherReport)
    }

    /// Send Report: the issue opens filled in, to be sent there; it is not offered again.
    func sendLauncherReport() {
        guard let report = launcherReport, let issue = report.issue else { return closeOverlay() }
        Sounds.shared.play(.select)
        openLink(issue.url)
        report.forget()
        launcherReport = nil
        withAnimation(Motion.overlay) { overlay = nil }
    }

    /// Not Now: put aside for good.
    func putLauncherReportAside() {
        launcherReport?.forget()
        launcherReport = nil
        closeOverlay()
    }
}
