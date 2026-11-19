import Foundation

/// A controller taking or leaving one of the console's ports.
public struct RetroSeatChange: Equatable, Sendable {
    public let port: Int
    public let pad: String
    /// True when `pad` sat down at `port`, false when it left it.
    public let joined: Bool

    public init(_ port: Int, _ pad: String, joined: Bool) {
        self.port = port
        self.pad = pad
        self.joined = joined
    }
}

/// Which launcher controller sits at each of the PS1's two controller ports (anyps5-retro-host
/// docs/protocol.md "input": `port` 0 or 1), as on Windows and Linux (AnyPS5 Desktop's
/// lib/core/retro_host/retro_seats.dart).
///
/// A controller keeps its port while it stays connected, so a press on another pad never swaps
/// the players. A controller that leaves frees its port and the other one stays where it is. A free
/// port goes to the first waiting controller in the order given, which puts Player 1 (the one used
/// last before the game) at port 1 when the game starts.
public struct RetroSeats: Sendable {
    public static let portCount = 2

    private var ports: [String?] = Array(repeating: nil, count: RetroSeats.portCount)

    public init() {}

    /// The controller at `port`, or nil.
    public func at(_ port: Int) -> String? { ports[port] }

    /// The port `pad` sits at, or nil.
    public func portOf(_ pad: String) -> Int? { ports.firstIndex(of: pad) }

    /// The `connectedPorts` argument: how many ports, counting from port 1, have a controller in.
    /// Port 1 always counts, because the host keeps a controller there for every game.
    public var connectedPorts: Int { ports[1] != nil ? 2 : 1 }

    /// Seats the controllers connected now, `present` in the launcher's order (Player 1 first), and
    /// gives what changed: the controllers that left first, then those that sat down.
    public mutating func sync(_ present: [String]) -> [RetroSeatChange] {
        var changes: [RetroSeatChange] = []
        let here = Set(present)
        for port in 0..<Self.portCount {
            if let pad = ports[port], !here.contains(pad) {
                ports[port] = nil
                changes.append(RetroSeatChange(port, pad, joined: false))
            }
        }
        for pad in present where !ports.contains(pad) {
            guard let free = ports.firstIndex(where: { $0 == nil }) else { break }
            ports[free] = pad
            changes.append(RetroSeatChange(free, pad, joined: true))
        }
        return changes
    }
}
