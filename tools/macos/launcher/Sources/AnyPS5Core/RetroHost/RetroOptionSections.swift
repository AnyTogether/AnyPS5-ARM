import Foundation

/// Where a SwanStation option is shown, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_option_sections.dart). The host lists every option SwanStation lets the
/// player change now (about fifty for a PS1 game, in SwanStation's order); the launcher groups them.
public enum RetroOptionSection: String, CaseIterable, Sendable {
    /// The picture: SwanStation's `GPU`, `Display` and `TextureReplacements` options, and LRPS2's
    /// resolution scale. The in-game menu does not show them: they are left for a Graphics page of
    /// their own.
    case graphics
    /// The sound: SwanStation's `Audio` options and Mute CD Audio. The menu adds the host's volume.
    case audio
    /// The controllers: SwanStation's `Controller`, `Controller1`, `Controller2`, … and
    /// `ControllerPorts` options.
    case controller
    /// The console: its region and BIOS (`Console`, `BIOS`), the CD-ROM's region check and speed,
    /// and the CPU's clock.
    case console
    /// Everything else: how SwanStation runs the CPU and reads the disc, its compatibility settings
    /// and hacks, and any option a later SwanStation adds.
    case advanced

    /// Options players have no use for in the launcher, which are not shown and whose kept values
    /// are not sent: the on-screen messages (the host draws none), the four display offsets
    /// (sixty-one steps of SwanStation's own calibration each), the development console's 8 MB of
    /// RAM, the CPU recompiler's debugging switches, and the light gun crosshair (the host plugs in
    /// only DualShocks). Texture replacements are left out too (the host gives SwanStation no
    /// texture folder).
    static let hidden: Set<String> = [
        "Display_ShowOSDMessages", "Display_ActiveStartOffset", "Display_ActiveEndOffset", "Display_LineStartOffset",
        "Display_LineEndOffset", "Console_Enable8MBRAM", "CPU_RecompilerICache", "CPU_RecompilerBlockLinking", "CPU_FastmemMode",
        "Controller_ShowCrosshair",
    ]

    static let consoleOptions: Set<String> = ["CDROM_RegionCheck", "CDROM_ReadSpeedup", "CDROM_SeekSpeedup", "CPU_Overclock"]

    /// The section a SwanStation option key is shown in, or nil for an option that is not shown.
    /// Keys are `swanstation_<Group>_<Name>`; a key of another form is `advanced`, as every LRPS2
    /// option of a PS2 game is (`pcsx2_...`), but its resolution scale, which is `graphics`.
    public static func of(_ key: String) -> RetroOptionSection? {
        let prefix = "swanstation_"
        if key == RetroResolution.ps2Key { return .graphics }
        // LRPS2's VR (pcsx2_vr_mode and its pcsx2_vr_depth): a picture for each eye side by side
        // for a VR headset or a 3D display, which AnyPS5 has none of.
        if key.hasPrefix("pcsx2_vr_") { return nil }
        guard key.hasPrefix(prefix) else { return .advanced }
        let name = String(key.dropFirst(prefix.count))
        if hidden.contains(name) || name.hasPrefix("TextureReplacements_") { return nil }
        if consoleOptions.contains(name) { return .console }
        if name == "CDROM_MuteCDAudio" { return .audio }
        let group = name.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? name
        if group == "GPU" || group == "Display" { return .graphics }
        if group == "Audio" { return .audio }
        if group.hasPrefix("Controller") { return .controller }
        if group == "Console" || group == "BIOS" { return .console }
        return .advanced
    }

    /// Whether the option at `key` is shown somewhere.
    public static func shown(_ key: String) -> Bool { of(key) != nil }

    /// Whether a value kept for `key` goes to a game's `start`: one the in-game menu shows. A
    /// graphics option is kept back too, since the launcher has no page yet where the player could
    /// see or change it. The two cores' options share one list of values the player chose, so
    /// LRPS2's (`pcsx2_...`) go to a `ps2` game only and every other to a PS1 game only.
    public static func sent(_ key: String, ps2: Bool = false) -> Bool {
        guard key.hasPrefix("pcsx2_") == ps2 else { return false }
        // The console's internal resolution, which the menu's first page offers. A PS2 one still
        // goes only to a host that limits it (RetroHostGame.start).
        if key == RetroResolution.key(ps2: ps2) { return true }
        guard let section = of(key) else { return false }
        return section != .graphics
    }

    /// An option's title without SwanStation's own " (Restart)": the menu says that under every
    /// option that takes effect only when the game starts again.
    public static func title(_ title: String) -> String {
        let mark = "(Restart)"
        let trimmed = title.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        guard trimmed.hasSuffix(mark) else { return title }
        let rest = String(trimmed.dropLast(mark.count)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return rest.isEmpty ? title : rest
    }
}
