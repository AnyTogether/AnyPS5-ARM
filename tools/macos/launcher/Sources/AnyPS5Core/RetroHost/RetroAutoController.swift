import Foundation

/// The Auto Optimizer of a PS1 game while it plays with its internal resolution on Auto, as on
/// Windows and Linux (AnyPS5 Desktop's lib/ui/retro_host/retro_auto_controller.dart): every
/// `RetroAutoRules.window` it hands the game's last status to a `RetroAutoResolution` and asks the
/// host for the scale that one chooses, as the menu's Internal resolution row would. What it learns
/// of the game is read with `kept` and handed to `saved` after each change to it, under the game's
/// `titleID`.
@MainActor
public final class RetroAutoController {
    public let menu: RetroGameMenu
    /// The game's title ID, as its save states are kept under.
    public let titleID: String
    /// What was learned of the game before, from the launcher's preferences.
    private let kept: () -> RetroAutoMemory?
    /// Called with what is learned of the game whenever it changed, so it is kept.
    private let saved: (RetroAutoMemory) -> Void
    /// The largest scale worth choosing for the view the game is shown in now
    /// (`retroAutoDisplayNeed`), asked at every judgement, as the window may be resized or moved.
    private let need: () -> Int
    /// Where each change and its reason are written, for the launcher's log.
    private let log: ((String) -> Void)?
    /// How often the game's last status is judged.
    public let every: Duration
    /// The time since the optimizer started.
    private let clock: () -> Duration

    private var loop: Task<Void, Never>?
    private var change: Task<Void, Never>?
    private var stopped = false
    private var openingsSeen: Int

    /// The optimizer judging the game now, once a status allowed one.
    public private(set) var optimizer: RetroAutoResolution?

    public init(menu: RetroGameMenu, titleID: String, kept: @escaping () -> RetroAutoMemory?, saved: @escaping (RetroAutoMemory) -> Void,
                need: @escaping () -> Int, log: ((String) -> Void)? = nil, every: Duration = RetroAutoRules.window,
                clock: (() -> Duration)? = nil) {
        self.menu = menu
        self.titleID = titleID
        self.kept = kept
        self.saved = saved
        self.need = need
        self.log = log
        self.every = every
        if let clock {
            self.clock = clock
        } else {
            let start = ContinuousClock.now
            self.clock = { start.duration(to: .now) }
        }
        openingsSeen = menu.openings
    }

    /// Starts judging, from now, every `every`. The menu opening pauses the game, and breaks the run
    /// of readings, between judgements too.
    public func start() {
        guard !stopped, loop == nil else { return }
        let every = self.every
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: every)
                if Task.isCancelled { return }
                await self?.tick()
            }
        }
    }

    /// Judges the game's last status once: a change the optimizer chooses is asked of the host, and
    /// is the scale the game draws at once the host took it. While the menu is open the game is
    /// paused, and the readings before it do not count with those after it.
    public func tick() async {
        guard !stopped, change == nil, menu.game.reportsPerformance else { return }
        if menu.openings != openingsSeen {
            openingsSeen = menu.openings
            optimizer?.interrupted()
        }
        if menu.isOpen {
            optimizer?.interrupted()
            return
        }
        guard let status = menu.game.status, let choice = menu.resolution else { return }
        guard status.ready, status.performance != nil, status.gpu != nil else {
            optimizer?.interrupted()
            return
        }
        var scales: [Int: String] = [:]
        for value in choice.values {
            if let scale = value.scale { scales[scale] = value.value }
        }
        guard let current = choice.active.scale else { return }
        let auto = optimizerFor(status, scales: Array(scales.keys), current: current)
        auto.need = need()
        guard let change = auto.observe(at: clock(), status), let value = scales[change] else { return }
        let asked = Task { await self.apply(auto, status, current, change, value) }
        self.change = asked
        await asked.value
        self.change = nil
    }

    private func apply(_ auto: RetroAutoResolution, _ status: RetroStatus, _ current: Int, _ change: Int, _ value: String) async {
        guard await menu.chooseResolution(value), !stopped else { return }
        let reading = status.performance
        let speed = reading.map { "\($0.speed)" } ?? "null"
        let work = reading?.work.map { "\($0)" } ?? "null"
        log?("auto resolution: \(current)x to \(change)x for \(titleID) (speed \(speed), work \(work))")
        auto.changed(at: clock(), to: change)
        saved(auto.memory)
    }

    /// The optimizer for what the game is measured with now, from a status that measured it: the
    /// game shows its pictures, so the host has named the GPU that draws it, and a memory is never
    /// matched against a GPU not yet known. It is the one in use, or a new one when the game's GPU,
    /// host or other graphics settings are not those its memory was measured with, so what was
    /// learned with others is not used. The first judges from the game's start; one that replaces it
    /// settles from now, as after a change.
    private func optimizerFor(_ status: RetroStatus, scales: [Int], current: Int) -> RetroAutoResolution {
        let gpu = status.gpu?.renderer ?? ""
        let host = menu.game.hostVersion
        let config = retroAutoConfig(status, RetroGraphics.keys)
        let auto = optimizer
        if let auto, auto.memory.gpu == gpu, auto.memory.host == host, auto.memory.config == config { return auto }
        let before = kept()
        let slow = before.map { $0.measuredWith(gpu: gpu, host: host, config: config) ? $0.slow : [] } ?? []
        let memory = RetroAutoMemory(gpu: gpu, host: host, config: config, scale: current, slow: slow)
        saved(memory)
        let fresh = RetroAutoResolution(scales: scales, need: need(), memory: memory, scale: current)
        if auto != nil { fresh.changed(at: clock(), to: current) }
        optimizer = fresh
        return fresh
    }

    /// Stops judging, and waits for a change already asked of the host, so a value the player
    /// chooses next is chosen over the game's real scale and nothing the optimizer asked comes after
    /// it.
    public func stop() async {
        dispose()
        await change?.value
    }

    /// Stops judging; a change already asked is not counted when its reply comes.
    public func dispose() {
        stopped = true
        loop?.cancel()
        loop = nil
    }
}
