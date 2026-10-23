import AnyPS5Core
import AVFoundation

/// The selected game's theme song, the way the PS5 plays it: it comes in softly once the
/// selection has rested on a game for a moment, repeats, and fades out when the selection moves,
/// a game starts or the launcher goes to the background.
@MainActor
final class ThemeMusic {
    static let shared = ThemeMusic()

    static let settle: Duration = .milliseconds(900)
    static let fadeIn = 1.4
    static let fadeOut = 0.45

    /// 0 to 1.
    var volume: Float = 0.5 {
        didSet { if fade == nil, current != nil { player.volume = volume } }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var current: String?
    private var wanted: String?
    private var pending: Task<Void, Never>?
    private var fade: Timer?
    private var cache: [String: ThemeSong.Buffers] = [:]
    private var cacheOrder: [String] = []

    private init() {
        engine.attach(player)
    }

    /// The song of `game`, or silence for nil; asking again for the song playing changes nothing.
    func play(_ game: Game?) {
        let id = game?.music != nil ? game?.id : nil
        guard id != wanted else { return }
        wanted = id
        pending?.cancel()
        stop()
        guard let game, let music = game.music, volume > 0 else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: ThemeMusic.settle)
            guard let self, !Task.isCancelled, self.wanted == game.id else { return }
            let buffers: ThemeSong.Buffers
            if let cached = self.cache[game.id] {
                buffers = cached
            } else {
                guard let song = await Task.detached(priority: .userInitiated, operation: { try? ThemeSong.decode(music) }).value,
                      let made = song.buffers() else { return }
                buffers = made
                self.remember(game.id, made)
            }
            guard !Task.isCancelled, self.wanted == game.id else { return }
            self.start(game.id, buffers)
        }
    }

    private func start(_ id: String, _ buffers: ThemeSong.Buffers) {
        let songFormat = buffers.intro.format
        if format != songFormat {
            engine.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: songFormat)
            format = songFormat
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.stop()
        if let loop = buffers.loop {
            player.scheduleBuffer(buffers.intro)
            player.scheduleBuffer(loop, at: nil, options: .loops)
        } else {
            player.scheduleBuffer(buffers.intro, at: nil, options: .loops)
        }
        current = id
        player.volume = 0
        player.play()
        ramp(to: volume, over: ThemeMusic.fadeIn)
    }

    private func stop() {
        guard current != nil else { return }
        current = nil
        ramp(to: 0, over: ThemeMusic.fadeOut) { [weak self] in
            guard let self, self.current == nil else { return }
            self.player.stop()
        }
    }

    private func ramp(to target: Float, over seconds: Double, then done: (() -> Void)? = nil) {
        fade?.invalidate()
        let from = player.volume
        let began = Date()
        fade = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let t = min(1, Date().timeIntervalSince(began) / seconds)
                let eased = Float(t * t * (3 - 2 * t))
                self.player.volume = from + (target - from) * eased
                if t >= 1 {
                    timer.invalidate()
                    self.fade = nil
                    done?()
                }
            }
        }
    }

    private func remember(_ id: String, _ buffers: ThemeSong.Buffers) {
        cache[id] = buffers
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        // A song is about 30 MB as floats: a few are kept for going back and forth.
        while cacheOrder.count > 3 { cache[cacheOrder.removeFirst()] = nil }
    }
}
