import Foundation

/// Who helps the first player (assist, as PS5's second controller for assistance or Xbox
/// Copilot): no one, the Mac's controllers after the first player's, or one phone or browser pad.
/// A helper's buttons and sticks join the first player's, and it takes no player of its own.
/// Share play guests are set one by one (SharePadRouter.assist).
public enum AssistTarget: Equatable, Sendable {
    case off
    case controllers
    /// A phone or browser pad, by its device ID.
    case device(String)

    static let controllersValue = "controllers"

    /// The target kept in the launcher's settings: nil off, "controllers", or a device ID.
    public init(stored: String?) {
        switch stored {
        case nil, "": self = .off
        case AssistTarget.controllersValue?: self = .controllers
        case let id?: self = .device(id)
        }
    }

    public var stored: String? {
        switch self {
        case .off: return nil
        case .controllers: return AssistTarget.controllersValue
        case .device(let id): return id
        }
    }

    /// The phones and browser pads that help, for the phone server.
    public var devices: Set<String> {
        if case .device(let id) = self { return [id] }
        return []
    }

    /// Whether the Mac's other controllers help (the engine's assist datagram).
    public var controllers: Bool { self == .controllers }

    /// The choices a settings row offers, in order: off, the other controllers, then each device
    /// (connected ones, and the chosen one when it is not), by ID and name.
    public static func choices(devices: [(id: String, name: String)], chosen: AssistTarget, names: [String: String]) -> [(target: AssistTarget, name: String?)] {
        var list: [(AssistTarget, String?)] = [(.off, nil), (.controllers, nil)]
        var seen = Set<String>()
        for device in devices where seen.insert(device.id).inserted { list.append((.device(device.id), device.name)) }
        if case .device(let id) = chosen, !seen.contains(id) { list.append((.device(id), names[id] ?? id)) }
        return list
    }
}
