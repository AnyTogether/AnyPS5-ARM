import XCTest
@testable import AnyPS5Core

/// Where the in-game menu shows SwanStation's options, as on Windows and Linux (AnyPS5 Desktop's
/// test/ui/retro_host/retro_option_sections_test.dart), against the status of the real host
/// recorded in Fixtures/retro-host-swanstation-status.json (the same file as Desktop's
/// test/fixtures).
final class RetroOptionSectionsTests: XCTestCase {
    static func recordedStatus() throws -> RetroStatus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/retro-host-swanstation-status.json").standardized
        let file = try RetroJSON.parse(Array(try Data(contentsOf: url)))
        return try RetroStatus.parse(try XCTUnwrap(file.objectValue?["status"]))
    }

    func testTheFiftyOptionsOfTheRealHostFallIntoTheirSectionsInTheHostsOrderEighteenNotShown() throws {
        let keys = try Self.recordedStatus().orderedOptionKeys
        XCTAssertEqual(keys.count, 50)
        func inSection(_ section: RetroOptionSection?) -> [String] {
            keys.filter { RetroOptionSection.of($0) == section }.map { String($0.dropFirst("swanstation_".count)) }
        }
        XCTAssertEqual(inSection(.audio), ["CDROM_MuteCDAudio", "Audio_FastHook"])
        XCTAssertEqual(inSection(.controller), ["Controller_AnalogCombo", "Controller_EnableRumble", "Controller1_ForceAnalog",
                                                "Controller1_AnalogDPadInDigitalMode", "Controller1_AxisScale", "Controller1_VibrationBias"])
        XCTAssertEqual(inSection(.console), ["Console_Region", "BIOS_PathNTSCU", "BIOS_PatchFastBoot", "CDROM_RegionCheck",
                                             "CDROM_ReadSpeedup", "CDROM_SeekSpeedup", "CPU_Overclock"])
        XCTAssertEqual(inSection(.advanced), ["CDROM_ReadThread", "CDROM_LoadImagePatches", "CDROM_LoadImageToRAM", "CDROM_PreCacheCHD",
                                              "CPU_ExecutionMode", "CDROM_ReadaheadSectors", "Main_RunaheadFrameCount", "Hacks_OldMDECRoutines"])
        XCTAssertEqual(inSection(.graphics), ["GPU_ResolutionScale", "GPU_TrueColor", "GPU_ScaledDithering", "GPU_ChromaSmoothing24Bit",
                                              "GPU_TextureFilter", "GPU_WidescreenHack", "GPU_PGXPEnable", "Display_AspectRatio",
                                              "GPU_ShaderPrecompile"])
        XCTAssertEqual(inSection(nil), ["GPU_UseSoftwareRendererForReadbacks", "GPU_MSAA", "GPU_DisableInterlacing", "GPU_ForceNTSCTimings",
                                        "Display_Force4_3For24Bit", "Display_CropMode", "GPU_DownsampleMode", "Display_ShowOSDMessages",
                                        "Display_ActiveStartOffset", "Display_ActiveEndOffset", "Display_LineStartOffset", "Display_LineEndOffset",
                                        "Main_ApplyGameSettings", "CPU_RecompilerICache", "CPU_RecompilerBlockLinking", "CPU_FastmemMode",
                                        "TextureReplacements_EnableVRAMWriteReplacements", "Console_Enable8MBRAM"])
    }

    func testOptionsTheRecordingDoesNotHaveGoByTheirGroupAndUnknownOnesToAdvanced() {
        XCTAssertEqual(RetroOptionSection.of("swanstation_Controller2_ForceAnalog"), .controller)
        XCTAssertEqual(RetroOptionSection.of("swanstation_ControllerPorts_MultitapMode"), .controller)
        XCTAssertEqual(RetroOptionSection.of("swanstation_BIOS_PathPAL"), .console)
        XCTAssertEqual(RetroOptionSection.of("swanstation_GPU_PGXPCulling"), .graphics)
        for key in ["swanstation_GPU_PGXPVertexCache", "swanstation_GPU_PGXPCPU", "swanstation_GPU_MSAA"] {
            XCTAssertNil(RetroOptionSection.of(key), key)
            XCTAssertFalse(RetroOptionSection.sent(key), key)
        }
        XCTAssertEqual(RetroOptionSection.of("swanstation_Audio_Something"), .audio)
        XCTAssertNil(RetroOptionSection.of("swanstation_Controller_ShowCrosshair"))
        XCTAssertNil(RetroOptionSection.of("swanstation_TextureReplacements_Other"))
        XCTAssertEqual(RetroOptionSection.of("swanstation_NewGroup_NewOption"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("swanstation_Lonely"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("other_core_option"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("pcsx2_upscale_multiplier"), .graphics)
        for key in ["pcsx2_vu0_softfloat", "pcsx2_enable_hw_hacks", "pcsx2_pgs_ssaa", "pcsx2_pgs_other"] {
            XCTAssertNil(RetroOptionSection.of(key), key)
            XCTAssertFalse(RetroOptionSection.sent(key, ps2: true), "\(key) is not sent though an older launcher kept it")
        }
        XCTAssertEqual(RetroOptionSection.of("pcsx2_bios"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("pcsx2_new_option"), .advanced)
        XCTAssertFalse(RetroOptionSection.shown("swanstation_Console_Enable8MBRAM"))
        XCTAssertTrue(RetroOptionSection.shown("swanstation_Console_Region"))
        XCTAssertTrue(RetroOptionSection.sent("swanstation_Console_Region"))
        XCTAssertFalse(RetroOptionSection.sent("swanstation_Console_Enable8MBRAM"))
        XCTAssertTrue(RetroOptionSection.sent("swanstation_GPU_ResolutionScale"), "the menu offers the resolution")
        XCTAssertFalse(RetroOptionSection.sent("swanstation_GPU_PGXPCulling"), "no Graphics row sets it")
        for key in ["swanstation_GPU_TextureFilter", "swanstation_GPU_PGXPEnable", "swanstation_GPU_WidescreenHack", "swanstation_Display_AspectRatio"] {
            XCTAssertEqual(RetroOptionSection.of(key), .graphics, key)
            XCTAssertTrue(RetroOptionSection.sent(key), "\(key): a Graphics row sets it")
            XCTAssertFalse(RetroOptionSection.sent(key, ps2: true), key)
        }
        for key in ["pcsx2_anisotropic_filtering", "pcsx2_widescreen_hint"] {
            XCTAssertEqual(RetroOptionSection.of(key), .graphics, key)
            XCTAssertTrue(RetroOptionSection.sent(key, ps2: true), "\(key): a Graphics row sets it")
        }
        for key in ["swanstation_GPU_TrueColor", "swanstation_GPU_ChromaSmoothing24Bit"] {
            XCTAssertEqual(RetroOptionSection.of(key), .graphics, key)
            XCTAssertFalse(RetroOptionSection.sent(key), "\(key): no row sets it, so a kept value is not sent")
        }
        XCTAssertFalse(RetroOptionSection.sent("pcsx2_bios"), "LRPS2's options go to a PS2 game only")
        XCTAssertTrue(RetroOptionSection.sent("pcsx2_bios", ps2: true))
        XCTAssertFalse(RetroOptionSection.sent("swanstation_Console_Region", ps2: true))
    }

    func testAStartSendsTheKeptValuesTheMenuShowsOverTheGraphicsDefaults() {
        let pgxp = "swanstation_GPU_PGXPEnable"
        let trueColor = "swanstation_GPU_TrueColor"
        let plain: [String: String] = [pgxp: "true", trueColor: "true"]
        XCTAssertEqual(RetroOptionSection.startOptions(kept: [:], ps2: false), plain,
                       "fix wobbly 3D and true colour on; the console's own textures; no widescreen")
        let higher: [String: String] = ["swanstation_GPU_ResolutionScale": "3", "swanstation_CDROM_ReadSpeedup": "2"]
        var higherStart: [String: String] = higher
        higherStart[pgxp] = "true"
        higherStart[trueColor] = "true"
        XCTAssertEqual(RetroOptionSection.startOptions(kept: higher, ps2: false), higherStart,
                       "no smoothing chosen for the player at a higher resolution either")
        let chosen: [String: String] = ["swanstation_GPU_TextureFilter": "xBR", pgxp: "false", trueColor: "false",
                                        "swanstation_GPU_MSAA": "4", "pcsx2_anisotropic_filtering": "disabled"]
        let chosenStart: [String: String] = [trueColor: "true", "swanstation_GPU_TextureFilter": "xBR", pgxp: "false"]
        XCTAssertEqual(RetroOptionSection.startOptions(kept: chosen, ps2: false), chosenStart,
                       "the values the player chose win; true colour has no row; MSAA and PS2 options are not sent")
        let widescreen: [String: String] = ["swanstation_GPU_WidescreenHack": "true", "swanstation_Display_AspectRatio": "16:9"]
        var gameList: [String: String] = widescreen
        gameList["swanstation_CDROM_ReadSpeedup"] = "2"
        var gameStart: [String: String] = widescreen
        gameStart[pgxp] = "true"
        gameStart[trueColor] = "true"
        XCTAssertNil(RetroOptionSection.startOptions(kept: widescreen, ps2: false)["swanstation_GPU_WidescreenHack"],
                     "PS1 widescreen kept for every game (by an older launcher) is not sent")
        XCTAssertNil(RetroOptionSection.startOptions(kept: widescreen, ps2: false)["swanstation_Display_AspectRatio"])
        XCTAssertEqual(RetroOptionSection.startOptions(kept: [:], ps2: false, game: gameList), gameStart,
                       "the game's own widescreen is sent; only per-game options come from the game's list")
        XCTAssertEqual(RetroOptionSection.startOptions(kept: [:], ps2: true), ["pcsx2_anisotropic_filtering": "16x"])
        let ps2Kept: [String: String] = ["pcsx2_anisotropic_filtering": "disabled", "pcsx2_widescreen_hint": "enabled (16:9)",
                                         "pcsx2_vr_mode": "stereoscopic", "pcsx2_enable_hw_hacks": "enabled", "pcsx2_fastboot": "disabled", pgxp: "false"]
        let ps2Start: [String: String] = ["pcsx2_anisotropic_filtering": "disabled", "pcsx2_widescreen_hint": "enabled (16:9)", "pcsx2_fastboot": "disabled"]
        XCTAssertEqual(RetroOptionSection.startOptions(kept: ps2Kept, ps2: true), ps2Start,
                       "stereo and a hardware fix kept by an older launcher are dropped")
    }

    /// LRPS2's options of the real host with no BIOS (Fixtures/retro-host-lrps2-status.json): each
    /// goes to PS2 games only, the curated graphics and Advanced, as on Windows and Linux (Desktop's
    /// test/core/retro_host/retro_status_ps2_test.dart).
    func testLrps2sOptionsGoToPs2GamesOnlyUnderTheCuratedGraphicsAndAdvanced() throws {
        let status = try RetroGraphicsTests.fixture("retro-host-lrps2-status.json", ps2: true)
        let keys = status.orderedOptionKeys
        XCTAssertEqual(keys.count, 68)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("pcsx2_") })
        func inSection(_ section: RetroOptionSection?) -> [String] {
            keys.filter { RetroOptionSection.of($0) == section }.map { String($0.dropFirst("pcsx2_".count)) }
        }
        XCTAssertEqual(inSection(.graphics), ["upscale_multiplier", "widescreen_hint", "anisotropic_filtering"],
                       "the internal resolution and the options the Graphics rows set")
        var advanced: [String] = ["fastboot", "fastcdvd", "hint_language_unlock", "enable_cheats", "use_external_gameindex"]
        let perPort: [String] = ["axis_deadzone", "button_deadzone", "axis_scale", "invert_left_stick", "invert_right_stick", "analog_mode", "enable_rumble"]
        for port in 1...2 {
            for name in perPort { advanced.append("\(name)\(port)") }
        }
        XCTAssertEqual(inSection(.advanced), advanced, "the system, disc speed and controller options")
        let hidden = inSection(nil)
        XCTAssertTrue(Set(hidden).isSuperset(of: ["vr_mode", "vr_depth"]), "AnyPS5 has no VR")
        XCTAssertTrue(Set(hidden).isSuperset(of: ["enable_hw_hacks", "cpu_sprite_size", "force_sprite_position"]), "HW Hacks")
        XCTAssertTrue(Set(hidden).isSuperset(of: ["blending_accuracy", "ee_cycle_rate", "mtvu", "uncapped_framerate_hint", "pgs_disable_mipmaps"]))
        XCTAssertEqual(hidden.count, keys.count - 22, "every other video, emulation and HW Hacks option")
        for key in keys {
            let section = RetroOptionSection.of(key)
            XCTAssertFalse(RetroOptionSection.sent(key), "\(key) is no PS1 option")
            XCTAssertEqual(RetroOptionSection.sent(key, ps2: true), section == .advanced || section == .graphics,
                           "\(key): a kept value goes only to an option the menu shows")
        }
    }

    func testSwanStationsOwnRestartLeavesTheTitle() {
        XCTAssertEqual(RetroOptionSection.title("NTSC-U BIOS (Restart)"), "NTSC-U BIOS")
        XCTAssertEqual(RetroOptionSection.title("Use Per-Frame Audio Batching (Restart) "), "Use Per-Frame Audio Batching")
        XCTAssertEqual(RetroOptionSection.title("Console Region"), "Console Region")
        XCTAssertEqual(RetroOptionSection.title("(Restart)"), "(Restart)")
        XCTAssertEqual(RetroOptionSection.title("Restart Count"), "Restart Count")
    }
}
