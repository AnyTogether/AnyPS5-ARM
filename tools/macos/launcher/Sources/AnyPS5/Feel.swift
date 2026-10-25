import AnyPS5Core
import AppKit
import CoreHaptics
import GameController
import SwiftUI

/// The launcher's touch: the controller's soft pulses (HapticFeedback through the pad used last)
/// and the tick when the pointer arrives on something (HoverGate).
@MainActor
final class Feel {
    static let shared = Feel()

    let pad = PadHaptics()
    let haptics: HapticFeedback
    private var hover = HoverGate()

    private init() {
        haptics = HapticFeedback(output: pad)
        haptics.launcherInFront = NSApp?.isActive ?? true
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Behind a game (or any other app) the pad is the game's: the motors stop at once.
                MainActor.assumeIsolated { self?.haptics.launcherInFront = NSApp.isActive }
            }
        }
    }

    /// Settings → Behaviour → Controller Vibration.
    var vibration: Bool {
        get { haptics.enabled }
        set { haptics.enabled = newValue }
    }

    func usedPad(_ controller: GCController?) {
        haptics.padInUse = true
        if let controller { pad.use(controller) }
    }

    /// The keyboard or the mouse: the controller on the desk stays still.
    func usedKeyboard() { haptics.padInUse = false }

    /// The pulse an interface sound comes with, whether or not sounds are on.
    func sound(_ cue: Sounds.Cue) {
        if let haptic = HapticCue(sound: cue.rawValue) { haptics.play(haptic) }
    }

    func vibrate(_ cue: HapticCue) { haptics.play(cue) }

    /// The pointer arrived on a control, tile, row or card.
    func arrive(_ id: String) {
        let sounds = Sounds.shared
        let tick = hover.arrive(id, pointer: NSEvent.mouseLocation, now: ProcessInfo.processInfo.systemUptime, lastCue: sounds.lastCue,
                                buttonsDown: NSEvent.pressedMouseButtons != 0, allowed: sounds.enabled && NSApp.isActive)
        if tick { sounds.play(.hover) }
    }

    func leave(_ id: String) { hover.leave(id) }
}

extension View {
    /// The navigation tick when the pointer arrives on this element; `id` tells elements apart.
    func hoverTick(_ id: String) -> some View {
        onHover { inside in
            MainActor.assumeIsolated {
                if inside { Feel.shared.arrive(id) } else { Feel.shared.leave(id) }
            }
        }
    }
}

/// A controller's motors through Core Haptics (GCDeviceHaptics): DualSense, DualShock 4 and Xbox
/// controllers. Each pulse is a short continuous event, which rumble motors follow better than a
/// transient. A controller without haptics, or an engine that will not start, stays silent.
final class PadHaptics: HapticOutput {
    private weak var controller: GCController?
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    /// A controller the launcher reads itself (the DualShock 3): its motors set at each pulse.
    private var external: String?
    private var timers: [Timer] = []

    /// The controller used last is the one that answers.
    func use(_ controller: GCController) {
        guard controller !== self.controller || external != nil else { return }
        stop()
        engine?.stop()
        engine = nil
        external = nil
        self.controller = controller
    }

    func use(external id: String) {
        guard external != id else { return }
        stop()
        engine?.stop()
        engine = nil
        controller = nil
        external = id
    }

    func play(_ pulses: [HapticPulse]) {
        if let external {
            stop()
            for pulse in pulses {
                timers.append(Timer.scheduledTimer(withTimeInterval: pulse.start, repeats: false) { _ in
                    MainActor.assumeIsolated { Controllers.shared.externalRumble(external, strong: pulse.strong, weak: pulse.weak) }
                })
                timers.append(Timer.scheduledTimer(withTimeInterval: pulse.start + max(pulse.length, 0.05), repeats: false) { _ in
                    MainActor.assumeIsolated { Controllers.shared.externalRumble(external, strong: 0, weak: 0) }
                })
            }
            return
        }
        guard !pulses.isEmpty, let engine = startedEngine() else { return }
        let events = pulses.map { pulse in
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(pulse.intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(pulse.sharpness)),
            ], relativeTime: pulse.start, duration: pulse.length)
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try? player?.stop(atTime: CHHapticTimeImmediate)
            let next = try engine.makePlayer(with: pattern)
            try next.start(atTime: CHHapticTimeImmediate)
            player = next
        } catch {
            // Asked again next time from a new engine.
            self.engine = nil
            player = nil
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        timers.forEach { $0.invalidate() }
        timers = []
        if let external { MainActor.assumeIsolated { Controllers.shared.externalRumble(external, strong: 0, weak: 0) } }
    }

    private func startedEngine() -> CHHapticEngine? {
        if let engine { return engine }
        guard let haptics = controller?.haptics else { return nil }
        let locality: GCHapticsLocality = haptics.supportedLocalities.contains(.handles) ? .handles : .default
        guard let engine = haptics.createEngine(withLocality: locality) else { return nil }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { [weak self] _ in DispatchQueue.main.async { self?.engine = nil } }
        engine.resetHandler = { [weak self] in DispatchQueue.main.async { self?.engine = nil } }
        do { try engine.start() } catch { return nil }
        self.engine = engine
        return engine
    }
}
