import Foundation

/// Where a SwanStation option is shown, as on Windows and Linux (AnyPS5 Desktop's
/// lib/ui/retro_host/retro_option_sections.dart). The host lists every option SwanStation lets the
/// player change now (about fifty for a PS1 game, in SwanStation's order); the launcher groups them.
public enum RetroOptionSection: String, CaseIterable, Sendable {
    /// The picture: SwanStation's `GPU` and `Display` options, and LRPS2's resolution scale,
    /// anisotropic filtering and widescreen patch. The menu's Graphics page does not list them one
    /// by one: it offers the internal resolution (`RetroResolution.key`) and a few settings that
    /// set them (`RetroGraphics.settings`). The others are kept at the core's defaults.
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
    /// texture folder). So are SwanStation's MSAA, which does not work on the host (its shader
    /// needs OpenGL 4.0 and the host makes the 3.3 context SwanStation asks for, so the core falls
    /// back to software and the game never starts), and its accuracy and compatibility settings:
    /// the PGXP options but PGXP itself, the downsampling, the read-back renderer, the NTSC
    /// timings, interlacing, the display crop, 4:3 for 24-bit display, and `Main_ApplyGameSettings`,
    /// which stays on so SwanStation's per-game list still turns enhancements off for the games
    /// they break.
    static let hidden: Set<String> = [
        "GPU_MSAA", "GPU_PGXPColorCorrection", "GPU_PGXPDepthBuffer", "GPU_PGXPPreserveProjFP", "GPU_PGXPVertexCache",
        "GPU_PGXPTolerance", "GPU_PGXPDepthClearThreshold", "GPU_PGXPCPU", "GPU_DownsampleMode", "GPU_UseSoftwareRendererForReadbacks",
        "GPU_ForceNTSCTimings", "GPU_DisableInterlacing", "Display_CropMode", "Display_Force4_3For24Bit", "Main_ApplyGameSettings",
        "Display_ShowOSDMessages", "Display_ActiveStartOffset", "Display_ActiveEndOffset", "Display_LineStartOffset",
        "Display_LineEndOffset", "Console_Enable8MBRAM", "CPU_RecompilerICache", "CPU_RecompilerBlockLinking", "CPU_FastmemMode",
        "Controller_ShowCrosshair",
    ]

    /// LRPS2's options that are not shown and whose kept values are not sent, besides its VR and
    /// paraLLEl-GS ones: its other video options, its software renderer's threads, its EE and VU
    /// options, its game patch hints but the widescreen patch, and its manual hardware fixes ("HW
    /// Hacks", which LRPS2 itself calls not recommended), as LRPS2 c0d39a5's
    /// `libretro/libretro_core_options.h` lists them. They stay at LRPS2's defaults, which defer
    /// to its game database.
    static let ps2Hidden: Set<String> = [
        "pcsx2_renderer", "pcsx2_native_scaling", "pcsx2_deinterlace_mode", "pcsx2_nointerlacing_hint", "pcsx2_disable_interlace_offset",
        "pcsx2_hw_download_mode", "pcsx2_texture_filtering", "pcsx2_trilinear_filtering", "pcsx2_dithering", "pcsx2_blending_accuracy",
        "pcsx2_pcrtc_antiblur", "pcsx2_pcrtc_screen_offsets", "pcsx2_sw_renderer_threads", "pcsx2_disable_shader_cache",
        "pcsx2_vu_accurate_addsub", "pcsx2_vu_exact_mul", "pcsx2_vu_exact_div", "pcsx2_vu0_softfloat", "pcsx2_vu1_softfloat", "pcsx2_mtvu",
        "pcsx2_instant_vu1", "pcsx2_ee_accurate_fpu", "pcsx2_fpu_softfloat", "pcsx2_ee_cycle_rate", "pcsx2_ee_cpu", "pcsx2_ee_cycle_skip",
        "pcsx2_fastmem", "pcsx2_game_enhancements_hint", "pcsx2_uncapped_framerate_hint", "pcsx2_enable_hw_hacks", "pcsx2_cpu_sprite_size",
        "pcsx2_cpu_sprite_level", "pcsx2_software_clut_render", "pcsx2_texture_inside_rt", "pcsx2_disable_depth_conversion",
        "pcsx2_framebuffer_conversion", "pcsx2_disable_partial_invalidation", "pcsx2_gpu_palette_conversion", "pcsx2_preload_frame_data",
        "pcsx2_half_pixel_offset", "pcsx2_round_sprite", "pcsx2_align_sprite", "pcsx2_merge_sprite", "pcsx2_unscaled_palette_draw",
        "pcsx2_force_sprite_position",
    ]

    static let consoleOptions: Set<String> = ["CDROM_RegionCheck", "CDROM_ReadSpeedup", "CDROM_SeekSpeedup", "CPU_Overclock"]

    /// The section a SwanStation option key is shown in, or nil for an option that is not shown.
    /// Keys are `swanstation_<Group>_<Name>`; a key of another form is `advanced`, as every other
    /// LRPS2 option of a PS2 game is (`pcsx2_...`: its BIOS, fast boot, disc speed and the
    /// controllers), but those a Graphics row sets, which are `graphics`.
    public static func of(_ key: String) -> RetroOptionSection? {
        let prefix = "swanstation_"
        if key == RetroResolution.ps2Key || RetroGraphics.keys.contains(key) { return .graphics }
        // LRPS2's VR (pcsx2_vr_mode and its pcsx2_vr_depth): a picture for each eye side by side
        // for a VR headset or a 3D display, which AnyPS5 has none of. LRPS2's paraLLEl-GS options
        // (pcsx2_pgs_...), for a renderer the host never uses: it draws LRPS2 with GSdx on OpenGL
        // and makes no Vulkan context.
        if key.hasPrefix("pcsx2_vr_") || key.hasPrefix("pcsx2_pgs_") || ps2Hidden.contains(key) { return nil }
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
    /// graphics option is kept back, since the player cannot see or change it, but for the
    /// console's internal resolution and the options the Graphics rows set (`RetroGraphics.keys`).
    /// A value kept for an option that is not shown is not sent either, also one an older launcher
    /// kept while it showed the option (LRPS2's stereo, a hardware fix). The two cores' options
    /// share one list of values the player chose, so LRPS2's (`pcsx2_...`) go to a `ps2` game only
    /// and every other to a PS1 game only.
    public static func sent(_ key: String, ps2: Bool = false) -> Bool {
        guard key.hasPrefix("pcsx2_") == ps2 else { return false }
        // A PS2 internal resolution still goes only to a host that limits it (RetroHostGame.start).
        if key == RetroResolution.key(ps2: ps2) || RetroGraphics.keys.contains(key) { return true }
        guard let section = of(key) else { return false }
        return section != .graphics
    }

    /// The core options a game of `ps2`'s console starts with: the values the player kept for
    /// every game (`kept`) and for this game (`game`) that are sent (`sent`), over the Graphics
    /// defaults for the settings the player did not choose (`RetroGraphics.defaults`). An option
    /// kept per game (`RetroGraphics.perGameKeys`) comes from `game` only, so a value kept for
    /// every game (by an older launcher) is not sent.
    public static func startOptions(kept: [String: String], ps2: Bool, game: [String: String] = [:]) -> [String: String] {
        var chosen = kept.filter { !RetroGraphics.perGameKeys.contains($0.key) && sent($0.key, ps2: ps2) }
        for (key, value) in game where RetroGraphics.perGameKeys.contains(key) && sent(key, ps2: ps2) { chosen[key] = value }
        return RetroGraphics.defaults(kept: chosen, ps2: ps2).merging(chosen) { _, player in player }
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
