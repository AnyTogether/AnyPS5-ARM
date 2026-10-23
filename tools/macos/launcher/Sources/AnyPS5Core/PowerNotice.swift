import Foundation

/// Low Power Mode holds a faster display (ProMotion) at 60 Hz: games stop at 60 fps and frame
/// generation, which needs twice the game's rate, turns itself off. Which of those to tell.
public enum PowerNotice: Equatable, Sendable {
    /// The game's frame generation cannot work.
    case frameGeneration
    /// The game stops at 60 fps.
    case refresh

    public static func kind(lowPower: Bool, displayMaximumFPS: Int, frameGeneration: Bool) -> PowerNotice? {
        guard lowPower, displayMaximumFPS > 60 else { return nil }
        return frameGeneration ? .frameGeneration : .refresh
    }
}
