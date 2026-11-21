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

    func testTheFiftyOptionsOfTheRealHostFallIntoTheirSectionsInTheHostsOrderTenNotShown() throws {
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
                                              "CPU_ExecutionMode", "CDROM_ReadaheadSectors", "Main_ApplyGameSettings",
                                              "Main_RunaheadFrameCount", "Hacks_OldMDECRoutines"])
        XCTAssertEqual(inSection(.graphics), ["GPU_ResolutionScale", "GPU_UseSoftwareRendererForReadbacks", "GPU_MSAA", "GPU_TrueColor",
                                              "GPU_ScaledDithering", "GPU_DisableInterlacing", "GPU_ForceNTSCTimings",
                                              "Display_Force4_3For24Bit", "GPU_ChromaSmoothing24Bit", "GPU_TextureFilter",
                                              "GPU_WidescreenHack", "GPU_PGXPEnable", "Display_AspectRatio", "Display_CropMode",
                                              "GPU_DownsampleMode", "GPU_ShaderPrecompile"])
        XCTAssertEqual(inSection(nil), ["Display_ShowOSDMessages", "Display_ActiveStartOffset", "Display_ActiveEndOffset",
                                        "Display_LineStartOffset", "Display_LineEndOffset", "CPU_RecompilerICache",
                                        "CPU_RecompilerBlockLinking", "CPU_FastmemMode", "TextureReplacements_EnableVRAMWriteReplacements",
                                        "Console_Enable8MBRAM"])
    }

    func testOptionsTheRecordingDoesNotHaveGoByTheirGroupAndUnknownOnesToAdvanced() {
        XCTAssertEqual(RetroOptionSection.of("swanstation_Controller2_ForceAnalog"), .controller)
        XCTAssertEqual(RetroOptionSection.of("swanstation_ControllerPorts_MultitapMode"), .controller)
        XCTAssertEqual(RetroOptionSection.of("swanstation_BIOS_PathPAL"), .console)
        XCTAssertEqual(RetroOptionSection.of("swanstation_GPU_PGXPCulling"), .graphics)
        XCTAssertEqual(RetroOptionSection.of("swanstation_Audio_Something"), .audio)
        XCTAssertNil(RetroOptionSection.of("swanstation_Controller_ShowCrosshair"))
        XCTAssertNil(RetroOptionSection.of("swanstation_TextureReplacements_Other"))
        XCTAssertEqual(RetroOptionSection.of("swanstation_NewGroup_NewOption"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("swanstation_Lonely"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("other_core_option"), .advanced)
        XCTAssertEqual(RetroOptionSection.of("pcsx2_upscale_multiplier"), .graphics)
        XCTAssertFalse(RetroOptionSection.shown("swanstation_Console_Enable8MBRAM"))
        XCTAssertTrue(RetroOptionSection.shown("swanstation_Console_Region"))
        XCTAssertTrue(RetroOptionSection.sent("swanstation_Console_Region"))
        XCTAssertFalse(RetroOptionSection.sent("swanstation_Console_Enable8MBRAM"))
        XCTAssertTrue(RetroOptionSection.sent("swanstation_GPU_ResolutionScale"), "the menu offers the resolution")
        XCTAssertFalse(RetroOptionSection.sent("swanstation_GPU_PGXPCulling"), "another graphics option waits for a Graphics page")
        XCTAssertFalse(RetroOptionSection.sent("pcsx2_bios"), "LRPS2's options go to a PS2 game only")
        XCTAssertTrue(RetroOptionSection.sent("pcsx2_bios", ps2: true))
        XCTAssertFalse(RetroOptionSection.sent("swanstation_Console_Region", ps2: true))
    }

    func testSwanStationsOwnRestartLeavesTheTitle() {
        XCTAssertEqual(RetroOptionSection.title("NTSC-U BIOS (Restart)"), "NTSC-U BIOS")
        XCTAssertEqual(RetroOptionSection.title("Use Per-Frame Audio Batching (Restart) "), "Use Per-Frame Audio Batching")
        XCTAssertEqual(RetroOptionSection.title("Console Region"), "Console Region")
        XCTAssertEqual(RetroOptionSection.title("(Restart)"), "(Restart)")
        XCTAssertEqual(RetroOptionSection.title("Restart Count"), "Restart Count")
    }
}
