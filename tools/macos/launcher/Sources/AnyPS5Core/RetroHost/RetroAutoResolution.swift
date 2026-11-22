import Foundation

/// The thresholds the Auto Optimizer judges a PS1 game's internal resolution by, as on Windows and
/// Linux (AnyPS5 Desktop's lib/core/retro_host/retro_auto_resolution.dart): the highest scale the
/// game keeps full speed at on this Mac, judged from the host's `status.performance`
/// (anyps5-retro-host docs/protocol.md "status"). SwanStation applies its resolution while the game
/// runs, so a wrong scale is undone within seconds of play. A PS2 game is not chosen for: LRPS2
/// reads its resolution only when the game starts.
///
/// Measured on full-speed games, one 5-second window reads 0.994 to 1.004 (a frame either way), so
/// a step down needs two slow windows in a row or a slow half minute, never one window. A game also
/// slows for a moment for reasons no resolution changes (a new scene's shaders, a disc read): Spyro
/// the Dragon at 2x on an RTX 4080 SUPER read 0.983 then 0.836 once, with each frame taking 78% of
/// its time at the median. So a step down needs the slowness to be steady, or the frames themselves
/// to take longer than their time.
public enum RetroAutoRules {
    /// The time measured by each reading the optimizer takes, as the host measures it.
    public static let window: Duration = .seconds(5)
    /// How much sooner than `window` after the last reading the next may come: a timer's ticks can
    /// come a little sooner or later than its period, and a reading thrown away for being a few
    /// milliseconds early would drop about every other one. With the status itself up to a poll
    /// (half a second) old, two readings may share up to about a second of the host's measurement;
    /// the rules judge several readings, never one.
    public static let early: Duration = .milliseconds(500)
    /// The time after the game starts or its resolution changes before readings count: loading,
    /// shader compiles and the redraw at the new scale.
    public static let settle: Duration = .seconds(20)
    /// Two readings in a row below this, each with a frame taking at least `slowWork` of its time at
    /// the median, step down at once: the PC cannot keep up with the game at this scale.
    public static let slow = 0.95
    public static let slowWork = 1.0
    /// Six readings (30 seconds) in a row, each below this, step down: a small but steady loss, as
    /// Jak and Daxter at a scale just too high read 0.956 to 0.990 in every window. One slow moment
    /// among full-speed readings is not steady.
    public static let steady = 0.995
    public static let steadyReadings = 6
    /// Twelve readings (a minute) at full speed, each with a frame taking at most half its time,
    /// step up one scale.
    public static let headroomReadings = 12
    public static let headroomWork = 0.5
    /// The scale a game starts at when nothing is remembered for it: low enough to start quickly on
    /// most graphics cards, and the optimizer climbs from there.
    public static let firstScale = 2
}

/// What the optimizer remembers of one game on this Mac: the scale it last used, and the scales
/// that ran slow, which it never chooses again. It is measured with one GPU, host build and set of
/// the game's other graphics settings; when any of them changes, it starts again. Kept in the
/// preferences with the same fields as on Windows and Linux.
public struct RetroAutoMemory: Codable, Equatable, Sendable {
    /// The renderer that drew the game (`status.gpu.renderer`), or empty before one was seen.
    public var gpu: String
    /// The host's version (`welcome.hostVersion`), which names the core build it ships.
    public var host: String
    /// The game's other graphics settings it was measured with (`retroAutoConfig`), or empty before
    /// a status was seen.
    public var config: String
    /// The scale last used, or nil before any.
    public var scale: Int?
    /// The scales that ran slow.
    public var slow: Set<Int>

    public init(gpu: String, host: String, config: String, scale: Int? = nil, slow: Set<Int> = []) {
        self.gpu = gpu
        self.host = host
        self.config = config
        self.scale = scale
        self.slow = slow
    }

    /// Whether this memory was measured with `gpu`, `host` and `config`. An empty `gpu` or `config`
    /// of this memory or of the question matches any, since it was not known.
    public func measuredWith(gpu: String, host: String, config: String) -> Bool {
        self.host == host && (self.gpu.isEmpty || gpu.isEmpty || self.gpu == gpu)
            && (self.config.isEmpty || config.isEmpty || self.config == config)
    }

    private enum CodingKeys: String, CodingKey { case gpu, host, config, scale, slow }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        gpu = try fields.decode(String.self, forKey: .gpu)
        host = try fields.decode(String.self, forKey: .host)
        config = try fields.decode(String.self, forKey: .config)
        scale = try fields.decodeIfPresent(Int.self, forKey: .scale)
        slow = Set(try fields.decodeIfPresent([Int].self, forKey: .slow) ?? [])
    }

    /// The scale only once one was used, and the slow scales in order only when there are any.
    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(gpu, forKey: .gpu)
        try fields.encode(host, forKey: .host)
        try fields.encode(config, forKey: .config)
        try fields.encodeIfPresent(scale, forKey: .scale)
        if !slow.isEmpty { try fields.encode(slow.sorted(), forKey: .slow) }
    }
}

/// What the optimizer learned of each game, by the game's title ID, as the preferences keep it. An
/// entry that is not a memory is left out when read, so it never makes the preferences unreadable.
public struct RetroAutoMemories: Codable, Equatable, Sendable {
    public var games: [String: RetroAutoMemory]

    public init(_ games: [String: RetroAutoMemory] = [:]) { self.games = games }

    public subscript(titleID: String) -> RetroAutoMemory? {
        get { games[titleID] }
        set { games[titleID] = newValue }
    }

    private struct Entry: Decodable {
        let memory: RetroAutoMemory?
        init(from decoder: Decoder) throws { memory = try? RetroAutoMemory(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let entries = (try? decoder.singleValueContainer().decode([String: Entry].self)) ?? [:]
        games = entries.compactMapValues(\.memory)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(games)
    }
}

/// The game's graphics settings other than the resolution that change what a frame costs, as
/// `status` has them chosen: the values of `keys` the host lists, in key order. Empty before a
/// status lists any.
public func retroAutoConfig(_ status: RetroStatus, _ keys: some Sequence<String>) -> String {
    keys.sorted().compactMap { key in status.options[key].map { "\(key)=\($0.values[$0.selected])" } }.joined(separator: ";")
}

/// The largest scale the view needs: a PS1 game is 240 lines high, so a scale past the view's
/// height in pixels over 240 draws pixels it cannot show.
public func retroAutoDisplayNeed(_ displayHeight: Double) -> Int {
    displayHeight <= 0 ? 1 : Int((displayHeight / 240).rounded(.up))
}

/// The optimizer of one game while it plays.
public final class RetroAutoResolution {
    /// The scales the host lists and the launcher offers, smallest first.
    public let scales: [Int]
    /// The largest scale worth choosing (`retroAutoDisplayNeed`); it follows the view.
    public var need: Int
    public private(set) var memory: RetroAutoMemory
    /// The scale the game draws at now; `changed(at:to:)` sets it.
    public private(set) var scale: Int
    /// The game runs slow at the smallest scale: no resolution helps it, so the optimizer stops.
    public private(set) var atFloor = false

    private var readings: [RetroPerformance] = []
    private var settledAt = RetroAutoRules.settle
    private var lastReading: Duration?

    public init(scales: [Int], need: Int, memory: RetroAutoMemory, scale: Int) {
        self.scales = Set(scales).sorted()
        self.need = need
        self.memory = memory
        self.scale = scale
    }

    /// The scale a game starts at: the one `memory` last used, or `RetroAutoRules.firstScale`, at
    /// most `need`, never one that ran slow, and one of `scales` (the smallest when none fits).
    public static func startScale(_ scales: [Int], need: Int, memory: RetroAutoMemory? = nil) -> Int {
        let listed = Set(scales).sorted()
        guard let smallest = listed.first else { return 1 }
        let wanted = memory?.scale ?? RetroAutoRules.firstScale
        let allowed = listed.filter { $0 <= wanted && $0 <= need && !(memory?.slow.contains($0) ?? false) }
        return allowed.last ?? smallest
    }

    /// Takes `status` at `at` (the time since the game started) and returns the scale to change to,
    /// or nil to keep this one. A reading counts only while the game plays and nothing is being
    /// applied, `RetroAutoRules.settle` after the start or the last change, and about once per
    /// `RetroAutoRules.window` (no sooner than `RetroAutoRules.early` before it); anything else
    /// breaks the run of readings.
    public func observe(at: Duration, _ status: RetroStatus) -> Int? {
        if atFloor { return nil }
        guard let performance = status.performance, status.ready, !status.ended, !status.graphicsPending,
              status.progressLabel == nil, at >= settledAt else {
            if status.performance == nil || status.graphicsPending || status.progressLabel != nil { readings = [] }
            return nil
        }
        if let lastReading, at - lastReading < RetroAutoRules.window - RetroAutoRules.early { return nil }
        lastReading = at
        readings.append(performance)
        if slow() { return down() }
        if headroom() { return up() }
        return nil
    }

    /// The game was paused (the menu opened) or was otherwise not played: the readings before do not
    /// count with those after.
    public func interrupted() {
        readings = []
        lastReading = nil
    }

    /// The game now draws at `now` (the change asked was taken, or the player's), from `at`: the
    /// readings start again after `RetroAutoRules.settle`.
    public func changed(at: Duration, to now: Int) {
        scale = now
        memory.scale = now
        readings = []
        lastReading = nil
        settledAt = at + RetroAutoRules.settle
    }

    private func slow() -> Bool {
        func overloaded(_ reading: RetroPerformance) -> Bool {
            reading.speed < RetroAutoRules.slow && (reading.work ?? 0) >= RetroAutoRules.slowWork
        }
        let count = readings.count
        if count >= 2, overloaded(readings[count - 1]), overloaded(readings[count - 2]) { return true }
        guard count >= RetroAutoRules.steadyReadings else { return false }
        return readings.suffix(RetroAutoRules.steadyReadings).allSatisfy { $0.speed < RetroAutoRules.steady }
    }

    private func headroom() -> Bool {
        guard readings.count >= RetroAutoRules.headroomReadings else { return false }
        return readings.suffix(RetroAutoRules.headroomReadings).allSatisfy { reading in
            guard let work = reading.work else { return false }
            return reading.speed >= RetroAutoRules.steady && work <= RetroAutoRules.headroomWork
        }
    }

    private func down() -> Int? {
        readings = []
        guard let lower = scales.last(where: { $0 < scale && !memory.slow.contains($0) }) else {
            atFloor = true
            return nil
        }
        memory.slow.insert(scale)
        return lower
    }

    private func up() -> Int? {
        readings = []
        guard let next = scales.first(where: { $0 > scale }), next <= need, !memory.slow.contains(next) else { return nil }
        return next
    }
}
