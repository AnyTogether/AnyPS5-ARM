import Foundation

/// The internal resolution a PS1 or PS2 game in the emulator host is drawn at, as the in-game menu
/// offers it, as on Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_resolution.dart):
/// the core option of each console, the scales the launcher offers, and what the host's `status`
/// says of them (anyps5-retro-host docs/protocol.md "status").
public enum RetroResolution {
    /// SwanStation's internal resolution, whose values are whole scales (`"1"` to `"16"`). Every
    /// host limits it to what it can pass on while it draws with the GPU (`status.hardware`).
    public static let ps1Key = "swanstation_GPU_ResolutionScale"
    /// LRPS2's internal resolution (`"1x (Native)"`, `"2x"`, `"4x"`, `"8x"`), applied only when the
    /// game starts. Only a host that lists `ps2ResolutionLimits` limits it.
    public static let ps2Key = "pcsx2_upscale_multiplier"

    /// The internal resolution's option key for a PS1 game, or with `ps2` for a PS2 game.
    public static func key(ps2: Bool = false) -> String { ps2 ? ps2Key : ps1Key }

    /// The values the launcher offers, by console, with the scale each one draws at: Native to 4x,
    /// and 6x and 8x for PS1 and 8x for PS2 for strong graphics cards. LRPS2 lists no 3x or 6x;
    /// SwanStation's 5x and 7x are left out, so each step is a clear one. 8x is for the player to
    /// choose: PS2 games at 8x ran at about half speed on a fast graphics card (anyps5-retro-host
    /// docs/ps2.md "Drawing"). The host may list fewer, and only those it lists are offered.
    static func offered(ps2: Bool) -> [String: Int] {
        ps2 ? ["1x (Native)": 1, "2x": 2, "4x": 4, "8x": 8] : ["1": 1, "2": 2, "3": 3, "4": 4, "6": 6, "8": 8]
    }
}

/// One value the row offers.
public struct RetroResolutionValue: Equatable, Sendable {
    /// The option's value, sent with `option`.
    public let value: String
    /// The scale it draws at, 1 for Native; nil for a value the launcher does not offer, which is
    /// shown only while the host has it chosen.
    public let scale: Int?
    /// The host's label of the value.
    public let label: String

    public init(value: String, scale: Int?, label: String) {
        self.value = value
        self.scale = scale
        self.label = label
    }
}

/// The internal resolution of a running game, as its menu offers it.
public struct RetroResolutionChoice: Equatable, Sendable {
    /// The option's key (`RetroResolution.key`).
    public let key: String
    /// The values offered, in the host's order.
    public let values: [RetroResolutionValue]
    /// The index into `values` of the value chosen.
    public let selected: Int
    /// The value the game draws at now (`activeValue`), which the refusal names.
    public let active: RetroResolutionValue
    public let note: RetroGraphicsNote

    /// The choice `status` allows, or nil when the menu offers none: no status yet, the host draws
    /// without the GPU (`hardware` false), the core lists no internal resolution, or it is a PS2
    /// game's and the host does not limit it (`limitsPs2` false, the host's
    /// `ps2ResolutionLimits`). The console is the status's own (`console`, which only a host with
    /// `ps2` sends).
    ///
    /// The values are those the launcher offers that the host lists, in the host's order, and the
    /// value chosen even when the launcher does not offer it, so the row always shows what the
    /// game has.
    public static func of(_ status: RetroStatus?, limitsPs2: Bool) -> RetroResolutionChoice? {
        guard let status, status.hardware else { return nil }
        let ps2 = status.console == RetroConsole.ps2
        if ps2, !limitsPs2 { return nil }
        guard let option = status.options[RetroResolution.key(ps2: ps2)] else { return nil }
        let offered = RetroResolution.offered(ps2: ps2)
        let chosen = option.values[option.selected]
        func value(at index: Int) -> RetroResolutionValue {
            RetroResolutionValue(value: option.values[index], scale: offered[option.values[index]], label: option.labels[index])
        }
        let values = option.values.indices.filter { offered[option.values[$0]] != nil || option.values[$0] == chosen }.map(value(at:))
        let active = option.values.firstIndex(of: option.activeValue).map(value(at:))
            ?? RetroResolutionValue(value: option.activeValue, scale: offered[option.activeValue], label: option.activeValue)
        return RetroResolutionChoice(key: option.key, values: values, selected: values.firstIndex { $0.value == chosen } ?? 0,
                                     active: active, note: note(status, option, chosen))
    }

    private static func note(_ status: RetroStatus, _ option: RetroOption, _ chosen: String) -> RetroGraphicsNote {
        if !status.resolutionError.isEmpty { return .refused }
        if option.restart { return chosen == option.activeValue ? .changesAtNextStart : .nextStart }
        if chosen != option.activeValue || status.graphicsPending { return .applying }
        return .none
    }
}
