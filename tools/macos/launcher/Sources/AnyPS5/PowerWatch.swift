import AnyPS5Core
import AppKit
import SwiftUI

/// Settings → Battery & Heat at work: the Mac's power read every few seconds and on macOS's
/// notices, the policy (AnyPS5Core/PowerProfiles.swift) fed with it, and what it decides handed
/// to the model, which tells the game (EngineControl's file) and dims the launcher.
@MainActor
final class PowerWatch {
    /// Seconds between readings: the policy's settle and cool-down count in these.
    static let interval: TimeInterval = 5

    private(set) var reading = PowerReading.pluggedIn
    private(set) var policy = PowerPolicy()
    private var estimate = BatteryEstimate()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var shown: [String] = []

    /// After every reading or change: the adjustment before it, whether it entered a hot spell,
    /// and whether anything the screens show changed.
    var changed: ((_ before: PowerAdjustment, _ becameHot: Bool, _ shownChanged: Bool) -> Void)?

    var profiles: PowerProfiles {
        get { policy.profiles }
        set {
            guard newValue != policy.profiles else { return }
            let before = policy.adjustment
            policy.profiles = newValue
            report(before, becameHot: false)
        }
    }

    var adjustment: PowerAdjustment { policy.adjustment }
    var mode: PowerMode { policy.mode }
    var canUndo: Bool { policy.canUndo }

    /// Minutes of battery left, nil plugged in or while there is no estimate yet.
    var minutesLeft: Int? { reading.onBattery ? estimate.minutesLeft(system: reading.minutesToEmpty) : nil }

    func start() {
        guard timer == nil else { return }
        read()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.read() }
            })
        }
    }

    /// A reading taken now, or the one given (the previews').
    func read(_ reading: PowerReading = .current(), at now: Date = Date()) {
        let before = policy.adjustment
        self.reading = reading
        if let percent = reading.batteryPercent { estimate.add(percent: percent, onBattery: reading.onBattery, at: now) }
        policy.update(reading, at: now)
        report(before, becameHot: policy.becameHot)
    }

    func undo() {
        let before = policy.adjustment
        policy.undo()
        report(before, becameHot: false)
    }

    private func report(_ before: PowerAdjustment, becameHot: Bool) {
        let now = [String(reading.hasBattery), String(reading.onBattery), String(describing: reading.batteryPercent), String(describing: minutesLeft),
                   String(reading.thermal.rawValue), String(reading.lowPowerMode), mode.rawValue, String(canUndo), "\(policy.adjustment)"]
        let shownChanged = now != shown
        shown = now
        changed?(before, becameHot, shownChanged)
    }
}

extension AppModel {
    /// The file the running game reads its frame cap and frame generation pause from.
    static var powerControlFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AnyPS5/Power/control.txt")
    }

    var powerProfiles: PowerProfiles { preferences.powerProfiles ?? PowerProfiles() }

    /// Readings start with the app (not for the previews, which set theirs).
    func startPowerWatch() {
        power.changed = { [weak self] before, becameHot, shownChanged in self?.powerChanged(before: before, becameHot: becameHot, shownChanged: shownChanged) }
        if persists { power.start() }
    }

    private func powerChanged(before: PowerAdjustment, becameHot: Bool, shownChanged: Bool) {
        let adjustment = power.adjustment
        if adjustment != before {
            if persists { try? EngineControl.write(adjustment, to: Self.powerControlFile) }
            Motion.reduced = preferences.reducedMotion || adjustment.dimEffects
        }
        if becameHot, running != nil, power.mode == .hot, !adjustment.isNone {
            TrophyBanner.shared.notice(TPow.text(.hotTitle), detail: Self.hotDetail(lowered: adjustment.frameCap > 0),
                                       symbol: "thermometer.sun.fill", cue: .move, sounds: preferences.sounds)
        }
        if shownChanged { objectWillChange.send() }
    }

    /// "AnyPS5 lowered the frame rate. To undo: PS › Quick Menu"
    static func hotDetail(lowered: Bool) -> String {
        TPow.format(.hotDetail, TPow.text(lowered ? .hotLowered : .hotEased))
    }

    /// The launcher's heavy effects (Glass blur, moving backgrounds, animations) turned down.
    var powerDimmed: Bool { power.adjustment.dimEffects }

    func undoPowerAdjustment() {
        guard power.canUndo else { return }
        power.undo()
        Sounds.shared.play(.select)
        show(TPow.text(.undone), symbol: "arrow.uturn.backward")
    }

    func setPowerProfiles(_ change: (inout PowerProfiles) -> Void) {
        var profiles = powerProfiles
        change(&profiles)
        preferences.powerProfiles = profiles == PowerProfiles() ? nil : profiles
    }

    // MARK: Starting a game

    /// What a game starts with: the cap and the control file it reads while it runs.
    func powerEnvironment() -> [String: String] {
        let adjustment = power.adjustment
        if persists { try? EngineControl.write(adjustment, to: Self.powerControlFile) }
        return EngineControl.environment(file: Self.powerControlFile, adjustment: adjustment)
    }

    /// The resolution `game` starts at under a lower-resolution profile, nil to keep `current`.
    func powerResolution(for game: Game, current: String?) -> String? {
        guard power.adjustment.lowerResolution, let toolkit = toolkit(for: game),
              let resolution = GamePatches.load(titleID: game.titleID, from: toolkit.patches)?.resolution else { return nil }
        return PowerResolution.lower(than: current ?? resolution.default, choices: resolution.choices)
    }

    // MARK: Words

    static func duration(minutes: Int) -> String {
        minutes >= 60 ? TPow.format(.hoursMinutes, minutes / 60, minutes % 60) : TPow.format(.minutes, minutes)
    }

    /// "On battery · 64% · about 2 h 5 min left", "Plugged in", or the desktop Mac's line.
    var powerSourceLine: String {
        let reading = power.reading
        guard reading.hasBattery else { return TPow.text(.noBattery) }
        guard reading.onBattery else { return TPow.text(.pluggedIn) }
        var parts = [reading.batteryPercent.map { TPow.format(.onBatteryPercent, $0) } ?? TPow.text(.onBattery)]
        parts.append(power.minutesLeft.map { TPow.format(.timeLeft, Self.duration(minutes: $0)) } ?? TPow.text(.estimating))
        return parts.joined(separator: " · ")
    }

    var thermalLine: String {
        switch power.reading.thermal {
        case .nominal: return TPow.text(.thermalNominal)
        case .fair: return TPow.text(.thermalFair)
        case .serious: return TPow.text(.thermalSerious)
        case .critical: return TPow.text(.thermalCritical)
        }
    }

    /// The profile in force by name, with its cap: "Battery profile · 40 FPS cap".
    var powerProfileLine: String {
        let adjustment = power.adjustment
        let name: String
        switch power.mode {
        case .hot: name = TPow.text(.profileHot)
        case .battery where !adjustment.isNone: name = TPow.text(.profileBattery)
        case .battery: name = power.policy.batteryUndone && powerProfiles.battery.on ? TPow.format(.profileUndone, TPow.text(.profileBattery)) : TPow.text(.profileNone)
        case .pluggedIn: name = power.policy.hot && power.policy.hotUndoneAt != nil ? TPow.format(.profileUndone, TPow.text(.profileHot)) : TPow.text(.profileNone)
        }
        return adjustment.frameCap > 0 ? name + " · " + TPow.format(.capSummary, adjustment.frameCap) : name
    }

    /// The profile Undo would lift: the heat's first.
    private var undoTitle: String { TPow.text(power.mode == .hot ? .quickUndoHot : .quickUndoBattery) }

    /// The quick menu's Undo item, nil when there is nothing to undo.
    var quickMenuUndo: (title: String, detail: String)? {
        power.canUndo ? (undoTitle, TPow.text(.quickUndoDetail)) : nil
    }

    // MARK: Settings → Battery & Heat

    func powerRows() -> [PanelRow] {
        let profiles = powerProfiles
        var rows: [PanelRow] = [
            PanelRow(id: "powerIntro", title: TPow.text(.intro), kind: .info("")),
            PanelRow(id: "powerStatus", title: powerSourceLine, detail: [thermalLine, power.reading.lowPowerMode ? TPow.text(.lowPowerMode) : nil].compactMap { $0 }.joined(separator: "\n"),
                     symbol: powerSymbol, kind: .info(power.adjustment.isNone ? TPow.text(.inForceNothing) : TPow.format(.inForce, powerProfileLine))),
        ]
        if power.canUndo {
            rows.append(PanelRow(id: "powerUndo", title: undoTitle, detail: TPow.text(.undoDetail), symbol: "arrow.uturn.backward", kind: .action(destructive: false) { [weak self] in
                self?.undoPowerAdjustment()
            }))
        }
        rows.append(PanelRow(id: "batterySection", title: TPow.text(.sectionBattery), kind: .info("")))
        rows += profileRows("battery", profiles.battery, title: .batteryProfile, detail: .batteryProfileDetail, symbol: "battery.75percent") { $0.battery = $1 }
        rows.append(PanelRow(id: "hotSection", title: TPow.text(.sectionHot), kind: .info("")))
        rows += profileRows("hot", profiles.hot, title: .hotProfile, detail: .hotProfileDetail, symbol: "thermometer.medium") { $0.hot = $1 }
        return rows
    }

    private var powerSymbol: String {
        let reading = power.reading
        if reading.thermal >= .serious { return "thermometer.sun.fill" }
        guard reading.hasBattery else { return "desktopcomputer" }
        guard reading.onBattery else { return "powerplug.fill" }
        switch reading.batteryPercent ?? 50 {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func profileRows(_ id: String, _ profile: PowerProfile, title: TPow.Key, detail: TPow.Key, symbol: String,
                             set: @escaping (inout PowerProfiles, PowerProfile) -> Void) -> [PanelRow] {
        func change(_ edit: @escaping (inout PowerProfile) -> Void) -> () -> Void {
            { [weak self] in
                self?.setPowerProfiles { profiles in
                    var changed = id == "hot" ? profiles.hot : profiles.battery
                    edit(&changed)
                    set(&profiles, changed)
                }
            }
        }
        var rows = [PanelRow(id: id + "On", title: TPow.text(title), detail: TPow.text(detail), symbol: symbol, kind: .toggle(profile.on) { value in change { $0.on = value }() })]
        guard profile.on else { return rows }
        let caps = PowerProfile.frameCaps
        rows += [
            PanelRow(id: id + "Cap", title: TPow.text(.frameCap), detail: TPow.text(.frameCapDetail), symbol: "speedometer",
                     kind: .choice(options: caps.map { $0 == 0 ? T.text(.off) : TPow.format(.fps, $0) }, selected: caps.firstIndex(of: profile.frameCap) ?? 0) { index in
                         change { $0.frameCap = caps[index] }()
                     }),
            PanelRow(id: id + "Resolution", title: TPow.text(.lowerResolution), detail: TPow.text(.lowerResolutionDetail), symbol: "rectangle.compress.vertical",
                     kind: .toggle(profile.lowerResolution) { value in change { $0.lowerResolution = value }() }),
            PanelRow(id: id + "FrameGeneration", title: TPow.text(.pauseFrameGeneration), detail: TPow.text(.pauseFrameGenerationDetail), symbol: "square.stack.3d.forward.dottedline",
                     kind: .toggle(profile.pauseFrameGeneration) { value in change { $0.pauseFrameGeneration = value }() }),
            PanelRow(id: id + "Effects", title: TPow.text(.dimEffects), detail: TPow.text(.dimEffectsDetail), symbol: "sparkles",
                     kind: .toggle(profile.dimEffects) { value in change { $0.dimEffects = value }() }),
        ]
        return rows
    }
}
