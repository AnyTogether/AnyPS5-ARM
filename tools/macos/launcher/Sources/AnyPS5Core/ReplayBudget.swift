import Foundation

/// The replay buffer's lengths and what each costs. Everything stays in memory and is let go
/// unless Create saves it: up to a minute at the clip quality (0.15 bit a pixel at 60 fps), longer
/// ones at a bit rate that keeps the picture within `videoBudget`. Encoding runs on the Mac's
/// media engine, so the CPU cost is the capture's alone.
public enum ReplayBudget {
    /// Settings → Behaviour → Clip Length.
    public static let lengths = [30, 60, 180, 300]
    public static let defaultLength = 30
    public static let videoBudget = 256 * 1024 * 1024
    /// The sound as ScreenCaptureKit hands it over: 48 kHz stereo, 32-bit float.
    public static let audioBytesPerSecond = 48000 * 2 * 4

    /// A saved length from before the choices (15 to 120 in steps of 15) as the nearest choice.
    public static func length(_ saved: Int?) -> Int {
        guard let saved else { return defaultLength }
        return lengths.min { abs($0 - saved) < abs($1 - saved) } ?? defaultLength
    }

    /// The encoder's bit rate for a `width` x `height` picture kept `seconds` long.
    public static func bitRate(width: Int, height: Int, seconds: Int) -> Int {
        let quality = Int(Double(width) * Double(height) * 60 * 0.15)
        let fitting = Int(Double(videoBudget) * 8 / Double(max(1, seconds)))
        return max(1_000_000, min(quality, fitting))
    }

    /// The memory the buffer takes once full, picture and sound.
    public static func bytes(width: Int, height: Int, seconds: Int) -> Int {
        bitRate(width: width, height: height, seconds: seconds) / 8 * seconds + audioBytesPerSecond * seconds
    }

    /// The same in whole megabytes, for the setting's line.
    public static func megabytes(width: Int, height: Int, seconds: Int) -> Int {
        Int((Double(bytes(width: width, height: height, seconds: seconds)) / 1_048_576).rounded())
    }
}

/// Pausing the game before the launcher's quick menu covers it: one Options press sent through
/// the engine's remote pad (the phone's way in). The engine seats such a pad as the lowest free
/// player, so the press reaches the game's first player only while no controller or phone holds
/// that seat; otherwise it would sign in a second player, and nothing is sent.
public enum GamePause {
    public enum Route: Equatable, Sendable {
        case send
        case off
        /// A controller (or a phone as player 1) holds the first player.
        case playerOneTaken
        /// The game was started without the remote pad's channels, or none is free.
        case noChannel
    }

    public static func route(enabled: Bool, controllers: Int, phonePlayers: [Int], channelFree: Bool) -> Route {
        guard enabled else { return .off }
        guard controllers == 0, !phonePlayers.contains(1) else { return .playerOneTaken }
        return channelFree ? .send : .noChannel
    }

    /// When each packet of a press goes, in seconds from the first, and whether Options is down:
    /// held a little over 0.1 s, as a thumb holds it (a game samples its pad once a frame), then
    /// let go twice in case one is lost.
    public static let press: [(at: Double, down: Bool)] = [(0, true), (0.04, true), (0.08, true), (0.12, true), (0.16, false), (0.2, false)]

    /// The 80-byte packets of one press, in order.
    public static func packets(session: UInt64, firstSequence: UInt32, sentMicros: UInt64 = 0) -> [Data] {
        press.enumerated().map { index, step in
            var state = SharePadState()
            state.buttons = step.down ? SharePadState.Button.options : 0
            return state.packet(sequence: firstSequence &+ UInt32(index), sentMicros: sentMicros, session: session)
        }
    }
}

/// The launcher's window at start: full screen the first time, then as it was left.
public enum WindowStart {
    public static func fullScreen(saved: Bool?, steamFullScreen: Bool) -> Bool {
        steamFullScreen || (saved ?? true)
    }
}
