import Foundation

/// Keeps macOS from putting the launcher to sleep (App Nap) while it sends a game to someone:
/// with the game's window over the launcher, a napping process gets its timers bunched up, and
/// the timers pacing WebRTC and the broadcast with them.
public final class Awake {
    public let options: ProcessInfo.ActivityOptions = [.userInitiated, .latencyCritical]
    private let reason: String
    private var token: NSObjectProtocol?

    public init(_ reason: String) { self.reason = reason }

    public var held: Bool { token != nil }

    public func hold() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
    }

    public func release() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }

    deinit { release() }
}
